import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../../features/p2p/data/datasources/file_sender.dart';
import '../../../features/p2p/domain/entities/outgoing_file.dart';
import '../../../features/p2p/presentation/p2p_files.dart';

/// The "Gửi tệp" tab's [P2pFiles]: the `file_picker` dialogs, files dropped
/// from the file manager read from disk, and the file manager started as a
/// process (desktop only; the tab never asks for it on Android).
class P2pFilesBridge implements P2pFiles {
  const P2pFilesBridge();

  @override
  Future<List<OutgoingFile>> pickFiles({required String dialogTitle}) async {
    final picked = await FilePicker.pickFiles(dialogTitle: dialogTitle);
    final files = <OutgoingFile>[];
    for (final file in picked) {
      files.add(
        OutgoingFile(
          name: file.name,
          size: file.lengthSync() ?? await file.length(),
          open: file.readAsByteStream,
        ),
      );
    }
    return files;
  }

  @override
  Future<String?> pickDirectory({required String dialogTitle}) =>
      FilePicker.getDirectoryPath(dialogTitle: dialogTitle);

  @override
  Future<DroppedFiles> filesAt(List<String> paths) async {
    final files = <OutgoingFile>[];
    var skipped = 0;
    for (final path in paths) {
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
        skipped++;
        continue;
      }
      files.add(outgoingFromFile(File(path)));
    }
    return (files: files, skipped: skipped);
  }

  @override
  Future<void> openInFileManager(String path, {bool select = false}) async {
    if (Platform.isWindows) {
      // explorer.exe exits with a non-zero code even when it opened the
      // folder, so only an exception counts as a failure.
      await Process.run('explorer.exe', select ? ['/select,', path] : [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', select ? ['-R', path] : [path]);
    } else {
      await Process.run('xdg-open', [select ? File(path).parent.path : path]);
    }
  }
}
