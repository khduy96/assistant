import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/domain/clock.dart';
import '../../domain/entities/p2p_settings.dart';
import '../../domain/entities/transfer.dart';
import '../../domain/p2p_protocol.dart';
import '../models/transfer_job.dart';
import 'public_files.dart';
import 'save_folder.dart';

/// A small HTTP server inside the app that receives files from other
/// devices.
///
/// The protocol is kept simple on purpose, so both sides only need dart:io:
///   GET  /info    → who this device is, used to check it is alive
///   POST /upload  → the request body is the file; its name and size are in
///                   headers (the name in base64, as HTTP headers only take
///                   ASCII)
class FileServer {
  FileServer({
    required this.settings,
    required this.platform,
    required this.onOffer,
    required this.onProgress,
    required this.onFinished,
    required this.clock,
    this.saveFolder = const SaveFolder(),
    this.publish,
    this.basePort = P2pProtocol.basePort,
    this.portAttempts = P2pProtocol.portAttempts,
  });

  /// The settings in effect, read on every request: the id and name `/info`
  /// gives, and the folder received files go to.
  final P2pSettings Function() settings;

  /// Platform tag `/info` gives, see `LocalDevice.platformTag`.
  final String platform;

  /// Asks whether to take this file. False declines it.
  final Future<bool> Function(TransferJob job) onOffer;

  /// Called again and again while writing, and once when accepted.
  final void Function(TransferJob job) onProgress;
  final void Function(TransferJob job) onFinished;

  final Clock clock;
  final SaveFolder saveFolder;

  /// Tidying up once a file is written: on Android it is moved on to the
  /// public Download folder. Null leaves it where it was written.
  final Future<PublishedFile?> Function(File saved)? publish;

  /// First port tried; when taken, the next ones are, [portAttempts] in all.
  /// Tests pass 0 for any free port.
  final int basePort;
  final int portAttempts;

  HttpServer? _server;
  int _counter = 0;

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    SocketException? last;
    for (var i = 0; i < portAttempts; i++) {
      try {
        final server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          basePort + i,
          shared: false,
        );
        _server = server;
        server.listen(_handle, onError: (Object e) => debugPrint('P2P: $e'));
        return;
      } on SocketException catch (e) {
        last = e;
      }
    }
    throw last ?? const SocketException('Không mở được cổng nhận tệp');
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/info') {
        final current = settings();
        return _json(request, {
          'id': current.deviceId,
          'name': current.deviceName,
          'platform': platform,
        });
      }
      if (request.method == 'POST' && request.uri.path == '/upload') {
        return await _receive(request);
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      debugPrint('P2P: lỗi xử lý request — $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // The other side hung up.
      }
    }
  }

  Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _receive(HttpRequest request) async {
    final headers = request.headers;
    final fileName =
        _decodeName(headers.value('x-file-name')) ?? 'tep-nhan-duoc';
    final declared = int.tryParse(headers.value('x-file-size') ?? '');
    final size =
        declared ?? (request.contentLength >= 0 ? request.contentLength : null);

    final now = clock.now();
    final job = TransferJob(
      id: 'in-${now.microsecondsSinceEpoch}-${_counter++}',
      direction: TransferDirection.receive,
      fileName: fileName,
      peerName:
          _decodeText(headers.value('x-device-name')) ??
          headers.value('x-device-name-plain') ??
          'Thiết bị lạ',
      peerId: headers.value('x-device-id'),
      size: size,
      startedAt: now,
      state: TransferState.pending,
    );

    if (!await onOffer(job)) {
      job.state = TransferState.cancelled;
      // An offer that ran out of time says so already.
      job.problem ??= TransferProblem.declined;
      onFinished(job);
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    job.state = TransferState.running;
    onProgress(job);

    final dir = await saveFolder.resolve(settings().saveDir);
    final target = await _freeName(dir, fileName);
    // Write to .part and rename at the end: a transfer cut halfway never
    // leaves a half file that looks complete.
    final partial = File('${target.path}.part');
    IOSink? sink;
    try {
      sink = partial.openWrite();
      await for (final chunk in request) {
        if (job.cancelRequested) throw const _Cancelled();
        sink.add(chunk);
        job.transferred += chunk.length;
        onProgress(job);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await partial.rename(target.path);

      job.savedPath = target.path;
      // Move the file where the user can reach it; if that fails, the copy
      // just written is still there.
      final published = await publish?.call(target);
      if (published != null) {
        job.savedPath = published.path;
        job.savedUri = published.uri;
      }
      job.state = TransferState.done;
      onFinished(job);
      await _json(request, {'ok': true, 'saved': target.path});
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {
        // The sink was broken already.
      }
      if (await partial.exists()) await partial.delete();
      final cancelled = e is _Cancelled || job.cancelRequested;
      job.state = cancelled ? TransferState.cancelled : TransferState.failed;
      job.problem = cancelled
          ? TransferProblem.cancelled
          : TransferProblem.failed;
      job.problemDetail = cancelled ? null : '$e';
      onFinished(job);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // The connection is gone, which is usually why we are here.
      }
    }
  }

  /// HTTP headers only take ASCII, so file and device names come as base64
  /// of their UTF-8 bytes.
  static String? _decodeText(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return utf8.decode(base64Url.decode(encoded));
    } catch (_) {
      return null;
    }
  }

  static String? _decodeName(String? encoded) {
    final name = _decodeText(encoded);
    return name == null ? null : sanitize(name);
  }

  /// Keeps a file name sent by another device from writing outside the
  /// receiving folder.
  static String sanitize(String name) {
    // Every path separator becomes '_', so "../../x" cannot point outside
    // any more; characters Windows forbids go too, on every platform.
    var safe = name.replaceAll(RegExp('[\\\\/\\x00-\\x1f]'), '_');
    safe = safe.replaceAll(RegExp(r'[:*?"<>|]'), '_').trim();
    while (safe.startsWith('.')) {
      safe = safe.substring(1);
    }
    safe = safe.trim();
    if (safe.isEmpty) return 'tep-nhan-duoc';
    return safe.length <= 120 ? safe : safe.substring(safe.length - 120);
  }

  /// "anh.jpg" taken already becomes "anh (1).jpg": an old file is never
  /// overwritten.
  static Future<File> _freeName(Directory dir, String name) async {
    final sep = Platform.pathSeparator;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = File('${dir.path}$sep$name');
    var i = 1;
    while (await candidate.exists() ||
        await File('${candidate.path}.part').exists()) {
      candidate = File('${dir.path}$sep$stem ($i)$ext');
      i++;
    }
    return candidate;
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
