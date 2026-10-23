import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/alarm_payload.dart';
import '../entities/reminder.dart';
import '../entities/scheduled_alarm.dart';
import '../ports/alarm_body_formatter.dart';
import '../services/schedule_calculator.dart';

/// Turns reminders into the list of OS alarms to hand over: the next
/// [perReminderLimit] alerts of each switched-on reminder from now, soonest
/// first, at most [scheduleLimit] in all, numbered from 1.
class BuildAlarmSchedule
    implements UseCase<List<ScheduledAlarm>, List<Reminder>> {
  BuildAlarmSchedule(this._formatter, this._clock);

  final AlarmBodyFormatter _formatter;
  final Clock _clock;

  /// Alarms handed to the OS at a time. Android caps pending alarms per app,
  /// and the list is refreshed on every save and on resume.
  static const scheduleLimit = 48;
  static const perReminderLimit = 8;

  @override
  Future<Result<List<ScheduledAlarm>>> call(List<Reminder> reminders) async {
    final now = _clock.now();
    final pending = <({Reminder reminder, AlertTime alert})>[
      for (final r in reminders.where((r) => r.enabled))
        for (final alert in ScheduleCalculator.upcomingAlerts(
          r,
          perReminderLimit,
          from: now,
        ))
          (reminder: r, alert: alert),
    ];
    pending.sort((a, b) => a.alert.at.compareTo(b.alert.at));

    var id = 1;
    return Ok([
      for (final item in pending.take(scheduleLimit))
        ScheduledAlarm(
          id: id++,
          at: item.alert.at,
          title: item.reminder.title,
          body: _formatter.body(
            item.reminder,
            item.alert.eventAt,
            isLead: item.alert.isLead,
          ),
          payload: AlarmPayload(
            reminderId: item.reminder.id,
            at: item.alert.at,
            isLead: item.alert.isLead,
          ).encode(),
        ),
    ]);
  }
}
