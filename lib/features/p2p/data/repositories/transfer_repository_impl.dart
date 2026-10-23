import 'dart:async';
import 'dart:io';

import '../../../../core/domain/clock.dart';
import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../domain/entities/outgoing_file.dart';
import '../../domain/entities/p2p_settings.dart';
import '../../domain/entities/peer.dart';
import '../../domain/entities/save_location.dart';
import '../../domain/entities/transfer.dart';
import '../../domain/p2p_protocol.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../datasources/file_sender.dart';
import '../datasources/file_server.dart';
import '../datasources/local_device.dart';
import '../datasources/public_files.dart';
import '../datasources/save_folder.dart';
import '../models/transfer_job.dart';

/// [TransferRepository] over the receiving [FileServer] and the
/// [FileSender]; on Android received files are moved on by [PublicFiles].
///
/// Each transfer lives as a mutable [TransferJob] while its bytes move; every
/// change goes out on [updates] as a snapshot.
class TransferRepositoryImpl implements TransferRepository {
  /// [basePort], [portAttempts] and [offerTimeout] replace the
  /// [P2pProtocol] values; tests use any free port and a short timeout.
  TransferRepositoryImpl(
    this._clock, {
    this.device = const LocalDevice(),
    this.saveFolder = const SaveFolder(),
    PublicFiles? publicFiles,
    this.basePort = P2pProtocol.basePort,
    this.portAttempts = P2pProtocol.portAttempts,
    this.offerTimeout = P2pProtocol.offerTimeout,
  }) : publicFiles = publicFiles ?? PublicFiles();

  final Clock _clock;
  final LocalDevice device;
  final SaveFolder saveFolder;
  final PublicFiles publicFiles;
  final int basePort;
  final int portAttempts;
  final Duration offerTimeout;

  final _updates = StreamController<Transfer>.broadcast();

  P2pSettings? _settings;
  FileServer? _server;
  FileSender? _sender;

  /// Transfers not ended yet, by id.
  final Map<String, TransferJob> _active = {};

  /// Incoming files waiting for an answer, by id.
  final Map<String, Completer<bool>> _offers = {};

  @override
  Stream<Transfer> get updates => _updates.stream;

  @override
  Future<Result<int>> start(P2pSettings settings) async {
    _settings = settings;
    final running = _server;
    if (running != null) {
      _sender = _senderFor(settings);
      return Ok(running.port!);
    }
    final server = FileServer(
      settings: () => _settings!,
      platform: device.platformTag,
      onOffer: _onOffer,
      onProgress: _emit,
      onFinished: _finish,
      clock: _clock,
      saveFolder: saveFolder,
      // Does nothing outside Android, see [PublicFiles.publish].
      publish: publicFiles.publish,
      basePort: basePort,
      portAttempts: portAttempts,
    );
    try {
      await server.start();
    } catch (e) {
      // The message is what the user is shown after "Không bật được: ".
      return Err(NetworkFailure('$e', cause: e));
    }
    _server = server;
    _sender = _senderFor(settings);
    return Ok(server.port!);
  }

  @override
  Future<Result<void>> stop() async {
    final server = _server;
    if (server == null) return const Ok(null);
    _server = null;
    _sender = null;
    // No way to move bytes any more: cut everything half done. Flagged
    // before the server closes, so the broken connections end as cancelled
    // rather than failed.
    for (final job in _active.values) {
      job.cancelRequested = true;
    }
    for (final offer in _offers.values) {
      if (!offer.isCompleted) offer.complete(false);
    }
    _offers.clear();
    try {
      await server.stop();
      return const Ok(null);
    } catch (e) {
      return Err(NetworkFailure('File server could not stop', cause: e));
    }
  }

  @override
  Future<Result<void>> updateSettings(P2pSettings settings) async {
    if (_server == null) return const Ok(null);
    _settings = settings;
    _sender = _senderFor(settings);
    return const Ok(null);
  }

  @override
  Future<Result<Transfer>> send({
    required Peer peer,
    required OutgoingFile file,
  }) async {
    final sender = _sender;
    if (sender == null) {
      return const Err(UnexpectedFailure('File transfer is not started'));
    }
    final now = _clock.now();
    final job = TransferJob(
      id: 'out-${now.microsecondsSinceEpoch}-${file.name.hashCode}',
      direction: TransferDirection.send,
      fileName: file.name,
      peerName: peer.name,
      peerId: peer.id,
      size: file.size,
      startedAt: now,
    );
    _active[job.id] = job;
    _emit(job);
    try {
      await sender.send(peer: peer, file: file, job: job, onProgress: _emit);
      job.state = TransferState.done;
    } catch (e) {
      if (e is P2pCancelled || job.cancelRequested) {
        job
          ..state = TransferState.cancelled
          ..problem = TransferProblem.cancelled;
      } else {
        job
          ..state = TransferState.failed
          ..problem = switch (e) {
            P2pRejected() => TransferProblem.rejectedByPeer,
            SocketException() => TransferProblem.unreachable,
            _ => TransferProblem.failed,
          }
          ..problemDetail = '$e';
      }
    }
    _finish(job);
    return Ok(job.snapshot());
  }

  @override
  Future<Result<void>> respond(String id, {required bool accept}) async {
    final offer = _offers.remove(id);
    if (offer == null || offer.isCompleted) return const Ok(null);
    if (!accept) _active[id]?.cancelRequested = true;
    offer.complete(accept);
    return const Ok(null);
  }

  @override
  Future<Result<void>> cancel(String id) async {
    final job = _active[id];
    if (job == null || !job.isActive) return const Ok(null);
    job.cancelRequested = true;
    final offer = _offers.remove(id);
    if (offer != null && !offer.isCompleted) offer.complete(false);
    return const Ok(null);
  }

  @override
  Future<Result<SaveLocation>> saveLocation(String? customDir) async {
    final Directory dir;
    try {
      dir = await saveFolder.resolve(customDir);
    } catch (e) {
      return Err(StorageFailure('No folder for received files', cause: e));
    }
    bool public;
    try {
      public = await publicFiles.isSupported();
    } catch (_) {
      // The native side did not answer: files stay where they are written.
      public = false;
    }
    return Ok(
      SaveLocation(
        directory: dir.path,
        publicFolder: public ? 'Download/${PublicFiles.subDir}' : null,
      ),
    );
  }

  @override
  Future<Result<bool>> openDownloads() async {
    try {
      return Ok(await publicFiles.openDownloads());
    } catch (e) {
      return Err(UnexpectedFailure('Downloads could not open', cause: e));
    }
  }

  @override
  Future<Result<bool>> openReceived(Transfer transfer) async {
    final uri = transfer.savedUri;
    if (uri == null) return const Ok(false);
    try {
      return Ok(await publicFiles.openFile(uri, transfer.fileName));
    } catch (e) {
      return Err(UnexpectedFailure('Received file could not open', cause: e));
    }
  }

  /// Stops the server and closes [updates]. For tests and shutdown; the
  /// repository cannot be used afterwards.
  Future<void> dispose() async {
    await stop();
    await _updates.close();
  }

  static FileSender _senderFor(P2pSettings settings) =>
      FileSender(deviceId: settings.deviceId, deviceName: settings.deviceName);

  /// Called by the server when a file knocks.
  Future<bool> _onOffer(TransferJob job) async {
    final settings = _settings;
    // Arrived while the server was closing: nobody is left to answer.
    if (_server == null || settings == null) return false;
    _active[job.id] = job;
    if (settings.autoAccept) {
      job.state = TransferState.running;
      _emit(job);
      return true;
    }
    final offer = Completer<bool>();
    _offers[job.id] = offer;
    _emit(job);

    final timer = Timer(offerTimeout, () {
      if (!offer.isCompleted) {
        job.problem = TransferProblem.offerExpired;
        offer.complete(false);
      }
    });
    try {
      return await offer.future;
    } finally {
      timer.cancel();
      _offers.remove(job.id);
    }
  }

  void _emit(TransferJob job) {
    if (!_updates.isClosed) _updates.add(job.snapshot());
  }

  void _finish(TransferJob job) {
    _active.remove(job.id);
    _emit(job);
  }
}
