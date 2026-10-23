import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/alert_from_payload.dart';
import 'package:event_notice/features/reminders/domain/usecases/build_alarm_schedule.dart';
import 'package:event_notice/features/reminders/domain/usecases/can_draw_overlays.dart';
import 'package:event_notice/features/reminders/domain/usecases/can_schedule_exact_alarms.dart';
import 'package:event_notice/features/reminders/domain/usecases/delete_reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/dismiss_alert.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_due_alerts.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_launch_payload.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_reminders.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_ringing_payload.dart';
import 'package:event_notice/features/reminders/domain/usecases/new_reminder_id.dart';
import 'package:event_notice/features/reminders/domain/usecases/request_alarm_permissions.dart';
import 'package:event_notice/features/reminders/domain/usecases/request_overlay_permission.dart';
import 'package:event_notice/features/reminders/domain/usecases/save_reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/schedule_alarms.dart';
import 'package:event_notice/features/reminders/domain/usecases/set_reminder_enabled.dart';
import 'package:event_notice/features/reminders/domain/usecases/snooze_alert.dart';
import 'package:event_notice/features/reminders/domain/usecases/start_alarm_sound.dart';
import 'package:event_notice/features/reminders/domain/usecases/stop_alarm_sound.dart';
import 'package:event_notice/features/reminders/domain/usecases/stop_ringing.dart';
import 'package:event_notice/features/reminders/domain/usecases/test_alarm_ring.dart';
import 'package:event_notice/features/reminders/domain/usecases/watch_reminders.dart';
import 'package:event_notice/features/reminders/presentation/reminder_alarm_body_formatter.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';

import '../domain/fakes.dart';

/// Thursday 22/10/2026 09:30.
final t0 = DateTime(2026, 10, 22, 9, 30);

/// A reminder on 22/10/2026 at [hour]:[minute], created at [t0] - 1 day.
Reminder reminder(
  String id, {
  String? title,
  String note = '',
  bool enabled = true,
  RepeatRule repeat = RepeatRule.once,
  DateTime? date,
  int hour = 10,
  int minute = 0,
  Set<int> weekdays = const {},
  int every = 0,
  TimeOfDay? end,
  int lead = 0,
  int snooze = 5,
  DateTime? snoozedUntil,
  DateTime? firedUpTo,
  bool isDeadline = false,
  DateTime? createdAt,
}) => Reminder(
  id: id,
  title: title ?? id,
  note: note,
  enabled: enabled,
  repeat: repeat,
  date: date ?? DateTime(2026, 10, 22),
  time: TimeOfDay(hour: hour, minute: minute),
  weekdays: weekdays,
  repeatEveryMinutes: every,
  endTime: end,
  leadMinutes: lead,
  snoozeMinutes: snooze,
  snoozedUntil: snoozedUntil,
  firedUpTo: firedUpTo,
  isDeadline: isDeadline,
  createdAt: createdAt ?? t0.subtract(const Duration(days: 1)),
);

/// A controller wired to [repo], [scheduler] and [ringer] through the real
/// use cases, with the time taken from [clock]. It rings natively when
/// [scheduler] does; the OS alarm bodies come from the real formatter.
RemindersController controllerFor(
  InMemoryReminderRepository repo, {
  required Clock clock,
  required FakeAlarmScheduler scheduler,
  FakeAlarmRinger? ringer,
  IdGenerator? ids,
}) {
  final sound = ringer ?? FakeAlarmRinger();
  return RemindersController(
    getReminders: GetReminders(repo, clock),
    watchReminders: WatchReminders(repo),
    newReminderId: NewReminderId(ids ?? SequentialIdGenerator()),
    saveReminder: SaveReminder(repo, clock),
    deleteReminder: DeleteReminder(repo),
    setReminderEnabled: SetReminderEnabled(repo, clock),
    getDueAlerts: GetDueAlerts(repo, clock),
    snoozeAlert: SnoozeAlert(repo, clock),
    dismissAlert: DismissAlert(repo),
    alertFromPayload: AlertFromPayload(repo),
    scheduleAlarms: ScheduleAlarms(
      repo,
      scheduler,
      BuildAlarmSchedule(const ReminderAlarmBodyFormatter(), clock),
      clock,
    ),
    stopRinging: StopRinging(scheduler),
    getRingingPayload: GetRingingPayload(scheduler),
    getLaunchPayload: GetLaunchPayload(scheduler),
    requestAlarmPermissions: RequestAlarmPermissions(scheduler),
    canScheduleExactAlarms: CanScheduleExactAlarms(scheduler),
    canDrawOverlays: CanDrawOverlays(scheduler),
    requestOverlayPermission: RequestOverlayPermission(scheduler),
    testAlarmRing: TestAlarmRing(scheduler),
    startAlarmSound: StartAlarmSound(sound),
    stopAlarmSound: StopAlarmSound(sound),
    clock: clock,
    ringsNatively: scheduler.ringsNatively,
  );
}
