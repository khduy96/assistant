import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

/// What [SetTodoDone] takes: the todo and whether it is now done.
typedef SetTodoDoneParams = ({Todo todo, bool done});

/// Ticks an item off, recording when, or un-ticks it and forgets that time.
/// Counts as an edit, so the item is stamped as edited now.
class SetTodoDone implements UseCase<void, SetTodoDoneParams> {
  SetTodoDone(this._repo, this._clock);

  final TodoRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(SetTodoDoneParams params) {
    final now = _clock.now();
    return _repo.save(
      params.todo.copyWith(
        done: params.done,
        completedAt: params.done ? now : null,
        updatedAt: now,
      ),
    );
  }
}
