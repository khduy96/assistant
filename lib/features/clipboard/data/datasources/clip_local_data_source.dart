import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/data/app_database.dart';
import '../models/clip_group_model.dart';
import '../models/clip_model.dart';

/// Reads and writes the `clips`, `groups` and `pending_deletes` tables of the
/// clipboard database.
///
/// IO only: which rows to keep, when to queue a server delete and who hears
/// about a change is the repository's business.
class ClipLocalDataSource {
  ClipLocalDataSource(this._appDb);

  final AppDatabase _appDb;

  static const String clipsTable = 'clips';
  static const String groupsTable = 'groups';
  static const String _pendingTable = 'pending_deletes';

  /// Ids per `IN (...)` query, well under SQLite's oldest limit of 999 bound
  /// variables.
  static const int _chunk = 500;

  Future<Database> get _db => _appDb.database;

  // ---------------------------------------------------------------- clips

  /// Every clip, newest capture first.
  Future<List<ClipModel>> clips() async {
    final db = await _db;
    final rows = await db.query(clipsTable, orderBy: 'created_at DESC');
    return rows.map(ClipModel.fromMap).toList();
  }

  Future<ClipModel?> clipById(String id) async {
    final db = await _db;
    final rows = await db.query(
      clipsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ClipModel.fromMap(rows.first);
  }

  /// A clip whose content is exactly [content], or null.
  Future<ClipModel?> clipByContent(String content) async {
    final db = await _db;
    final rows = await db.query(
      clipsTable,
      where: 'content = ?',
      whereArgs: [content],
      limit: 1,
    );
    return rows.isEmpty ? null : ClipModel.fromMap(rows.first);
  }

  /// The stored clips among [ids]; unknown ids are skipped.
  Future<List<ClipModel>> clipsByIds(Iterable<String> ids) async {
    final db = await _db;
    final found = <ClipModel>[];
    for (final chunk in _chunks(ids)) {
      final rows = await db.query(
        clipsTable,
        where: 'id IN (${_marks(chunk.length)})',
        whereArgs: chunk,
      );
      found.addAll(rows.map(ClipModel.fromMap));
    }
    return found;
  }

  /// Clips holding changes the server has not seen, temp ones included.
  Future<List<ClipModel>> dirtyClips() async {
    final db = await _db;
    final rows = await db.query(clipsTable, where: 'dirty = 1');
    return rows.map(ClipModel.fromMap).toList();
  }

  /// Updates the row with [model]'s id in place, or inserts it when there is
  /// none. With [keepRemoteId] an update leaves the stored `remote_id` as it
  /// is, so a push that landed meanwhile is not forgotten.
  Future<void> upsertClip(ClipModel model, {bool keepRemoteId = false}) =>
      _upsert(clipsTable, model.toMap(), keepRemoteId: keepRemoteId);

  /// Writes the copy time and count of the clip [id] and nothing else.
  Future<void> updateCopy(
    String id, {
    required DateTime? copiedAt,
    required int copyCount,
  }) async {
    final db = await _db;
    await db.update(
      clipsTable,
      {'copied_at': copiedAt?.millisecondsSinceEpoch, 'copy_count': copyCount},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Forgets the server object of the clip [id].
  Future<void> clearClipRemoteId(String id) async {
    final db = await _db;
    await db.update(
      clipsTable,
      {'remote_id': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteClips(Iterable<String> ids) async {
    final db = await _db;
    for (final chunk in _chunks(ids)) {
      await db.delete(
        clipsTable,
        where: 'id IN (${_marks(chunk.length)})',
        whereArgs: chunk,
      );
    }
  }

  // --------------------------------------------------------------- groups

  /// Every group, in list order.
  Future<List<ClipGroupModel>> groups() async {
    final db = await _db;
    final rows = await db.query(
      groupsTable,
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(ClipGroupModel.fromMap).toList();
  }

  Future<ClipGroupModel?> groupById(String id) async {
    final db = await _db;
    final rows = await db.query(
      groupsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ClipGroupModel.fromMap(rows.first);
  }

  Future<List<ClipGroupModel>> dirtyGroups() async {
    final db = await _db;
    final rows = await db.query(groupsTable, where: 'dirty = 1');
    return rows.map(ClipGroupModel.fromMap).toList();
  }

  /// Updates the row with [model]'s id in place, or inserts it when there is
  /// none; see [upsertClip] for [keepRemoteId].
  ///
  /// Never a REPLACE: that deletes the row first, and the
  /// `ON DELETE SET NULL` key on `clips.group_id` would drop every clip out
  /// of the group.
  Future<void> upsertGroup(ClipGroupModel model, {bool keepRemoteId = false}) =>
      _upsert(groupsTable, model.toMap(), keepRemoteId: keepRemoteId);

  /// Deletes the group [id]. Clips still in it lose the link through the
  /// foreign key.
  Future<void> deleteGroup(String id) async {
    final db = await _db;
    await db.delete(groupsTable, where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------ sync, both tables

  /// Ids of rows in [table] that exist on the server and hold no unpushed
  /// change.
  Future<Set<String>> syncedIds(String table) async {
    final db = await _db;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'remote_id IS NOT NULL AND dirty = 0',
    );
    return {for (final row in rows) row['id'] as String};
  }

  /// Stores the server id of the row [id] in [table] and clears its dirty
  /// flag, leaving every other column as it is.
  Future<void> markSynced(String table, String id, String remoteId) async {
    final db = await _db;
    await db.update(
      table,
      {'remote_id': remoteId, 'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------- pending deletes

  /// Queues the server object [remoteId] of [className] for a DELETE. A
  /// second queueing of the same object moves it to [queuedAt].
  Future<void> queueDelete(
    String remoteId,
    String className,
    DateTime queuedAt,
  ) async {
    final db = await _db;
    await db.insert(_pendingTable, {
      'remote_id': remoteId,
      'class_name': className,
      'queued_at': queuedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> cancelDelete(String remoteId) async {
    final db = await _db;
    await db.delete(
      _pendingTable,
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Server ids of [className] waiting for a DELETE, oldest first.
  Future<List<String>> pendingDeletes(String className) async {
    final db = await _db;
    final rows = await db.query(
      _pendingTable,
      columns: ['remote_id'],
      where: 'class_name = ?',
      whereArgs: [className],
      orderBy: 'queued_at ASC',
    );
    return [for (final row in rows) row['remote_id'] as String];
  }

  // -------------------------------------------------------------- helpers

  Future<void> _upsert(
    String table,
    Map<String, Object?> row, {
    required bool keepRemoteId,
  }) async {
    final db = await _db;
    final values = {...row}..remove('id');
    if (keepRemoteId) values.remove('remote_id');
    await db.transaction((txn) async {
      final updated = await txn.update(
        table,
        values,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      if (updated == 0) await txn.insert(table, row);
    });
  }

  static Iterable<List<String>> _chunks(Iterable<String> ids) sync* {
    final all = ids.toList();
    for (var i = 0; i < all.length; i += _chunk) {
      yield all.sublist(i, i + _chunk > all.length ? all.length : i + _chunk);
    }
  }

  static String _marks(int count) => List.filled(count, '?').join(', ');
}
