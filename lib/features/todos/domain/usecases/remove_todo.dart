import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/todo_repository.dart';

/// Removes the todo with the given id.
class RemoveTodo implements UseCase<void, String> {
  RemoveTodo(this._repo);

  final TodoRepository _repo;

  @override
  Future<Result<void>> call(String id) => _repo.delete(id);
}
