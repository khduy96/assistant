import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sync/domain/sync_state_store.dart';
import 'app_database.dart';

/// [SyncStateStore] on the `settings` table of the clipboard database, where
/// the sync engine has always kept its cursors and counters. The table also
/// holds per-device user choices such as `sync_auto`, so resetting the
/// engine's keys must not wipe them.
class SqliteSyncStateStore implements SyncStateStore {
  SqliteSyncStateStore(this._appDb);

  final AppDatabase _appDb;

  Future<Database> get _db => _appDb.database;

  @override
  Future<Map<String, String>> readAll() async {
    final db = await _db;
    final rows = await db.query('settings');
    return {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
  }

  @override
  Future<String?> read(String key) async {
    final db = await _db;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['value'] as String?) ?? '';
  }

  @override
  Future<void> write(String key, String value) async {
    final db = await _db;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
