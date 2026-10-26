import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/todo_repository.dart';

/// Clears everything already ticked off and yields how many items were
/// removed. Writes nothing when there is none.
class ClearDoneTodos implements UseCase<int, NoParams> {
  ClearDoneTodos(this._repo);

  final TodoRepository _repo;

  @override
  Future<Result<int>> call(NoParams params) async {
    final List<String> ids;
    switch (await _repo.getAll()) {
      case Ok(:final value):
        ids = [
          for (final todo in value)
            if (todo.done) todo.id,
        ];
      case Err(:final failure):
        return Err(failure);
    }
    if (ids.isEmpty) return const Ok(0);
    return switch (await _repo.deleteAll(ids)) {
      Ok() => Ok(ids.length),
      Err(:final failure) => Err(failure),
    };
  }
}
