import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/linked_todos.dart';

/// Marks done every todo item that points at the reminder with the given id.
/// Items already done stay as they are; having none is not an error.
class CompleteLinkedTodos implements UseCase<void, String> {
  CompleteLinkedTodos(this._todos);

  final LinkedTodos _todos;

  @override
  Future<Result<void>> call(String reminderId) =>
      _todos.completeFor(reminderId);
}
