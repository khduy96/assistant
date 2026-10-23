import '../../../../core/domain/result.dart';
import '../entities/scheduled_alarm.dart';

/// The OS alarm clock, which rings while the app is closed or the phone is
/// asleep (Android). Payloads are those of `AlarmPayload`.
///
/// Where the OS does not ring for the app ([ringsNatively] false, i.e.
/// desktop), the app's own ticker raises alerts and every other method does
/// nothing: the payloads are null and the checks false.
///
/// No method throws: platform errors come back as an `Err`.
abstract interface class AlarmScheduler {
  /// True where the OS rings the alarms; false where the app has to.
  bool get ringsNatively;

  /// Replaces the whole pending schedule with [alarms].
  Future<Result<void>> scheduleAll(List<ScheduledAlarm> alarms);

  /// Silences the alarm that is ringing.
  Future<Result<void>> stopRinging();

  /// Payload of the alarm ringing right now, if any.
  Future<Result<String?>> ringingPayload();

  /// Payload carried by whatever opened the app, if it was an alarm.
  Future<Result<String?>> launchPayload();

  /// Asks for notifications and the "Alarms & reminders" permission.
  Future<Result<void>> requestPermissions();

  /// Whether alarms may ring at the exact minute.
  Future<Result<bool>> canScheduleExactAlarms();

  /// Whether the alarm may take over the screen while the phone is in use.
  Future<Result<bool>> canDrawOverlays();

  /// Opens the "display over other apps" settings screen.
  Future<Result<void>> requestOverlayPermission();

  /// Rings right now so the user can check the sound without waiting.
  Future<Result<void>> testRing();
}
