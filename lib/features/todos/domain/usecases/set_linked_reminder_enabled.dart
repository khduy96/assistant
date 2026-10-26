import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/linked_reminder_repository.dart';

/// What [SetLinkedReminderEnabled] takes: the reminder id and whether it
/// should ring.
typedef SetLinkedReminderEnabledParams = ({String reminderId, bool enabled});

/// Switches a linked reminder on or off, e.g. off when its item is ticked and
/// back on when it is un-ticked. Does nothing when the reminder is gone or
/// already in that state, so switching never resets an alarm needlessly.
class SetLinkedReminderEnabled
    implements UseCase<void, SetLinkedReminderEnabledParams> {
  SetLinkedReminderEnabled(this._reminders);

  final LinkedReminderRepository _reminders;

  @override
  Future<Result<void>> call(SetLinkedReminderEnabledParams params) async {
    switch (await _reminders.find(params.reminderId)) {
      case Ok(:final value):
        if (value == null || value.enabled == params.enabled) {
          return const Ok(null);
        }
      case Err(:final failure):
        return Err(failure);
    }
    return _reminders.setEnabled(params.reminderId, params.enabled);
  }
}
