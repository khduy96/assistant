import 'dart:io';

import 'package:flutter/services.dart';

/// A file moved to where the user can reach it.
class PublishedFile {
  const PublishedFile({required this.uri, required this.path});

  /// `content://...`, to open it again with the default app.
  final String uri;

  /// Path to show, like `Download/Trợ lý/anh.jpg`.
  final String path;
}

/// Moves received files into Android's public Download folder, through the
/// native `event_notice/files` channel.
///
/// Files the app writes itself sit in `Android/data/<package>/files`, which
/// Android 11 hid from the Files app and from file pickers: a file received
/// but out of reach is as good as not received. MediaStore is the only way
/// out that needs no storage permission.
class PublicFiles {
  /// [isAndroid] defaults to the platform the app runs on; tests set it.
  PublicFiles({
    this.channel = const MethodChannel('event_notice/files'),
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel channel;
  final bool isAndroid;

  /// Sub-folder of Download, so the app's files do not mix with every other
  /// download.
  static const subDir = 'Trợ lý';

  bool? _supported;

  /// Whether files can be moved into Download here. Not on Android 9 and
  /// older: MediaStore needs full storage access there, not worth it for a
  /// version hardly anyone runs any more, so files stay in the app's folder.
  Future<bool> isSupported() async {
    if (!isAndroid) return false;
    return _supported ??=
        await channel.invokeMethod<bool>('isSupported') ?? false;
  }

  /// Copies [file] into `Download/[subDir]` and deletes the original. Null
  /// when it stays where it is: not Android, or the copy failed.
  Future<PublishedFile?> publish(File file) async {
    if (!isAndroid) return null;
    try {
      final saved = await channel.invokeMapMethod<String, String>(
        'saveToDownloads',
        {'path': file.path, 'subDir': subDir},
      );
      if (saved == null) return null;
      final uri = saved['uri'], path = saved['path'];
      if (uri == null || path == null) return null;
      return PublishedFile(uri: uri, path: path);
    } on PlatformException {
      // Better keep the copy in the app's folder than lose the file.
      return null;
    }
  }

  /// Opens the file at [uri] with the default app.
  Future<bool> openFile(String uri, String name) async {
    if (!isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('openFile', {
            'uri': uri,
            'name': name,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system's Downloads screen: Android has no way to open one
  /// folder that works on every phone, but every phone has this screen.
  Future<bool> openDownloads() async {
    if (!isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('openDownloads') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
