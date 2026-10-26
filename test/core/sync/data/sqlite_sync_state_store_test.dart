import 'dart:io';

import 'package:event_notice/core/data/app_database.dart';
import 'package:event_notice/core/data/sqlite_sync_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late AppDatabase db;
  late SqliteSyncStateStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_state_test');
    db = AppDatabase.atPath('${dir.path}/test.db');
    store = SqliteSyncStateStore(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('đọc được dòng settings do bản cũ ghi, đúng key nguyên văn', () async {
    final raw = await db.database;
    await raw.insert('settings', {'key': 'sync_cursor_nha', 'value': 'iso'});
    await raw.insert('settings', {'key': 'sync_req_2026-10', 'value': '41'});
    await raw.insert('settings', {'key': 'sync_meta_bump_nha', 'value': null});

    expect(await store.read('sync_cursor_nha'), 'iso');
    expect(await store.read('sync_req_2026-10'), '41');
    // A NULL value reads as empty, like the old loadSettings did.
    expect(await store.read('sync_meta_bump_nha'), '');
    expect(await store.readAll(), {
      'sync_cursor_nha': 'iso',
      'sync_req_2026-10': '41',
      'sync_meta_bump_nha': '',
    });
  });

  test('key chưa có thì read trả null', () async {
    expect(await store.read('sync_inflight'), isNull);
    expect(await store.readAll(), isEmpty);
  });

  test('write ghi đè, lưu vào bảng settings', () async {
    await store.write('sync_inflight', '["Clip/a"]');
    await store.write('sync_inflight', '[]');

    expect(await store.read('sync_inflight'), '[]');
    final rows = await (await db.database).query('settings');
    expect(rows, [
      {'key': 'sync_inflight', 'value': '[]'},
    ]);
  });
}
