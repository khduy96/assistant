import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/todo.dart';
import '../repositories/todo_repository.dart';
import '../services/todo_ordering.dart';

/// The unfinished todos that were turned into the reminder with the given id,
/// in display order: see [TodoOrdering]. Empty when none points at it.
class FindOpenTodosLinkedTo implements UseCase<List<Todo>, String> {
  FindOpenTodosLinkedTo(this._repo);

  final TodoRepository _repo;

  @override
  Future<Result<List<Todo>>> call(String reminderId) async =>
      switch (await _repo.getAll()) {
        Ok(:final value) => Ok(
          TodoOrdering.sorted(
            value.where((t) => !t.done && t.reminderId == reminderId),
          ),
        ),
        Err(:final failure) => Err(failure),
      };
}
