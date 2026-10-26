import 'dart:async';

import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../../domain/entities/todo.dart';
import '../../domain/repositories/todo_repository.dart';
import '../datasources/todo_local_data_source.dart';
import '../mappers/todo_mapper.dart';
import '../models/todo_model.dart';

/// Keeps the todos in memory and on disk, along with their sync state and the
/// tombstones of deleted items.
///
/// The user's edits come in through [TodoRepository]; the sync engine's come
/// in through `TodoSyncCollection`, which uses the members below the
/// "Sync side" mark. Both fire [changes]; only the user's fire
/// [localChanges], so applying a pull never schedules a push of its own.
class TodoRepositoryImpl implements TodoRepository {
  TodoRepositoryImpl(this._source);

  final TodoLocalDataSource _source;
  final List<TodoModel> _todos = [];

  /// Items deleted here whose Back4App object is still waiting to be removed.
  final List<SyncTombstone> _deleted = [];

  Future<void>? _loading;
  bool _loaded = false;

  final _changes = StreamController<void>.broadcast();
  final _localChanges = StreamController<void>.broadcast();

  /// Reads `todos.json`. Same as [ensureLoaded]; the app awaits this once at
  /// startup, before the sync engine first looks at the todos.
  Future<void> init() => ensureLoaded();

  /// Loads the file on the first call; later calls wait for that load. A
  /// load that throws is retried on the next call.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final saved = await _source.load();
      _todos
        ..clear()
        ..addAll(saved.items);
      _deleted
        ..clear()
        ..addAll(saved.deleted);
      _loaded = true;
    } catch (_) {
      _loading = null;
      rethrow;
    }
    _emit(local: false);
  }

  @override
  Stream<void> get changes => _changes.stream;

  /// Fires after a change made on this device through [save], [delete] or
  /// [deleteAll], so the sync engine can push it soon. Never fires for a
  /// change a sync applied.
  Stream<void> get localChanges => _localChanges.stream;

  @override
  Future<Result<List<Todo>>> getAll() => _guard('read', () async {
    await ensureLoaded();
    return [for (final m in _todos) TodoMapper.toEntity(m)];
  });

  @override
  Future<Result<void>> save(Todo todo) => _guard('save', () async {
    await ensureLoaded();
    final i = _indexOf(todo.id);
    final model = TodoMapper.toModel(todo, stored: i == -1 ? null : _todos[i]);
    if (i == -1) {
      _todos.add(model);
    } else {
      _todos[i] = model;
    }
    await _persist(local: true);
  });

  @override
  Future<Result<void>> delete(String id) => deleteAll([id]);

  @override
  Future<Result<void>> deleteAll(Iterable<String> ids) =>
      _guard('delete', () async {
        await ensureLoaded();
        final wanted = ids.toSet();
        final gone = _todos.where((t) => wanted.contains(t.id)).toList();
        if (gone.isEmpty) return;
        _todos.removeWhere((t) => wanted.contains(t.id));
        for (final todo in gone) {
          // Never pushed: there is nothing on the server to delete.
          final remoteId = todo.remoteId;
          if (remoteId == null) continue;
          _deleted.add(SyncTombstone(localId: todo.id, remoteId: remoteId));
        }
        await _persist(local: true);
      });

  Future<void> dispose() async {
    await _changes.close();
    await _localChanges.close();
  }

  // Sync side. Read these only after [ensureLoaded]. The writers change the
  // memory synchronously, before their first await, so a check made just
  // before calling one still holds when it lands.

  /// Every stored todo with its sync state, in storage order.
  List<TodoModel> get models => List.unmodifiable(_todos);

  /// Deleted todos still waiting for their server object to go.
  List<SyncTombstone> get tombstones => List.unmodifiable(_deleted);

  /// Adds [model], or replaces the stored todo with the same id, as it is.
  Future<void> putFromSync(TodoModel model) {
    _checkLoaded();
    final i = _indexOf(model.id);
    if (i == -1) {
      _todos.add(model);
    } else {
      _todos[i] = model;
    }
    return _persist(local: false);
  }

  /// Drops the todo with [id] without queueing a delete to the server.
  Future<void> removeFromSync(String id) {
    _checkLoaded();
    _todos.removeWhere((t) => t.id == id);
    return _persist(local: false);
  }

  /// Forgets the tombstone whose server object is [remoteId], once that
  /// object is gone.
  Future<void> clearTombstone(String remoteId) {
    _checkLoaded();
    _deleted.removeWhere((t) => t.remoteId == remoteId);
    return _persist(local: false);
  }

  int _indexOf(String id) => _todos.indexWhere((t) => t.id == id);

  void _checkLoaded() {
    if (!_loaded) {
      throw StateError('TodoRepositoryImpl used before ensureLoaded()');
    }
  }

  /// Writes the file, then tells the listeners. They hear about the change
  /// even when the write fails: the memory, which they read, has changed.
  Future<void> _persist({required bool local}) async {
    try {
      await _source.save(_todos, _deleted);
    } finally {
      _emit(local: local);
    }
  }

  void _emit({required bool local}) {
    if (!_changes.isClosed) _changes.add(null);
    if (local && !_localChanges.isClosed) _localChanges.add(null);
  }

  Future<Result<T>> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(StorageFailure('Could not $action todos', cause: e));
    }
  }
}
