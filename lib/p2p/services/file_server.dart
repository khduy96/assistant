import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/transfer.dart';
import 'p2p_settings.dart';
import 'public_files.dart';

/// Máy chủ HTTP nhỏ chạy ngay trong app để nhận tệp từ thiết bị khác.
///
/// Giao thức cố tình đơn giản để hai bên chỉ cần dart:io thuần:
///   GET  /info    → thông tin thiết bị, dùng để kiểm tra "còn sống" không
///   POST /upload  → thân request chính là nội dung tệp, tên/dung lượng nằm ở
///                   header (tên đi qua base64 vì header HTTP chỉ nhận ASCII)
class FileServer {
  FileServer({
    required this.settings,
    required this.onOffer,
    required this.onProgress,
    required this.onFinished,
    this.publish,
  });

  /// Cổng HTTP mặc định; nếu bị chiếm thì thử vài cổng kế tiếp.
  static const basePort = 45700;
  static const _portAttempts = 5;

  final P2pSettings settings;

  /// Hỏi người dùng có nhận tệp này không. Trả về false là từ chối.
  final Future<bool> Function(TransferTask task) onOffer;

  /// Gọi liên tục trong lúc ghi để UI vẽ lại thanh tiến trình.
  final void Function(TransferTask task) onProgress;
  final void Function(TransferTask task) onFinished;

  /// Bước dọn chỗ sau khi ghi xong: trên Android, tệp được chuyển tiếp ra thư
  /// mục Download công cộng. Null nghĩa là để nguyên tại chỗ đã ghi.
  final Future<PublishedFile?> Function(File saved)? publish;

  HttpServer? _server;
  int _counter = 0;

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    SocketException? last;
    for (var i = 0; i < _portAttempts; i++) {
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
        return _json(request, {
          'id': settings.deviceId,
          'name': settings.deviceName,
          'platform': P2pSettings.platformTag,
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
        // Bên kia đã ngắt kết nối.
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
    final fileName = _decodeName(headers.value('x-file-name')) ?? 'tep-nhan-duoc';
    final declared = int.tryParse(headers.value('x-file-size') ?? '');
    final size = declared ?? (request.contentLength >= 0 ? request.contentLength : null);

    final task = TransferTask(
      id: 'in-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
      direction: TransferDirection.receive,
      fileName: fileName,
      peerName: _decodeText(headers.value('x-device-name')) ??
          headers.value('x-device-name-plain') ??
          'Thiết bị lạ',
      peerId: headers.value('x-device-id'),
      size: size,
      state: TransferState.pending,
    );

    if (!await onOffer(task)) {
      task.state = TransferState.cancelled;
      task.error ??= 'Đã từ chối';
      onFinished(task);
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    task.state = TransferState.running;
    onProgress(task);

    final dir = await settings.resolveSaveDir();
    final target = await _freeName(dir, fileName);
    // Ghi ra .part rồi mới đổi tên: đứt giữa chừng không để lại tệp nửa vời
    // trông như đã tải xong.
    final partial = File('${target.path}.part');
    IOSink? sink;
    try {
      sink = partial.openWrite();
      await for (final chunk in request) {
        if (task.cancelRequested) throw const _Cancelled();
        sink.add(chunk);
        task.transferred += chunk.length;
        onProgress(task);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await partial.rename(target.path);

      task.savedPath = target.path;
      // Đưa tệp ra chỗ người dùng với tới được; hỏng thì vẫn còn bản vừa ghi.
      final published = await publish?.call(target);
      if (published != null) {
        task.savedPath = published.path;
        task.savedUri = published.uri;
      }
      task.state = TransferState.done;
      onFinished(task);
      await _json(request, {'ok': true, 'saved': target.path});
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {
        // Sink hỏng sẵn rồi.
      }
      if (await partial.exists()) await partial.delete();
      final cancelled = e is _Cancelled || task.cancelRequested;
      task.state = cancelled ? TransferState.cancelled : TransferState.failed;
      task.error = cancelled ? 'Đã huỷ' : '$e';
      onFinished(task);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // Kết nối đã đứt — đó thường chính là nguyên nhân vào đây.
      }
    }
  }

  /// Header HTTP chỉ nhận ASCII nên tên tệp và tên máy đi qua base64 utf8.
  static String? _decodeText(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return utf8.decode(base64Url.decode(encoded));
    } catch (_) {
      return null;
    }
  }

  static String? _decodeName(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final name = utf8.decode(base64Url.decode(encoded));
      return sanitize(name);
    } catch (_) {
      return null;
    }
  }

  /// Chặn tên tệp do máy khác gửi tới làm ta ghi ra ngoài thư mục nhận.
  static String sanitize(String name) {
    // Mọi dấu phân cách thư mục thành '_', nên "../../x" không còn trỏ ra
    // ngoài được; các ký tự Windows cấm cũng dọn luôn cho mọi nền tảng.
    var safe = name.replaceAll(RegExp('[\\\\/\\x00-\\x1f]'), '_');
    safe = safe.replaceAll(RegExp(r'[:*?"<>|]'), '_').trim();
    while (safe.startsWith('.')) {
      safe = safe.substring(1);
    }
    safe = safe.trim();
    if (safe.isEmpty) return 'tep-nhan-duoc';
    return safe.length <= 120 ? safe : safe.substring(safe.length - 120);
  }

  /// "anh.jpg" đã có thì thành "anh (1).jpg" — không đè tệp cũ bao giờ.
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
