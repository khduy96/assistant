import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/pending_alert.dart';
import '../repositories/reminder_repository.dart';

/// Puts off an alert: its reminder rings again after its own snooze interval.
/// A reminder deleted in the meantime is skipped.
class SnoozeAlert implements UseCase<void, PendingAlert> {
  SnoozeAlert(this._repo, this._clock);

  final ReminderRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(PendingAlert alert) async {
    switch (await _repo.find(alert.reminder.id)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: null):
        return const Ok(null);
      case Ok(value: final r?):
        final now = _clock.now();
        return _repo.save(
          r.copyWith(
            snoozedUntil: now.add(Duration(minutes: r.snoozeMinutes)),
            firedUpTo: now,
          ),
        );
    }
  }
}
