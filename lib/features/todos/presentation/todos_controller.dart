import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/failure.dart';
import '../../../core/domain/result.dart';
import '../../../core/domain/usecase.dart';
import '../domain/entities/linked_reminder.dart';
import '../domain/entities/reminder_draft.dart';
import '../domain/entities/todo.dart';
import '../domain/usecases/add_todo.dart';
import '../domain/usecases/clear_done_todos.dart';
import '../domain/usecases/draft_reminder_from_todo.dart';
import '../domain/usecases/find_linked_reminder.dart';
import '../domain/usecases/get_todos.dart';
import '../domain/usecases/link_reminder.dart';
import '../domain/usecases/new_todo_id.dart';
import '../domain/usecases/remove_linked_reminder.dart';
import '../domain/usecases/remove_todo.dart';
import '../domain/usecases/save_todo.dart';
import '../domain/usecases/set_linked_reminder_enabled.dart';
import '../domain/usecases/set_todo_done.dart';
import '../domain/usecases/watch_linked_reminders.dart';
import '../domain/usecases/watch_todos.dart';

/// What the todo tab shows: the checklist in display order and, for items
/// turned into a reminder or deadline, that alarm as last looked up.
///
/// Only talks to use cases. Listens to [WatchTodos] and reloads the list on
/// every event, so a change a sync applied shows up without anyone asking;
/// listens to [WatchLinkedReminders] and looks the linked alarms up again, so
/// their countdowns keep moving. The [Clock] only says what "now" is for the
/// labels and the editor.
class TodosController extends ChangeNotifier {
  TodosController({
    required this._getTodos,
    required this._watchTodos,
    required this._addTodo,
    required this._saveTodo,
    required this._setTodoDone,
    required this._linkReminder,
    required this._removeTodo,
    required this._clearDoneTodos,
    required this._newTodoId,
    required this._draftReminderFromTodo,
    required this._findLinkedReminder,
    required this._setLinkedReminderEnabled,
    required this._removeLinkedReminder,
    required this._watchLinkedReminders,
    required this._clock,
  });

  final GetTodos _getTodos;
  final WatchTodos _watchTodos;
  final AddTodo _addTodo;
  final SaveTodo _saveTodo;
  final SetTodoDone _setTodoDone;
  final LinkReminder _linkReminder;
  final RemoveTodo _removeTodo;
  final ClearDoneTodos _clearDoneTodos;
  final NewTodoId _newTodoId;
  final DraftReminderFromTodo _draftReminderFromTodo;
  final FindLinkedReminder _findLinkedReminder;
  final SetLinkedReminderEnabled _setLinkedReminderEnabled;
  final RemoveLinkedReminder _removeLinkedReminder;
  final WatchLinkedReminders _watchLinkedReminders;
  final Clock _clock;

  List<Todo> _todos = const [];

  /// Linked alarms that still exist, by reminder id.
  Map<String, LinkedReminder> _linked = const {};
  Failure? _failure;

  final List<StreamSubscription<void>> _watches = [];
  bool _started = false;
  bool _disposed = false;

  /// Bumped by every load of the list, and of the linked alarms, so a slow
  /// one that finishes after a newer one does not overwrite it.
  int _loads = 0;
  int _linkLoads = 0;

  /// The newest load of each kind, so an action can wait until the state it
  /// leaves behind is on screen.
  Future<void> _latestLoad = Future.value();
  Future<void> _latestLinkLoad = Future.value();

  /// Every todo: unfinished first, most urgent on top, then finished ones.
  List<Todo> get todos => _todos;

  /// Items still to do, most urgent first.
  List<Todo> get open => _todos.where((t) => !t.done).toList();

  /// Items already ticked off, most recently finished first.
  List<Todo> get done => _todos.where((t) => t.done).toList();

  int get remaining => open.length;

  /// Why the last call failed, or null when it went through.
  Failure? get failure => _failure;

  /// The current time, for the deadline and countdown labels.
  DateTime now() => _clock.now();

  Todo? todoById(String id) => _todos.where((t) => t.id == id).firstOrNull;

  /// The alarm [todo] was turned into, as of the last lookup. Null when it
  /// never was, or when that alarm has since been deleted.
  LinkedReminder? linkedOf(Todo todo) {
    final id = todo.reminderId;
    return id == null ? null : _linked[id];
  }

  /// Starts listening for changes and loads the list. Safe to call twice.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    final todos = await _watchTodos(const NoParams());
    final reminders = await _watchLinkedReminders(const NoParams());
    if (_disposed) return;
    if (todos case Ok(:final value)) {
      _watches.add(value.listen((_) => _reload()));
    }
    if (reminders case Ok(:final value)) {
      _watches.add(value.listen((_) => _reloadLinks()));
    }
    _failure = todos.failureOrNull ?? reminders.failureOrNull;
    await _reload();
  }

  /// A fresh id for the editor to give a new item. Null if none could be
  /// made.
  Future<String?> newId() async {
    final result = await _newTodoId(const NoParams());
    if (_failed(result)) return null;
    return result.valueOrNull;
  }

  /// Adds a bare item typed into the quick-add box. Blank titles are ignored.
  Future<void> add(String title) => _run(_addTodo(title));

  /// Adds [todo], or replaces the one with the same id.
  Future<void> save(Todo todo) => _run(_saveTodo(todo));

  /// Ticks [todo] off or un-ticks it. Ticking silences its linked alarm;
  /// un-ticking turns it back on.
  Future<void> setDone(Todo todo, bool done) async {
    final current = _current(todo);
    if (current == null) return;
    if (_failed(await _setTodoDone((todo: current, done: done)))) return;
    final reminderId = current.reminderId;
    if (reminderId != null) {
      _failed(
        await _setLinkedReminderEnabled((
          reminderId: reminderId,
          enabled: !done,
        )),
      );
    }
    await _reload();
    await _settle();
  }

  /// Records which reminder [todo] was turned into, or clears the link with
  /// a null [reminderId]. Nothing happens if the item is gone by now.
  Future<void> linkReminder(Todo todo, String? reminderId) async {
    final current = _current(todo);
    if (current == null) return;
    await _run(_linkReminder((todo: current, reminderId: reminderId)));
  }

  Future<void> remove(String id) => _run(_removeTodo(id));

  /// Clears everything already ticked off; returns how many were removed.
  Future<int> clearDone() async {
    final result = await _clearDoneTodos(const NoParams());
    if (_failed(result)) return 0;
    await _reload();
    await _settle();
    return result.valueOrNull ?? 0;
  }

  /// The prefilled form for turning [todo] into a reminder, or a deadline
  /// when [deadline] is set. Null if it could not be made.
  Future<ReminderDraft?> draftReminder(
    Todo todo, {
    required bool deadline,
  }) async {
    final result = await _draftReminderFromTodo((
      todo: todo,
      deadline: deadline,
    ));
    if (_failed(result)) return null;
    return result.valueOrNull;
  }

  /// Looks up the alarm [todo] was turned into right now. `Ok(null)` means
  /// there is none: never converted, or the alarm was deleted since.
  Future<Result<LinkedReminder?>> findLinked(Todo todo) async {
    final result = await _findLinkedReminder(todo);
    _failed(result);
    return result;
  }

  /// Deletes the alarm [todo] was turned into, then forgets the link. The
  /// item stays on the checklist.
  Future<void> removeReminder(Todo todo, String reminderId) async {
    if (_failed(await _removeLinkedReminder(reminderId))) return;
    await linkReminder(todo, null);
  }

  /// The stored version of [todo]: a sync may have replaced it while the
  /// caller was waiting. Null once it has been deleted.
  Todo? _current(Todo todo) => todoById(todo.id);

  /// Waits for [action], then reloads so the list is current when the caller
  /// resumes.
  Future<void> _run(Future<Result<Object?>> action) async {
    if (_failed(await action)) return;
    await _reload();
    await _settle();
  }

  /// Waits until the newest loads are done, including ones a watch event
  /// started meanwhile: those supersede the load the action itself started.
  Future<void> _settle() async {
    while (true) {
      final load = _latestLoad, linkLoad = _latestLinkLoad;
      await Future.wait([load, linkLoad]);
      if (identical(load, _latestLoad) &&
          identical(linkLoad, _latestLinkLoad)) {
        return;
      }
    }
  }

  /// Records the failure of [result], if any, and tells the listeners.
  bool _failed(Result<Object?> result) {
    if (result case Err(:final failure)) {
      _failure = failure;
      _notify();
      return true;
    }
    return false;
  }

  Future<void> _reload() => _latestLoad = _loadTodos(++_loads);

  Future<void> _loadTodos(int load) async {
    final result = await _getTodos(const NoParams());
    if (_disposed || load != _loads) return;
    switch (result) {
      case Ok(:final value):
        _todos = List.unmodifiable(value);
        _failure = null;
      case Err(:final failure):
        _failure = failure;
    }
    _notify();
    await _reloadLinks();
  }

  Future<void> _reloadLinks() => _latestLinkLoad = _loadLinks(++_linkLoads);

  Future<void> _loadLinks(int load) async {
    final linkedTodos = [
      for (final todo in _todos)
        if (todo.reminderId != null) todo,
    ];
    final results = await Future.wait(
      linkedTodos.map(_findLinkedReminder.call),
    );
    if (_disposed || load != _linkLoads) return;

    final found = <String, LinkedReminder>{};
    Failure? failure;
    for (var i = 0; i < results.length; i++) {
      switch (results[i]) {
        case Ok(value: final reminder?):
          found[linkedTodos[i].reminderId!] = reminder;
        case Ok():
          break;
        case Err(failure: final f):
          failure ??= f;
      }
    }
    // Nothing linked before or now: no label to move, so no rebuild either.
    if (found.isEmpty && _linked.isEmpty && failure == null) return;
    _linked = Map.unmodifiable(found);
    if (failure != null) _failure = failure;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final watch in _watches) {
      watch.cancel();
    }
    super.dispose();
  }
}
