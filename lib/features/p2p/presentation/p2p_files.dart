import '../domain/entities/outgoing_file.dart';

/// Files dropped onto a device card: the ones that can be sent, and how many
/// dropped items were left out because they are folders.
typedef DroppedFiles = ({List<OutgoingFile> files, int skipped});

/// The tab's way to this machine's files: the system pickers, files dropped
/// from the file manager, and the file manager itself. Implemented outside
/// the feature's layers (an adapter wired in DI), so presentation imports
/// neither `dart:io` nor a picker package.
abstract interface class P2pFiles {
  /// Opens the system file picker titled [dialogTitle] and yields the files
  /// chosen, ready to send; empty when the user cancelled.
  Future<List<OutgoingFile>> pickFiles({required String dialogTitle});

  /// Opens the system folder picker titled [dialogTitle] and yields the
  /// folder chosen, or null when the user cancelled.
  Future<String?> pickDirectory({required String dialogTitle});

  /// The files at [paths], in order, ready to send. Folders are left out and
  /// counted in `skipped`: the receiving side only understands single files.
  Future<DroppedFiles> filesAt(List<String> paths);

  /// Opens [path] in the system file manager; with [select], opens its folder
  /// and points at it. Throws when the file manager could not be started; the
  /// error is shown to the user as is.
  Future<void> openInFileManager(String path, {bool select = false});
}
