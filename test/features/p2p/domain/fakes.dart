import 'dart:async';

import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/p2p/domain/entities/outgoing_file.dart';
import 'package:event_notice/features/p2p/domain/entities/p2p_settings.dart';
import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/entities/save_location.dart';
import 'package:event_notice/features/p2p/domain/entities/transfer.dart';
import 'package:event_notice/features/p2p/domain/repositories/p2p_settings_repository.dart';
import 'package:event_notice/features/p2p/domain/repositories/peer_repository.dart';
import 'package:event_notice/features/p2p/domain/repositories/transfer_repository.dart';

final seen = DateTime(2026, 10, 22, 9);

Peer peer(
  String id, {
  String? name,
  String address = '192.168.1.20',
  int port = 45700,
  DateTime? seenAt,
}) => Peer(
  id: id,
  name: name ?? id,
  platform: 'windows',
  address: address,
  port: port,
  seenAt: seenAt ?? seen,
);

Transfer transfer(
  String id, {
  TransferState state = TransferState.running,
  TransferDirection direction = TransferDirection.send,
  int? size = 100,
  int transferred = 0,
}) => Transfer(
  id: id,
  direction: direction,
  fileName: '$id.txt',
  peerName: 'Máy kia',
  size: size,
  startedAt: seen,
  transferred: transferred,
  state: state,
);

OutgoingFile outgoing(String name) =>
    OutgoingFile(name: name, size: 3, open: () => Stream.value([1, 2, 3]));

/// Keeps one [P2pSettings] in memory. Set [loadFailure] or [saveFailure] to
/// make those calls return it; a failed save leaves the settings as they were.
class InMemoryP2pSettingsRepository implements P2pSettingsRepository {
  InMemoryP2pSettingsRepository([P2pSettings? initial])
    : current =
          initial ?? P2pSettings(deviceId: 'dev-1', deviceName: 'Máy này');

  P2pSettings current;
  int saves = 0;
  Failure? loadFailure;
  Failure? saveFailure;

  @override
  Future<Result<P2pSettings>> load() async {
    if (loadFailure case final f?) return Err(f);
    return Ok(current);
  }

  @override
  Future<Result<void>> save(P2pSettings settings) async {
    if (saveFailure case final f?) return Err(f);
    saves++;
    current = settings;
    return const Ok(null);
  }
}

/// Records every call in [calls]. [answers] says who answers a probe at an
/// entry; entries missing from it do not answer. Set [failures] to make a
/// method (by name) return an `Err`.
class FakePeerRepository implements PeerRepository {
  FakePeerRepository({this.log});

  /// Shared with a [FakeTransferRepository] to see the order across both.
  final List<String>? log;
  final calls = <String>[];
  final answers = <String, Peer>{};
  final failures = <String, Failure>{};
  final _sightings = StreamController<PeerSighting>.broadcast(sync: true);

  P2pSettings? startedWith;
  int? servicePort;
  P2pSettings? updatedWith;

  void hear(PeerSighting sighting) => _sightings.add(sighting);

  Result<T> _result<T>(String name, T value) {
    calls.add(name);
    log?.add('peers.$name');
    if (failures[name] case final f?) return Err(f);
    return Ok(value);
  }

  @override
  Future<Result<void>> start(
    P2pSettings settings, {
    required int servicePort,
  }) async {
    startedWith = settings;
    this.servicePort = servicePort;
    return _result('start', null);
  }

  @override
  Future<Result<void>> stop() async => _result('stop', null);

  @override
  Future<Result<void>> updateSettings(P2pSettings settings) async {
    updatedWith = settings;
    return _result('updateSettings', null);
  }

  @override
  Future<Result<void>> announce() async => _result('announce', null);

  @override
  Future<Result<void>> sweep() async => _result('sweep', null);

  @override
  Stream<PeerSighting> get sightings => _sightings.stream;

  @override
  Future<Result<Peer?>> probe(String entry) async =>
      _result('probe $entry', answers[entry]);

  @override
  Future<Result<String>> localAddress() async =>
      _result('localAddress', '192.168.1.10');
}

/// Records every call in [calls]. [send] yields what [sendOutcomes] holds for
/// the file name, or a done transfer. Set [failures] to make a method (by
/// name) return an `Err`.
class FakeTransferRepository implements TransferRepository {
  FakeTransferRepository({this.log});

  /// Shared with a [FakePeerRepository] to see the order across both.
  final List<String>? log;
  final calls = <String>[];
  final failures = <String, Failure>{};
  final sendOutcomes = <String, TransferState>{};
  final _updates = StreamController<Transfer>.broadcast(sync: true);

  P2pSettings? startedWith;
  P2pSettings? updatedWith;
  int port = 45701;

  void emit(Transfer transfer) => _updates.add(transfer);

  Result<T> _result<T>(String name, T value) {
    calls.add(name);
    log?.add('transfers.$name');
    if (failures[name] case final f?) return Err(f);
    return Ok(value);
  }

  @override
  Future<Result<int>> start(P2pSettings settings) async {
    startedWith = settings;
    return _result('start', port);
  }

  @override
  Future<Result<void>> stop() async => _result('stop', null);

  @override
  Future<Result<void>> updateSettings(P2pSettings settings) async {
    updatedWith = settings;
    return _result('updateSettings', null);
  }

  @override
  Stream<Transfer> get updates => _updates.stream;

  @override
  Future<Result<Transfer>> send({
    required Peer peer,
    required OutgoingFile file,
  }) async {
    final state = sendOutcomes[file.name] ?? TransferState.done;
    return _result(
      'send ${file.name} to ${peer.id}',
      transfer(file.name, state: state),
    );
  }

  @override
  Future<Result<void>> respond(String id, {required bool accept}) async =>
      _result('respond $id $accept', null);

  @override
  Future<Result<void>> cancel(String id) async => _result('cancel $id', null);

  @override
  Future<Result<SaveLocation>> saveLocation(String? customDir) async => _result(
    'saveLocation $customDir',
    SaveLocation(directory: customDir ?? 'Downloads/Trợ lý'),
  );

  @override
  Future<Result<bool>> openDownloads() async => _result('openDownloads', true);

  @override
  Future<Result<bool>> openReceived(Transfer transfer) async =>
      _result('openReceived ${transfer.id}', transfer.savedUri != null);
}
