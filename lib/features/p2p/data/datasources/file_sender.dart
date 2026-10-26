import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/entities/outgoing_file.dart';
import '../../domain/entities/peer.dart';
import '../../domain/entities/transfer.dart';
import '../../domain/p2p_protocol.dart';
import '../models/transfer_job.dart';

/// [file] on disk as a file to send. [size] defaults to its length.
OutgoingFile outgoingFromFile(File file, {int? size}) => OutgoingFile(
  name: file.uri.pathSegments.last,
  size: size ?? file.lengthSync(),
  open: file.openRead,
);

/// Pushes a file to another device with an HTTP POST, reporting progress
/// chunk by chunk.
class FileSender {
  FileSender({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  /// Sends [file] to [peer], counting bytes into [job] and calling
  /// [onProgress] after each chunk. Sets [job] done when the other side
  /// confirmed. Throws [P2pRejected] when it declined, [P2pCancelled] when
  /// [TransferJob.cancelRequested] was set, [P2pFailed] on another answer,
  /// and whatever the socket throws when the device cannot be reached.
  Future<void> send({
    required Peer peer,
    required OutgoingFile file,
    required TransferJob job,
    required void Function(TransferJob job) onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = P2pProtocol.sendConnectTimeout;
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
      // The sender's name must also be readable as plain text, for logs and
      // other servers.
      request.headers.set('x-device-name-plain', _asciiOnly(deviceName));

      await request.addStream(_counted(file.open(), job, onProgress));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.forbidden) {
        throw const P2pRejected();
      }
      if (response.statusCode != HttpStatus.ok) {
        throw P2pFailed('Máy nhận trả về ${response.statusCode}: $body');
      }
      job.state = TransferState.done;
    } finally {
      client.close(force: true);
    }
  }

  /// Wraps the file's stream to count the bytes pushed and to stop when the
  /// user cancels. A transformer rather than `async*`, so a cancel from the
  /// request side reaches the file stream at once.
  Stream<List<int>> _counted(
    Stream<List<int>> source,
    TransferJob job,
    void Function(TransferJob job) onProgress,
  ) => source.transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        if (job.cancelRequested) {
          // An error here breaks the HTTP request, so the receiver sees a
          // partial file and deletes its .part.
          sink
            ..addError(const P2pCancelled())
            ..close();
          return;
        }
        sink.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
        job.transferred += chunk.length;
        onProgress(job);
      },
    ),
  );

  static String _asciiOnly(String value) =>
      value.replaceAll(RegExp(r'[^\x20-\x7e]'), '?');
}

/// The receiving device declined the file.
class P2pRejected implements Exception {
  const P2pRejected();
  @override
  String toString() => 'Thiết bị kia đã từ chối nhận';
}

/// The user cancelled while the file was being sent.
class P2pCancelled implements Exception {
  const P2pCancelled();
  @override
  String toString() => 'Đã huỷ';
}

/// The receiving device answered something other than success.
class P2pFailed implements Exception {
  const P2pFailed(this.message);
  final String message;
  @override
  String toString() => message;
}
