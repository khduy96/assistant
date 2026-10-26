import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/todos/domain/entities/linked_reminder.dart';
import 'package:event_notice/features/todos/domain/entities/reminder_draft.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/domain/repositories/linked_reminder_repository.dart';
import 'package:event_notice/features/todos/domain/repositories/todo_repository.dart';
import 'package:event_notice/features/todos/domain/usecases/add_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/clear_done_todos.dart';
import 'package:event_notice/features/todos/domain/usecases/draft_reminder_from_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/find_linked_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/get_todos.dart';
import 'package:event_notice/features/todos/domain/usecases/link_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/new_todo_id.dart';
import 'package:event_notice/features/todos/domain/usecases/remove_linked_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/remove_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/save_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/set_linked_reminder_enabled.dart';
import 'package:event_notice/features/todos/domain/usecases/set_todo_done.dart';
import 'package:event_notice/features/todos/domain/usecases/watch_linked_reminders.dart';
import 'package:event_notice/features/todos/domain/usecases/watch_todos.dart';
import 'package:event_notice/features/todos/presentation/todo_reminder_editor.dart';
import 'package:event_notice/features/todos/presentation/todos_controller.dart';
import 'package:flutter/widgets.dart';

import '../domain/fakes.dart';

/// Thursday 22/10/2026 09:30.
final t0 = DateTime(2026, 10, 22, 9, 30);

/// [t0] plus [m] minutes.
DateTime at(int m) => t0.add(Duration(minutes: m));

Todo todo(
  String id, {
  String title = 'Việc',
  String note = '',
  bool done = false,
  TodoPriority priority = TodoPriority.normal,
  DateTime? due,
  DateTime? completedAt,
  String? reminderId,
  int createdMin = 0,
}) => Todo(
  id: id,
  title: title,
  note: note,
  done: done,
  priority: priority,
  dueDate: due,
  completedAt: completedAt,
  reminderId: reminderId,
  createdAt: at(createdMin),
  updatedAt: at(createdMin),
);

LinkedReminder linked(
  String id, {
  String title = 'Nhắc',
  bool isDeadline = false,
  bool enabled = true,
  DateTime? next,
}) => LinkedReminder(
  id: id,
  title: title,
  isDeadline: isDeadline,
  enabled: enabled,
  nextOccurrence: next,
);

/// A controller wired to [repo] and [links] through the real use cases, with
/// the time taken from [clock] and new ids from [ids].
TodosController controllerFor(
  TodoRepository repo,
  LinkedReminderRepository links, {
  required Clock clock,
  IdGenerator? ids,
}) {
  final idGen = ids ?? SequentialIdGenerator();
  return TodosController(
    getTodos: GetTodos(repo),
    watchTodos: WatchTodos(repo),
    addTodo: AddTodo(repo, idGen, clock),
    saveTodo: SaveTodo(repo, clock),
    setTodoDone: SetTodoDone(repo, clock),
    linkReminder: LinkReminder(repo, clock),
    removeTodo: RemoveTodo(repo),
    clearDoneTodos: ClearDoneTodos(repo),
    newTodoId: NewTodoId(idGen),
    draftReminderFromTodo: DraftReminderFromTodo(clock),
    findLinkedReminder: FindLinkedReminder(links),
    setLinkedReminderEnabled: SetLinkedReminderEnabled(links),
    removeLinkedReminder: RemoveLinkedReminder(links),
    watchLinkedReminders: WatchLinkedReminders(links),
    clock: clock,
  );
}

/// Stands in for the reminder editor: records what it was asked to open and
/// answers like a user who saves the form, or cancels it when [cancel] is set.
class FakeTodoReminderEditor implements TodoReminderEditor {
  final List<ReminderDraft> drafts = [];
  final List<String> opened = [];
  bool cancel = false;

  @override
  Future<LinkedReminder?> createFromDraft(
    BuildContext context,
    ReminderDraft draft,
  ) async {
    drafts.add(draft);
    if (cancel) return null;
    return LinkedReminder(
      id: 'r-new-${drafts.length}',
      title: draft.title,
      isDeadline: draft.isDeadline,
      enabled: true,
      nextOccurrence: draft.at,
    );
  }

  @override
  Future<void> open(BuildContext context, String reminderId) async =>
      opened.add(reminderId);
}

/// [InMemoryTodoRepository] the way a file-backed one behaves: reads take a
/// turn of the event loop, and change events arrive on a later turn, after
/// the write has returned.
class SlowTodoRepository implements TodoRepository {
  SlowTodoRepository(this.inner) {
    _forward = inner.changes.listen((_) => Timer.run(() => _changes.add(null)));
  }

  final InMemoryTodoRepository inner;
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<void> _forward;

  @override
  Future<Result<List<Todo>>> getAll() async {
    await Future<void>.delayed(Duration.zero);
    return inner.getAll();
  }

  @override
  Future<Result<void>> save(Todo todo) => inner.save(todo);

  @override
  Future<Result<void>> delete(String id) => inner.delete(id);

  @override
  Future<Result<void>> deleteAll(Iterable<String> ids) => inner.deleteAll(ids);

  @override
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() async {
    await _forward.cancel();
    await _changes.close();
  }
}
