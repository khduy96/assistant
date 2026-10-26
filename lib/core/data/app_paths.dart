import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the app keeps its files on disk.
///
/// Wraps `path_provider` so data sources ask for a file by name and tests can
/// hand them a fixed path instead.
class AppPaths {
  const AppPaths();

  /// Full path of [fileName] in the application support directory, the
  /// folder `reminders.json`, `todos.json`, `notes.json` and `p2p.json` have
  /// always lived in. Creates the directory when it is missing.
  Future<String> supportFile(String fileName) async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }
}
