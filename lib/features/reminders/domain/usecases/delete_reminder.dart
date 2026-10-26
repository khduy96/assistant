import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/pending_alert.dart';
import '../repositories/reminder_repository.dart';

/// What [DeleteReminder] takes: the id to delete, and the alerts waiting to
/// be shown.
typedef DeleteReminderParams = ({String id, List<PendingAlert> pending});

/// Deletes a reminder and yields the waiting alerts without its own, so a
/// deleted reminder never rings from the queue.
class DeleteReminder
    implements UseCase<List<PendingAlert>, DeleteReminderParams> {
  DeleteReminder(this._repo);

  final ReminderRepository _repo;

  @override
  Future<Result<List<PendingAlert>>> call(DeleteReminderParams params) async =>
      switch (await _repo.delete(params.id)) {
        Ok() => Ok([
          for (final a in params.pending)
            if (a.reminder.id != params.id) a,
        ]),
        Err(:final failure) => Err(failure),
      };
}
