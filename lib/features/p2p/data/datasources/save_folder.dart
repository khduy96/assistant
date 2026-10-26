import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Picks the folder received files are written to.
class SaveFolder {
  const SaveFolder();

  /// Sub-folder made inside the base folder, so the app's files do not mix
  /// with everything else there.
  static const subDir = 'Trợ lý';

  /// Where files go when the user has not chosen a folder: `Trợ lý` inside
  /// Downloads on desktop. Android does not let apps write straight into
  /// Download without full storage access, so there it is the app's own
  /// external folder (still visible in a file manager). Created when missing.
  Future<Directory> defaultDir() async {
    Directory? base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    } else {
      try {
        base = await getDownloadsDirectory();
      } catch (_) {
        base = null;
      }
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$subDir');
    await dir.create(recursive: true);
    return dir;
  }

  /// [custom] when it is set and can be created, otherwise [defaultDir].
  Future<Directory> resolve(String? custom) async {
    if (custom != null && custom.trim().isNotEmpty) {
      final dir = Directory(custom);
      try {
        await dir.create(recursive: true);
        return dir;
      } catch (_) {
        // The chosen folder cannot be written any more (drive or SD card
        // removed).
      }
    }
    return defaultDir();
  }
}
