import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../clipboard/sync/class_names.dart';
import '../models/todo.dart';
import 'sync/sync_collection.dart';
import 'todo_storage.dart';

/// Holds the todo list and keeps it on disk.
///
/// Unlike the reminder store there is no ticker here: a todo has no alarm, so
/// the list only changes when the user changes it.
class TodoStore extends ChangeNotifier {
  TodoStore({TodoStorage? storage}) : _storage = storage ?? TodoStorage();

  final TodoStorage _storage;
  final _uuid = const Uuid();
  final List<Todo> _todos = [];

  /// Items deleted here whose Back4App object is still waiting to be removed.
  final List<SyncTombstone> _deleted = [];

  List<Todo> get todos => List.unmodifiable(_todos);

  /// The todo list as the sync engine sees it.
  late final SyncCollection syncCollection = _TodoSyncCollection(this);

  /// Items still to do, most urgent first.
  List<Todo> get open => _todos.where((t) => !t.done).toList();

  /// Items already ticked off, most recently finished first.
  List<Todo> get done => _todos.where((t) => t.done).toList();

  int get remaining => open.length;

  Future<void> init() async {
    final saved = await _storage.load();
    _todos.addAll(saved.items);
    _deleted.addAll(saved.deleted);
    _sort();
    notifyListeners();
  }

  String newId() => _uuid.v4();

  /// Adds a bare item typed into the quick-add box. Blank titles are ignored.
  Future<void> add(String title) async {
    final text = title.trim();
    if (text.isEmpty) return;
    // A fresh item is born dirty, so the next sync pushes it.
    _todos.add(Todo(id: newId(), title: text));
    _sort();
    await _persist();
  }

  Future<void> upsert(Todo todo) async {
    todo.touch();
    final i = _todos.indexWhere((t) => t.id == todo.id);
    if (i == -1) {
      _todos.add(todo);
    } else {
      _todos[i] = todo;
    }
    _sort();
    await _persist();
  }

  Future<void> setDone(Todo todo, bool done) async {
    todo.done = done;
    todo.completedAt = done ? DateTime.now() : null;
    todo.touch();
    _sort();
    await _persist();
  }

  /// Records which reminder this item was turned into, or clears the link
  /// with a null [reminderId] once that reminder is gone.
  Future<void> linkReminder(Todo todo, String? reminderId) async {
    if (todo.reminderId == reminderId) return;
    todo.reminderId = reminderId;
    todo.touch();
    await _persist();
  }

  Future<void> remove(String id) async {
    _forget(_todos.where((t) => t.id == id));
    _todos.removeWhere((t) => t.id == id);
    await _persist();
  }

  /// Clears everything already ticked off; returns how many were removed.
  Future<int> clearDone() async {
    final count = _todos.where((t) => t.done).length;
    if (count == 0) return 0;
    _forget(_todos.where((t) => t.done));
    _todos.removeWhere((t) => t.done);
    await _persist();
    return count;
  }

  /// Queues the server objects of [gone] for deletion on the next sync.
  void _forget(Iterable<Todo> gone) {
    for (final todo in gone.toList()) {
      final remoteId = todo.remoteId;
      if (remoteId == null) continue; // never pushed: nothing to delete there
      _deleted.add(SyncTombstone(localId: todo.id, remoteId: remoteId));
    }
  }

  /// Unfinished first: overdue and high priority float to the top, then the
  /// nearest due date, then the oldest. Finished items sink to the bottom.
  void _sort() {
    _todos.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.done) {
        final ac = a.completedAt, bc = b.completedAt;
        if (ac != null && bc != null) return bc.compareTo(ac);
        return b.createdAt.compareTo(a.createdAt);
      }
      if (a.priority != b.priority) {
        return b.priority.index.compareTo(a.priority.index);
      }
      final ad = a.dueDate, bd = b.dueDate;
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  Future<void> _persist() async {
    await _storage.save(_todos, _deleted);
    notifyListeners();
  }
}

/// Mirrors the todo list to the `TodoItem` class on Back4App.
class _TodoSyncCollection implements SyncCollection {
  _TodoSyncCollection(this._store);

  final TodoStore _store;

  @override
  String get className => SyncClassNames.todo;

  @override
  List<SyncRecord> dirtyRecords() => [
        for (final todo in _store._todos)
          if (todo.dirty)
            SyncRecord(
              localId: todo.id,
              remoteId: todo.remoteId,
              fields: todo.toParse(),
            ),
      ];

  @override
  Set<String> syncedIds() => {
        for (final todo in _store._todos)
          if (todo.remoteId != null) todo.id,
      };

  @override
  List<({String localId, String remoteId})> pendingDeletes() => [
        for (final tombstone in _store._deleted)
          (localId: tombstone.localId, remoteId: tombstone.remoteId),
      ];

  @override
  Future<void> clearPendingDelete(String localId) async {
    _store._deleted.removeWhere((t) => t.localId == localId);
    await _store._persist();
  }

  @override
  Future<void> markSynced(String localId, String remoteId) async {
    final todo = _store._todos.where((t) => t.id == localId).firstOrNull;
    if (todo == null) return;
    todo.remoteId = remoteId;
    todo.dirty = false;
    await _store._persist();
  }

  @override
  Future<bool> applyRemote(Map<String, Object?> json) async {
    if (json['localId'] is! String) return false;
    final incoming = Todo.fromParse(json);
    final existing =
        _store._todos.where((t) => t.id == incoming.id).firstOrNull;

    // Local edits that have not been pushed yet, and newer local state, win.
    if (existing != null) {
      if (existing.dirty) return false;
      if (existing.updatedAt.isAfter(incoming.updatedAt)) return false;
      _store._todos.remove(existing);
    } else if (_store._deleted.any((t) => t.localId == incoming.id)) {
      // Deleted here, not yet on the server: the push will remove it.
      return false;
    }

    _store._todos.add(incoming);
    _store._sort();
    await _store._persist();
    return true;
  }

  @override
  Future<void> removeLocalOnly(String localId) async {
    _store._todos.removeWhere((t) => t.id == localId);
    await _store._persist();
  }
}
