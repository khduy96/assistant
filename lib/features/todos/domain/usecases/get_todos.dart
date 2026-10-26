import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/todo.dart';
import '../repositories/todo_repository.dart';
import '../services/todo_ordering.dart';

/// Every todo in display order: see [TodoOrdering].
class GetTodos implements UseCase<List<Todo>, NoParams> {
  GetTodos(this._repo);

  final TodoRepository _repo;

  @override
  Future<Result<List<Todo>>> call(NoParams params) async =>
      switch (await _repo.getAll()) {
        Ok(:final value) => Ok(TodoOrdering.sorted(value)),
        Err(:final failure) => Err(failure),
      };
}
