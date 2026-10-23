import 'dart:io';

import 'package:get_it/get_it.dart';

import 'data/alarm_sound_ringer.dart';
import 'data/android_alarm_scheduler.dart';
import 'data/datasources/reminder_local_data_source.dart';
import 'data/noop_alarm_scheduler.dart';
import 'data/repositories/reminder_repository_impl.dart';
import 'domain/ports/alarm_body_formatter.dart';
import 'domain/ports/alarm_ringer.dart';
import 'domain/ports/alarm_scheduler.dart';
import 'domain/repositories/reminder_repository.dart';
import 'domain/usecases/alert_from_payload.dart';
import 'domain/usecases/build_alarm_schedule.dart';
import 'domain/usecases/can_draw_overlays.dart';
import 'domain/usecases/can_schedule_exact_alarms.dart';
import 'domain/usecases/delete_reminder.dart';
import 'domain/usecases/dismiss_alert.dart';
import 'domain/usecases/get_due_alerts.dart';
import 'domain/usecases/get_launch_payload.dart';
import 'domain/usecases/get_reminders.dart';
import 'domain/usecases/get_ringing_payload.dart';
import 'domain/usecases/new_reminder_id.dart';
import 'domain/usecases/request_alarm_permissions.dart';
import 'domain/usecases/request_overlay_permission.dart';
import 'domain/usecases/save_reminder.dart';
import 'domain/usecases/schedule_alarms.dart';
import 'domain/usecases/set_reminder_enabled.dart';
import 'domain/usecases/snooze_alert.dart';
import 'domain/usecases/start_alarm_sound.dart';
import 'domain/usecases/stop_alarm_sound.dart';
import 'domain/usecases/stop_ringing.dart';
import 'domain/usecases/test_alarm_ring.dart';
import 'domain/usecases/watch_reminders.dart';
import 'presentation/reminder_alarm_body_formatter.dart';
import 'presentation/reminders_controller.dart';

/// Registers the reminders feature in [sl]. Expects a `Clock` and an
/// `IdGenerator` to be registered already.
///
/// Android hands the schedule to the OS alarm clock ([AndroidAlarmScheduler]);
/// everywhere else the controller's own ticker rings, so the OS side is a
/// [NoopAlarmScheduler].
///
/// [ReminderRepositoryImpl] is one singleton seen under two types: the use
/// cases get it as [ReminderRepository], while the app shell closes it.
/// [RemindersController] is a singleton too: the app shell and the todo
/// list's bridges share its queue of alerts. The app shell disposes it, and
/// the [AlarmRinger] after it.
void registerReminders(GetIt sl) {
  sl
    ..registerLazySingleton(() => ReminderLocalDataSource(sl()))
    ..registerLazySingleton(() => ReminderRepositoryImpl(sl()))
    ..registerLazySingleton<ReminderRepository>(
      () => sl<ReminderRepositoryImpl>(),
    )
    ..registerLazySingleton<AlarmScheduler>(
      () => Platform.isAndroid
          ? const AndroidAlarmScheduler()
          : const NoopAlarmScheduler(),
    )
    ..registerLazySingleton<AlarmRinger>(() => AlarmSoundRinger())
    ..registerLazySingleton<AlarmBodyFormatter>(
      () => const ReminderAlarmBodyFormatter(),
    )
    ..registerLazySingleton(() => GetReminders(sl(), sl()))
    ..registerLazySingleton(() => WatchReminders(sl()))
    ..registerLazySingleton(() => NewReminderId(sl()))
    ..registerLazySingleton(() => SaveReminder(sl(), sl()))
    ..registerLazySingleton(() => DeleteReminder(sl()))
    ..registerLazySingleton(() => SetReminderEnabled(sl(), sl()))
    ..registerLazySingleton(() => GetDueAlerts(sl(), sl()))
    ..registerLazySingleton(() => SnoozeAlert(sl(), sl()))
    ..registerLazySingleton(() => DismissAlert(sl()))
    ..registerLazySingleton(() => AlertFromPayload(sl()))
    ..registerLazySingleton(() => BuildAlarmSchedule(sl(), sl()))
    ..registerLazySingleton(() => ScheduleAlarms(sl(), sl(), sl(), sl()))
    ..registerLazySingleton(() => StopRinging(sl()))
    ..registerLazySingleton(() => GetRingingPayload(sl()))
    ..registerLazySingleton(() => GetLaunchPayload(sl()))
    ..registerLazySingleton(() => RequestAlarmPermissions(sl()))
    ..registerLazySingleton(() => CanScheduleExactAlarms(sl()))
    ..registerLazySingleton(() => CanDrawOverlays(sl()))
    ..registerLazySingleton(() => RequestOverlayPermission(sl()))
    ..registerLazySingleton(() => TestAlarmRing(sl()))
    ..registerLazySingleton(() => StartAlarmSound(sl()))
    ..registerLazySingleton(() => StopAlarmSound(sl()))
    ..registerLazySingleton(
      () => RemindersController(
        getReminders: sl(),
        watchReminders: sl(),
        newReminderId: sl(),
        saveReminder: sl(),
        deleteReminder: sl(),
        setReminderEnabled: sl(),
        getDueAlerts: sl(),
        snoozeAlert: sl(),
        dismissAlert: sl(),
        alertFromPayload: sl(),
        scheduleAlarms: sl(),
        stopRinging: sl(),
        getRingingPayload: sl(),
        getLaunchPayload: sl(),
        requestAlarmPermissions: sl(),
        canScheduleExactAlarms: sl(),
        canDrawOverlays: sl(),
        requestOverlayPermission: sl(),
        testAlarmRing: sl(),
        startAlarmSound: sl(),
        stopAlarmSound: sl(),
        clock: sl(),
        ringsNatively: sl<AlarmScheduler>().ringsNatively,
      ),
    );
}
