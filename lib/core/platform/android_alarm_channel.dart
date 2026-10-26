import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The `event_notice/alarm` method channel to the Android side, which hands
/// alarms to the OS alarm clock so they ring while the app is closed or the
/// phone is asleep.
///
/// The native side (`AlarmService.kt`) plays the tone itself on the alarm
/// stream instead of relying on a notification sound, which is what makes it
/// behave like a real alarm clock rather than a reminder popup.
///
/// Only the transport: what goes into an alarm is the caller's business.
/// Platform errors are thrown as they come.
class AndroidAlarmChannel {
  const AndroidAlarmChannel();

  static const channel = MethodChannel('event_notice/alarm');

  /// Asks for notifications and the "Alarms & reminders" permission.
  Future<void> requestPermissions() =>
      channel.invokeMethod<void>('requestPermissions');

  Future<bool> canScheduleExact() async =>
      await channel.invokeMethod<bool>('canScheduleExact') ?? false;

  /// Payload of the alarm ringing right now, if any.
  Future<String?> ringingPayload() =>
      channel.invokeMethod<String>('ringingPayload');

  /// Payload carried by the intent that opened the app, if it was an alarm.
  Future<String?> launchPayload() =>
      channel.invokeMethod<String>('launchPayload');

  /// Rings right now so the user can check the sound without waiting.
  Future<void> testRing() => channel.invokeMethod<void>('testRing');

  Future<bool> canDrawOverlays() async =>
      await channel.invokeMethod<bool>('canDrawOverlays') ?? false;

  /// Opens the "display over other apps" screen, which is what lets the alarm
  /// take over the screen while the phone is unlocked and in use.
  Future<void> requestOverlayPermission() =>
      channel.invokeMethod<void>('requestOverlayPermission');

  /// Silences the alarm that is ringing.
  Future<void> stopRinging() {
    debugPrint('[alarm] stopRinging called from: ${StackTrace.current}');
    return channel.invokeMethod<void>('stopRinging');
  }

  /// Replaces the whole pending schedule with [alarms], each a map of `id`
  /// (int), `at` (epoch milliseconds), `title`, `body` and `payload`.
  Future<void> scheduleAll(List<Map<String, Object>> alarms) =>
      channel.invokeMethod<int>('scheduleAll', {'alarms': alarms});
}
