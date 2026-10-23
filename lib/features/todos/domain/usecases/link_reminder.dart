import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

/// What [LinkReminder] takes: the todo and the id of its reminder, or null to
/// clear the link.
typedef LinkReminderParams = ({Todo todo, String? reminderId});

/// Records which reminder an item was turned into, or clears the link with a
/// null id once that reminder is gone. Linking the id already there writes
/// nothing; any other change is stamped as edited now.
class LinkReminder implements UseCase<void, LinkReminderParams> {
  LinkReminder(this._repo, this._clock);

  final TodoRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(LinkReminderParams params) async {
    final todo = params.todo;
    if (todo.reminderId == params.reminderId) return const Ok(null);
    return _repo.save(
      todo.copyWith(reminderId: params.reminderId, updatedAt: _clock.now()),
    );
  }
}
