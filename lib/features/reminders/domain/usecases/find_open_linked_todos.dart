import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/linked_todos.dart';

/// Titles of the todo items not done yet that point at the reminder with the
/// given id, so the user can be told they will be marked done.
class FindOpenLinkedTodos implements UseCase<List<String>, String> {
  FindOpenLinkedTodos(this._todos);

  final LinkedTodos _todos;

  @override
  Future<Result<List<String>>> call(String reminderId) =>
      _todos.openTitlesFor(reminderId);
}
