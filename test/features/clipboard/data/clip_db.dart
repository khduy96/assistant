import 'dart:io';

import 'package:event_notice/core/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points sqflite at the ffi engine, as the desktop app does.
void useFfiSqlite() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// A throwaway clipboard database with the real schema and migrations.
class ClipDb {
  ClipDb._(this.dir, this.db);

  static Future<ClipDb> open() async {
    final dir = await Directory.systemTemp.createTemp('clip_data_test');
    return ClipDb._(dir, AppDatabase.atPath('${dir.path}/test.db'));
  }

  final Directory dir;
  final AppDatabase db;

  /// The raw connection, for writing rows the way an older build did.
  Future<Database> get raw => db.database;

  Future<void> close() async {
    await db.close();
    await dir.delete(recursive: true);
  }
}
