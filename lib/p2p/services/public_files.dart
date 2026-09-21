import 'dart:io';

import 'package:flutter/services.dart';

/// Một tệp đã được đưa ra chỗ người dùng với tới được.
class PublishedFile {
  const PublishedFile({required this.uri, required this.path});

  /// `content://...` để mở lại bằng app mặc định.
  final String uri;

  /// Đường dẫn để hiển thị, kiểu `Download/Trợ lý/anh.jpg`.
  final String path;
}

/// Đưa tệp nhận được ra thư mục Download công cộng của Android.
///
/// Tệp app tự ghi nằm trong `Android/data/<gói>/files`, mà từ Android 11
/// Google đã chặn đường đó khỏi app Files lẫn hộp thoại chọn tệp — nhận xong
/// mà không lấy ra được thì coi như chưa nhận. MediaStore là lối ra duy nhất
/// không phải xin quyền bộ nhớ.
class PublicFiles {
  static const _channel = MethodChannel('event_notice/files');

  /// Thư mục con trong Download, để tệp của app không lẫn vào đống tải về.
  static const subDir = 'Trợ lý';

  static bool? _supported;

  /// Máy này có đưa tệp ra Download được không. Android 9 trở xuống thì không:
  /// MediaStore đời đó cần quyền ghi toàn bộ bộ nhớ, không đáng đánh đổi cho
  /// một phiên bản gần như không còn ai dùng — tệp cứ nằm trong thư mục riêng
  /// của app như cũ.
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    return _supported ??=
        await _channel.invokeMethod<bool>('isSupported') ?? false;
  }

  /// Chép [file] ra `Download/[subDir]` rồi xoá bản tạm.
  static Future<PublishedFile?> publish(File file) async {
    if (!Platform.isAndroid) return null;
    try {
      final saved = await _channel.invokeMapMethod<String, String>(
        'saveToDownloads',
        {'path': file.path, 'subDir': subDir},
      );
      if (saved == null) return null;
      final uri = saved['uri'], path = saved['path'];
      if (uri == null || path == null) return null;
      return PublishedFile(uri: uri, path: path);
    } on PlatformException {
      // Không đưa ra được thì giữ nguyên bản trong thư mục app, còn hơn mất.
      return null;
    }
  }

  /// Mở tệp bằng app mặc định của máy.
  static Future<bool> openFile(String uri, String name) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openFile', {'uri': uri, 'name': name}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Mở màn hình Tải xuống của hệ thống — Android không có cách mở đúng một
  /// thư mục cho mọi máy, nhưng màn hình này thì máy nào cũng có.
  static Future<bool> openDownloads() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openDownloads') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
