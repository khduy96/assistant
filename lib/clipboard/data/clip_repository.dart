import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/clip_group.dart';
import '../models/clip_item.dart';
import '../sync/class_names.dart';
import 'app_database.dart';

class ClipRepository {
  ClipRepository({AppDatabase? db}) : _appDb = db ?? AppDatabase.instance;

  final AppDatabase _appDb;
  final Random _random = Random();

  Future<Database> get _db => _appDb.database;

  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$stamp-$salt';
  }

  // ---------------------------------------------------------------- clips

  Future<List<ClipItem>> loadClips() async {
    final db = await _db;
    final rows = await db.query('clips', orderBy: 'created_at DESC');
    return rows.map(ClipItem.fromMap).toList();
  }

  /// Inserts a captured clipboard value as a temp clip.
  ///
  /// If the exact content already exists the existing row is bumped to the top
  /// instead, so repeated copies never flood the list.
  Future<ClipItem?> capture(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    final db = await _db;
    final now = DateTime.now();
    final existing = await db.query(
      'clips',
      where: 'content = ?',
      whereArgs: [trimmed],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final item = ClipItem.fromMap(existing.first);
      final bumped = item.copyWith(
        createdAt: item.isTemp ? now : item.createdAt,
        updatedAt: now,
        copiedAt: now,
        dirty: true,
      );
      await _update(bumped);
      return bumped;
    }

    final item = ClipItem(
      id: _newId(),
      content: trimmed,
      type: ClipItem.detectType(trimmed),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('clips', item.toMap());
    return item;
  }

  /// Adds a clip typed by the user; goes straight to the saved list.
  Future<ClipItem> createManual(String content, {String? groupId}) async {
    final db = await _db;
    final now = DateTime.now();
    final item = ClipItem(
      id: _newId(),
      content: content.trim(),
      type: ClipItem.detectType(content),
      createdAt: now,
      updatedAt: now,
      isSaved: true,
      groupId: groupId,
    );
    await db.insert('clips', item.toMap());
    return item;
  }

    Future<ClipItem> save(ClipItem item, {String? groupId}) =>
      _persist(item.copyWith(
        isSaved: true,
        groupId: groupId ?? item.groupId,
        updatedAt: DateTime.now(),
        dirty: true,
      ));

  /// Moving a clip back to temp restarts its 1-day countdown.
  Future<ClipItem> unsave(ClipItem item) => _persist(item.copyWith(
        isSaved: false,
        isPinned: false,
        clearGroup: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dirty: true,
      ));

  /// Pinning a temp clip saves it automatically, as required by the spec.
  Future<ClipItem> setPinned(ClipItem item, bool pinned) => _persist(
        item.copyWith(
          isPinned: pinned,
          isSaved: pinned ? true : item.isSaved,
          updatedAt: DateTime.now(),
          dirty: true,
        ),
      );

  Future<ClipItem> assignGroup(ClipItem item, String? groupId) => _persist(
        item.copyWith(
          groupId: groupId,
          clearGroup: groupId == null,
          isSaved: groupId != null ? true : item.isSaved,
          updatedAt: DateTime.now(),
          dirty: true,
        ),
      );

  Future<ClipItem> updateContent(ClipItem item, String content,
          {String? note}) =>
      _persist(item.copyWith(
        content: content.trim(),
        type: ClipItem.detectType(content),
        note: note,
        updatedAt: DateTime.now(),
        dirty: true,
      ));

  Future<ClipItem> markCopied(ClipItem item) => _persist(item.copyWith(
        copiedAt: DateTime.now(),
        copyCount: item.copyCount + 1,
      ));

  /// Deletes a clip for good: the row goes, and if the clip ever reached
  /// Back4App its object is queued for a DELETE on the next sync.
  Future<void> delete(ClipItem item) async {
    final db = await _db;
    await db.delete('clips', where: 'id = ?', whereArgs: [item.id]);
    await queueRemoteDelete(item.remoteId, SyncClassNames.clip);
  }

  /// Undo for [delete]. The old object is gone from the server, so the clip
  /// comes back without a remote id and is pushed again as a new one.
  Future<ClipItem> restore(ClipItem item) async {
    final db = await _db;
    final revived = ClipItem(
      id: item.id,
      content: item.content,
      type: item.type,
      createdAt: item.createdAt,
      updatedAt: DateTime.now(),
      copiedAt: item.copiedAt,
      isSaved: item.isSaved,
      isPinned: item.isPinned,
      groupId: item.groupId,
      note: item.note,
      copyCount: item.copyCount,
    );
    await db.insert('clips', revived.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    // If the delete never went out, cancel it instead of racing it.
    await _cancelRemoteDelete(item.remoteId);
    return revived;
  }

  /// Removes every temp clip (pinned/saved ones are untouched).
  Future<int> clearTemp() =>
      _deleteWhere('is_saved = 0 AND is_pinned = 0', const []);

  /// Drops temp clips older than [ClipItem.tempTtl]. Runs at startup and hourly.
  Future<int> purgeExpired() {
    final cutoff = DateTime.now().subtract(ClipItem.tempTtl);
    return _deleteWhere(
      'is_saved = 0 AND is_pinned = 0 AND created_at < ?',
      [cutoff.millisecondsSinceEpoch],
    );
  }

  /// Hard-deletes matching clips, queueing a server delete for any that had
  /// already been pushed.
  Future<int> _deleteWhere(String where, List<Object?> args) async {
    final db = await _db;
    final doomed = await db.query(
      'clips',
      columns: ['remote_id'],
      where: '$where AND remote_id IS NOT NULL',
      whereArgs: args,
    );
    for (final row in doomed) {
      await queueRemoteDelete(row['remote_id'] as String?, SyncClassNames.clip);
    }
    return db.delete('clips', where: where, whereArgs: args);
  }

  Future<ClipItem> _persist(ClipItem item) async {
    await _update(item);
    return item;
  }

  Future<void> _update(ClipItem item) async {
    final db = await _db;
    await db.update('clips', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  // --------------------------------------------------------------- groups

  Future<List<ClipGroup>> loadGroups() async {
    final db = await _db;
    final rows =
        await db.query('groups', orderBy: 'sort_order ASC, name ASC');
    return rows.map(ClipGroup.fromMap).toList();
  }

  Future<ClipGroup> createGroup(String name, int color, int sortOrder) async {
    final db = await _db;
    final now = DateTime.now();
    final group = ClipGroup(
      id: _newId(),
      name: name.trim(),
      color: color,
      createdAt: now,
      updatedAt: now,
      sortOrder: sortOrder,
    );
    await db.insert('groups', group.toMap());
    return group;
  }

  Future<ClipGroup> updateGroup(ClipGroup group) async {
    final db = await _db;
    final updated = group.copyWith(updatedAt: DateTime.now(), dirty: true);
    await db.update('groups', updated.toMap(),
        where: 'id = ?', whereArgs: [group.id]);
    return updated;
  }

  /// Deletes the group; its clips stay in the saved list without a group.
  Future<void> deleteGroup(ClipGroup group) async {
    final db = await _db;
    final now = DateTime.now();
    await db.delete('groups', where: 'id = ?', whereArgs: [group.id]);
    await queueRemoteDelete(group.remoteId, SyncClassNames.group);
    await db.rawUpdate(
      'UPDATE clips SET group_id = NULL, updated_at = ?, dirty = 1 '
      'WHERE group_id = ?',
      [now.millisecondsSinceEpoch, group.id],
    );
  }

  // --------------------------------------------------------- remote deletes

  /// Remembers an object that must disappear from Back4App. Kept in a table so
  /// a delete made offline still reaches the server later.
  Future<void> queueRemoteDelete(String? remoteId, String className) async {
    if (remoteId == null) return;
    final db = await _db;
    await db.insert(
      'pending_deletes',
      {
        'remote_id': remoteId,
        'class_name': className,
        'queued_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _cancelRemoteDelete(String? remoteId) async {
    if (remoteId == null) return;
    final db = await _db;
    await db.delete('pending_deletes',
        where: 'remote_id = ?', whereArgs: [remoteId]);
  }

  /// Deletes still waiting to be sent, as `(remoteId, className)` pairs.
  Future<List<(String, String)>> pendingDeletes() async {
    final db = await _db;
    final rows = await db.query('pending_deletes', orderBy: 'queued_at ASC');
    return [
      for (final row in rows)
        (row['remote_id'] as String, row['class_name'] as String),
    ];
  }

  Future<void> clearPendingDelete(String remoteId) =>
      _cancelRemoteDelete(remoteId);

  /// Local ids of rows that are known to exist on the server and hold no
  /// unpushed change — the set a pull can safely reconcile against.
  Future<Set<String>> syncedLocalIds(String table) async {
    final db = await _db;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'remote_id IS NOT NULL AND dirty = 0',
    );
    return {for (final row in rows) row['id'] as String};
  }

  /// Drops a row because the server no longer has it. No delete is queued —
  /// the object is already gone.
  Future<void> deleteLocalOnly(String table, String id) async {
    final db = await _db;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // ----------------------------------------------------------------- sync

  Future<List<ClipItem>> dirtyClips() async {
    final db = await _db;
    final rows = await db.query('clips', where: 'dirty = 1');
    return rows.map(ClipItem.fromMap).toList();
  }

  Future<List<ClipGroup>> dirtyGroups() async {
    final db = await _db;
    final rows = await db.query('groups', where: 'dirty = 1');
    return rows.map(ClipGroup.fromMap).toList();
  }

  Future<ClipItem?> clipById(String id) async {
    final db = await _db;
    final rows = await db.query('clips', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ClipItem.fromMap(rows.first);
  }

  Future<ClipGroup?> groupById(String id) async {
    final db = await _db;
    final rows = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ClipGroup.fromMap(rows.first);
  }

  /// Writes a row exactly as given — used when applying a pulled record or
  /// when clearing the dirty flag after a successful push.
  Future<void> putClip(ClipItem item) async {
    final db = await _db;
    await db.insert('clips', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> putGroup(ClipGroup group) async {
    final db = await _db;
    await db.insert('groups', group.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------- settings

  Future<Map<String, String>> loadSettings() async {
    final db = await _db;
    final rows = await db.query('settings');
    return {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
  }

  Future<void> putSetting(String key, String value) async {
    final db = await _db;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
