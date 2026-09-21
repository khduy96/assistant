import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens (and migrates) the single SQLite file shared by desktop and mobile.
class AppDatabase {
  AppDatabase._({String? path}) : _overridePath = path;

  static final AppDatabase instance = AppDatabase._();

  /// Opens the schema at an explicit path instead of the app support folder,
  /// so tests can run the real migrations against a throwaway file.
  @visibleForTesting
  factory AppDatabase.atPath(String path) => AppDatabase._(path: path);

  final String? _overridePath;

  Database? _db;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Must be called once before `runApp` so the ffi engine is registered.
  static void initPlatform() {
    if (_isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<Database> get database async => _db ??= await _open();

  static Future<Directory> _baseDirectory() async {
    final dir = _isDesktop
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  Future<Database> _open() async {
    final path = _overridePath ??
        p.join((await _baseDirectory()).path, 'clipboard_history.db');

    return openDatabase(
      path,
      version: 4,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createV1(db);
        await _upgradeToV2(db);
        await _upgradeToV3(db);
        await _upgradeToV4(db);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) await _upgradeToV2(db);
        if (from < 3) await _upgradeToV3(db);
        if (from < 4) await _upgradeToV4(db);
      },
    );
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE clips (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        copied_at INTEGER,
        is_saved INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        group_id TEXT REFERENCES groups(id) ON DELETE SET NULL,
        note TEXT,
        copy_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_clips_created ON clips(created_at DESC)');
    await db.execute('CREATE INDEX idx_clips_state ON clips(is_saved, is_pinned)');
    await db.execute('CREATE INDEX idx_clips_group ON clips(group_id)');
  }

  /// v2 adds Back4App sync bookkeeping, soft deletes and file attachments.
  Future<void> _upgradeToV2(Database db) async {
    const clipColumns = [
      'deleted_at INTEGER',
      'remote_id TEXT',
      'dirty INTEGER NOT NULL DEFAULT 1',
      'file_name TEXT',
      'file_size INTEGER',
      'file_mime TEXT',
      'local_path TEXT',
      'remote_url TEXT',
    ];
    for (final column in clipColumns) {
      await db.execute('ALTER TABLE clips ADD COLUMN $column');
    }

    const groupColumns = [
      'updated_at INTEGER',
      'deleted_at INTEGER',
      'remote_id TEXT',
      'dirty INTEGER NOT NULL DEFAULT 1',
    ];
    for (final column in groupColumns) {
      await db.execute('ALTER TABLE groups ADD COLUMN $column');
    }
    await db.execute('UPDATE groups SET updated_at = created_at');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_clips_dirty ON clips(dirty)');
    await db.execute('CREATE INDEX idx_clips_deleted ON clips(deleted_at)');
  }

  /// v3 drops tombstones: a delete now removes the row here and issues a
  /// DELETE on Back4App, queued in `pending_deletes` when offline.
  Future<void> _upgradeToV3(Database db) async {
    await db.execute('''
      CREATE TABLE pending_deletes (
        remote_id TEXT PRIMARY KEY,
        class_name TEXT NOT NULL,
        queued_at INTEGER NOT NULL
      )
    ''');
    // Rows left over from the tombstone era are gone for good.
    await db.delete('clips', where: 'deleted_at IS NOT NULL');
    await db.delete('groups', where: 'deleted_at IS NOT NULL');
  }

  /// v4 removes the attachment feature. File clips are dropped; the copies the
  /// app kept under `attachments/` stay on disk for the user to salvage.
  Future<void> _upgradeToV4(Database db) async {
    await db.delete('clips', where: 'file_name IS NOT NULL');
  }

  @visibleForTesting
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
