import '../../../core/domain/result.dart';
import '../domain/entities/scheduled_alarm.dart';
import '../domain/ports/alarm_scheduler.dart';

/// Where the OS does not ring for the app (desktop): the app's own ticker
/// raises the alerts, so there is nothing to hand over. Every call succeeds
/// and does nothing; the payloads are null and the checks false.
class NoopAlarmScheduler implements AlarmScheduler {
  const NoopAlarmScheduler();

  @override
  bool get ringsNatively => false;

  @override
  Future<Result<void>> scheduleAll(List<ScheduledAlarm> alarms) async =>
      const Ok(null);

  @override
  Future<Result<void>> stopRinging() async => const Ok(null);

  @override
  Future<Result<String?>> ringingPayload() async => const Ok(null);

  @override
  Future<Result<String?>> launchPayload() async => const Ok(null);

  @override
  Future<Result<void>> requestPermissions() async => const Ok(null);

  @override
  Future<Result<bool>> canScheduleExactAlarms() async => const Ok(false);

  @override
  Future<Result<bool>> canDrawOverlays() async => const Ok(false);

  @override
  Future<Result<void>> requestOverlayPermission() async => const Ok(null);

  @override
  Future<Result<void>> testRing() async => const Ok(null);
}
