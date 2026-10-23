import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/todos/domain/entities/linked_reminder.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/domain/repositories/linked_reminder_repository.dart';
import 'package:event_notice/features/todos/domain/repositories/todo_repository.dart';

/// A clock that stays at [current] until a test moves it.
class FakeClock implements Clock {
  FakeClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

/// Hands out `id-1`, `id-2`, ... in order.
class SequentialIdGenerator implements IdGenerator {
  int _next = 1;

  @override
  String newId() => 'id-${_next++}';
}

/// Keeps todos in a map. Set [failure] to make every call return it.
class InMemoryTodoRepository implements TodoRepository {
  InMemoryTodoRepository([Iterable<Todo> initial = const []]) {
    for (final todo in initial) {
      _todos[todo.id] = todo;
    }
  }

  final Map<String, Todo> _todos = {};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// How many calls changed the store (save, delete, deleteAll), so a test
  /// can tell that nothing was written.
  int writes = 0;

  /// Ids passed to [delete] or [deleteAll], in call order.
  final List<String> deleted = [];

  Failure? failure;

  Todo? operator [](String id) => _todos[id];

  int get length => _todos.length;

  @override
  Future<Result<List<Todo>>> getAll() async {
    if (failure case final f?) return Err(f);
    return Ok(_todos.values.toList());
  }

  @override
  Future<Result<void>> save(Todo todo) async {
    if (failure case final f?) return Err(f);
    writes++;
    _todos[todo.id] = todo;
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String id) => deleteAll([id]);

  @override
  Future<Result<void>> deleteAll(Iterable<String> ids) async {
    if (failure case final f?) return Err(f);
    writes++;
    var changed = false;
    for (final id in ids) {
      deleted.add(id);
      if (_todos.remove(id) != null) changed = true;
    }
    if (changed) _changes.add(null);
    return const Ok(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();
}

/// Keeps linked reminders in a map and records every call that would change
/// one. Set [failure] to make every call return it.
class FakeLinkedReminderRepository implements LinkedReminderRepository {
  FakeLinkedReminderRepository([Iterable<LinkedReminder> initial = const []]) {
    for (final reminder in initial) {
      _reminders[reminder.id] = reminder;
    }
  }

  final Map<String, LinkedReminder> _reminders = {};
  final changesController = StreamController<void>.broadcast(sync: true);

  /// `(id, enabled)` of each [setEnabled] call, in order.
  final List<(String, bool)> enabledCalls = [];

  /// Ids passed to [remove], in order.
  final List<String> removed = [];

  Failure? failure;

  LinkedReminder? operator [](String id) => _reminders[id];

  @override
  Future<Result<LinkedReminder?>> find(String id) async {
    if (failure case final f?) return Err(f);
    return Ok(_reminders[id]);
  }

  @override
  Future<Result<void>> setEnabled(String id, bool enabled) async {
    if (failure case final f?) return Err(f);
    enabledCalls.add((id, enabled));
    final current = _reminders[id];
    if (current != null) {
      _reminders[id] = LinkedReminder(
        id: current.id,
        title: current.title,
        isDeadline: current.isDeadline,
        enabled: enabled,
        nextOccurrence: current.nextOccurrence,
      );
    }
    return const Ok(null);
  }

  @override
  Future<Result<void>> remove(String id) async {
    if (failure case final f?) return Err(f);
    removed.add(id);
    _reminders.remove(id);
    return const Ok(null);
  }

  @override
  Stream<void> get changes => changesController.stream;

  Future<void> dispose() => changesController.close();
}
