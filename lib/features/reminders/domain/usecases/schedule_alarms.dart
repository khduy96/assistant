import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/reminder.dart';
import '../ports/alarm_scheduler.dart';
import '../repositories/reminder_repository.dart';
import '../services/reminder_ordering.dart';
import 'build_alarm_schedule.dart';

/// Refills the OS alarm schedule from the stored reminders, taken in display
/// order (see [BuildAlarmSchedule]), e.g. after every change and when the app
/// comes back to the front. Does nothing where the OS does not ring for the
/// app.
class ScheduleAlarms implements UseCase<void, NoParams> {
  ScheduleAlarms(this._repo, this._scheduler, this._build, this._clock);

  final ReminderRepository _repo;
  final AlarmScheduler _scheduler;
  final BuildAlarmSchedule _build;
  final Clock _clock;

  @override
  Future<Result<void>> call(NoParams params) async {
    if (!_scheduler.ringsNatively) return const Ok(null);
    final List<Reminder> reminders;
    switch (await _repo.getAll()) {
      case Ok(:final value):
        reminders = ReminderOrdering.sorted(value, _clock.now());
      case Err(:final failure):
        return Err(failure);
    }
    return switch (await _build(reminders)) {
      Ok(:final value) => _scheduler.scheduleAll(value),
      Err(:final failure) => Err(failure),
    };
  }
}
