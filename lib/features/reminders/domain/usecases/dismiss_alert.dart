import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/pending_alert.dart';
import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';

/// Turns an alert off and drops any snooze of its reminder. Turning off the
/// event of a one-off reminder marks it done (switched off); turning off the
/// alert before it leaves it on, so the event still rings. A reminder deleted
/// in the meantime is skipped.
class DismissAlert implements UseCase<void, PendingAlert> {
  DismissAlert(this._repo);

  final ReminderRepository _repo;

  @override
  Future<Result<void>> call(PendingAlert alert) async {
    switch (await _repo.find(alert.reminder.id)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: null):
        return const Ok(null);
      case Ok(value: final r?):
        final done = !alert.isLead && r.repeat == RepeatRule.once;
        return _repo.save(
          r.copyWith(snoozedUntil: null, enabled: done ? false : null),
        );
    }
  }
}
