import '../../../core/domain/result.dart';
import '../../../features/reminders/domain/ports/linked_todos.dart';
import '../../../features/todos/domain/usecases/complete_todos_linked_to.dart';
import '../../../features/todos/domain/usecases/find_open_todos_linked_to.dart';

/// The reminders' [LinkedTodos], backed by the todo list's use cases.
///
/// Goes through the use cases rather than a `TodosController`: that one is
/// made afresh for every screen, so it would not be the one on display. The
/// todo list on screen follows the repository's changes instead, and a todo
/// ticked off here is stamped and queued for the sync as a tick by hand.
class LinkedTodosBridge implements LinkedTodos {
  LinkedTodosBridge(this._findOpen, this._complete);

  final FindOpenTodosLinkedTo _findOpen;
  final CompleteTodosLinkedTo _complete;

  @override
  Future<Result<List<String>>> openTitlesFor(String reminderId) async =>
      switch (await _findOpen(reminderId)) {
        Ok(:final value) => Ok([for (final t in value) t.title]),
        Err(:final failure) => Err(failure),
      };

  @override
  Future<Result<void>> completeFor(String reminderId) => _complete(reminderId);
}
