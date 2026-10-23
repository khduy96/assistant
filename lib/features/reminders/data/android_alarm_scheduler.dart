import '../../../core/domain/failure.dart';
import '../../../core/domain/result.dart';
import '../../../core/platform/android_alarm_channel.dart';
import '../domain/entities/scheduled_alarm.dart';
import '../domain/ports/alarm_scheduler.dart';

/// The Android alarm clock, reached through [AndroidAlarmChannel]. The OS
/// rings the alarms itself, so the app's ticker does not.
class AndroidAlarmScheduler implements AlarmScheduler {
  const AndroidAlarmScheduler([this._channel = const AndroidAlarmChannel()]);

  final AndroidAlarmChannel _channel;

  @override
  bool get ringsNatively => true;

  @override
  Future<Result<void>> scheduleAll(List<ScheduledAlarm> alarms) => _call(
    'scheduleAll',
    () => _channel.scheduleAll([
      for (final a in alarms)
        {
          'id': a.id,
          'at': a.at.millisecondsSinceEpoch,
          'title': a.title,
          'body': a.body,
          'payload': a.payload,
        },
    ]),
  );

  @override
  Future<Result<void>> stopRinging() =>
      _call('stopRinging', _channel.stopRinging);

  @override
  Future<Result<String?>> ringingPayload() =>
      _call('ringingPayload', _channel.ringingPayload);

  @override
  Future<Result<String?>> launchPayload() =>
      _call('launchPayload', _channel.launchPayload);

  @override
  Future<Result<void>> requestPermissions() =>
      _call('requestPermissions', _channel.requestPermissions);

  @override
  Future<Result<bool>> canScheduleExactAlarms() =>
      _call('canScheduleExact', _channel.canScheduleExact);

  @override
  Future<Result<bool>> canDrawOverlays() =>
      _call('canDrawOverlays', _channel.canDrawOverlays);

  @override
  Future<Result<void>> requestOverlayPermission() =>
      _call('requestOverlayPermission', _channel.requestOverlayPermission);

  @override
  Future<Result<void>> testRing() => _call('testRing', _channel.testRing);

  /// Runs one channel call, turning whatever it throws (a
  /// `PlatformException`, or a `MissingPluginException` when the native side
  /// is absent) into an [Err].
  Future<Result<T>> _call<T>(String method, Future<T> Function() body) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(UnexpectedFailure('Alarm call $method failed', cause: e));
    }
  }
}
