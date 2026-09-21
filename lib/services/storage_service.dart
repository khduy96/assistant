import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/reminder.dart';

/// Persists reminders to a JSON file in the app's support directory.
class StorageService {
  File? _file;

  Future<File> _target() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _file = File('${dir.path}${Platform.pathSeparator}reminders.json');
  }

  Future<List<Reminder>> load() async {
    final file = await _target();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List;
      return raw
          .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupted file: start clean rather than blocking the app.
      return [];
    }
  }

  Future<void> save(List<Reminder> reminders) async {
    final file = await _target();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(reminders.map((r) => r.toJson()).toList()),
    );
  }
}
