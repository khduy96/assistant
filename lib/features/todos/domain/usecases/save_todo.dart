import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

/// Adds a todo or replaces the one with the same id, stamping it as edited
/// now.
class SaveTodo implements UseCase<void, Todo> {
  SaveTodo(this._repo, this._clock);

  final TodoRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(Todo todo) =>
      _repo.save(todo.copyWith(updatedAt: _clock.now()));
}
