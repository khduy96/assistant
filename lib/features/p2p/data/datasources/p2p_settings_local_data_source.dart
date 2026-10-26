import 'dart:convert';
import 'dart:io';

import '../../../../core/data/app_paths.dart';

/// Reads and writes `p2p.json` in the application support directory: one
/// JSON object holding this device's identity and the file-transfer options.
class P2pSettingsLocalDataSource {
  /// [path] replaces the default location; tests pass their own file.
  P2pSettingsLocalDataSource({String? path, this.paths = const AppPaths()})
    : _file = path == null ? null : File(path);

  static const String fileName = 'p2p.json';

  final AppPaths paths;
  File? _file;

  /// The last write in flight, so two quick saves never interleave.
  Future<void> _writing = Future<void>.value();

  Future<File> _target() async {
    final cached = _file;
    if (cached != null) return cached;
    return _file = File(await paths.supportFile(fileName));
  }

  /// The saved object. A missing file, or one that is not a JSON object,
  /// reads as empty, so a broken file never blocks the app.
  Future<Map<String, dynamic>> load() async {
    final file = await _target();
    if (!await file.exists()) return <String, dynamic>{};
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      // Corrupted file: start again from the defaults instead of blocking.
      return <String, dynamic>{};
    }
  }

  /// Writes [json] on one line, as the file has always been written. The
  /// text is built right away and waits for the write before it.
  Future<void> save(Map<String, Object?> json) {
    final text = jsonEncode(json);
    final write = _writing.then((_) async {
      final file = await _target();
      await file.writeAsString(text);
    });
    // A failed write is reported to its caller; the next one still runs.
    _writing = write.then((_) {}, onError: (_) {});
    return write;
  }
}
