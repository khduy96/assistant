import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';

/// What [SetReminderEnabled] takes: the reminder's id and its new state.
typedef SetReminderEnabledParams = ({String id, bool enabled});

/// Switches a reminder on or off and yields what was stored; null for an
/// unknown id, which is not an error.
///
/// Drops any snooze, and counts everything before now as handled, so
/// switching back on never rings for a moment that has already passed.
class SetReminderEnabled
    implements UseCase<Reminder?, SetReminderEnabledParams> {
  SetReminderEnabled(this._repo, this._clock);

  final ReminderRepository _repo;
  final Clock _clock;

  @override
  Future<Result<Reminder?>> call(SetReminderEnabledParams params) async {
    final Reminder? current;
    switch (await _repo.find(params.id)) {
      case Ok(:final value):
        current = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (current == null) return const Ok(null);
    final saved = current.copyWith(
      enabled: params.enabled,
      snoozedUntil: null,
      firedUpTo: _clock.now(),
    );
    return switch (await _repo.save(saved)) {
      Ok() => Ok(saved),
      Err(:final failure) => Err(failure),
    };
  }
}
