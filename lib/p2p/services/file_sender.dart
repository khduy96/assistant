import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/peer.dart';
import '../models/transfer.dart';

/// Nguồn dữ liệu một tệp cần gửi, tách khỏi file_picker để bên gọi có thể đưa
/// vào tệp trên đĩa (desktop) hay stream từ content-URI (Android) đều được.
class OutgoingFile {
  OutgoingFile({
    required this.name,
    required this.size,
    required this.open,
  });

  final String name;

  /// Dung lượng; null khi trình chọn tệp không cho biết.
  final int? size;
  final Stream<List<int>> Function() open;

  static OutgoingFile fromFile(File file, {int? size}) => OutgoingFile(
        name: file.uri.pathSegments.last,
        size: size ?? file.lengthSync(),
        open: file.openRead,
      );
}

/// Đẩy một tệp sang thiết bị khác qua HTTP POST, báo tiến trình theo từng khối.
class FileSender {
  FileSender({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  /// Chờ kết nối lâu nhất bấy nhiêu; sau khi đã nối thì không giới hạn nữa vì
  /// tệp lớn có thể chạy hàng phút.
  static const _connectTimeout = Duration(seconds: 10);

  Future<void> send({
    required Peer peer,
    required OutgoingFile file,
    required TransferTask task,
    required void Function(TransferTask task) onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = await client.postUrl(peer.uri('/upload'));
      request.headers
        ..set('x-device-id', deviceId)
        ..set('x-device-name', base64Url.encode(utf8.encode(deviceName)))
        ..set('x-file-name', base64Url.encode(utf8.encode(file.name)))
        ..contentType = ContentType.binary;
      final size = file.size;
      if (size != null) {
        request.headers.set('x-file-size', '$size');
        request.contentLength = size;
      }
      // Tên máy gửi cũng phải đọc được ở dạng thường cho log/server khác.
      request.headers.set('x-device-name-plain', _asciiOnly(deviceName));

      await request.addStream(_counted(file.open(), task, onProgress));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.forbidden) {
        throw const P2pRejected();
      }
      if (response.statusCode != HttpStatus.ok) {
        throw P2pFailed('Máy nhận trả về ${response.statusCode}: $body');
      }
      task.state = TransferState.done;
    } finally {
      client.close(force: true);
    }
  }

  /// Bọc stream của tệp để đếm byte đã đẩy đi và chặn lại khi người dùng huỷ.
  Stream<List<int>> _counted(
    Stream<List<int>> source,
    TransferTask task,
    void Function(TransferTask task) onProgress,
  ) async* {
    await for (final chunk in source) {
      if (task.cancelRequested) {
        // Ném lỗi ở đây làm HttpClientRequest đứt kết nối, bên nhận thấy tệp
        // dở và tự xoá phần .part.
        throw const P2pCancelled();
      }
      yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      task.transferred += chunk.length;
      onProgress(task);
    }
  }

  static String _asciiOnly(String value) =>
      value.replaceAll(RegExp(r'[^\x20-\x7e]'), '?');
}

class P2pRejected implements Exception {
  const P2pRejected();
  @override
  String toString() => 'Thiết bị kia đã từ chối nhận';
}

class P2pCancelled implements Exception {
  const P2pCancelled();
  @override
  String toString() => 'Đã huỷ';
}

class P2pFailed implements Exception {
  const P2pFailed(this.message);
  final String message;
  @override
  String toString() => message;
}
