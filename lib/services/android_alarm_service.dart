import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/reminder.dart';
import '../ui/format.dart';

/// Android alarms, handed to the OS alarm clock so they ring while the app is
/// closed or the phone is asleep.
///
/// The native side (`AlarmService.kt`) plays the tone itself on the alarm
/// stream instead of relying on a notification sound, which is what makes it
/// behave like a real alarm clock rather than a reminder popup.
///
/// Payloads are `reminderId|epochMillis|isLead`, so the app can rebuild the
/// alert when the alarm opens it.
class AndroidAlarmService {
  static const _channel = MethodChannel('event_notice/alarm');

  /// Alarms handed to the OS at a time. Android caps pending alarms per app,
  /// and the list is refreshed on every save and on resume.
  static const _scheduleLimit = 48;
  static const _perReminderLimit = 8;

  /// Asks for notifications and the "Alarms & reminders" permission.
  Future<void> requestPermissions() async {
    await _channel.invokeMethod<void>('requestPermissions');
  }

  Future<bool> canScheduleExactAlarms() async =>
      await _channel.invokeMethod<bool>('canScheduleExact') ?? false;

  /// Payload of the alarm ringing right now, if any.
  Future<String?> ringingPayload() =>
      _channel.invokeMethod<String>('ringingPayload');

  /// Payload carried by the intent that opened the app, if it was an alarm.
  Future<String?> launchPayload() =>
      _channel.invokeMethod<String>('launchPayload');

  /// Rings right now so the user can check the sound without waiting.
  Future<void> testRing() => _channel.invokeMethod<void>('testRing');

  Future<bool> canDrawOverlays() async =>
      await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;

  /// Opens the "display over other apps" screen, which is what lets the alarm
  /// take over the screen while the phone is unlocked and in use.
  Future<void> requestOverlayPermission() =>
      _channel.invokeMethod<void>('requestOverlayPermission');

  /// Silences the alarm that is ringing.
  Future<void> stopRinging() {
    debugPrint('[alarm] stopRinging called from: ${StackTrace.current}');
    return _channel.invokeMethod<void>('stopRinging');
  }

  /// Replaces the whole pending schedule with the next alerts of [reminders].
  Future<void> sync(List<Reminder> reminders) async {
    final now = DateTime.now();
    final pending =
        <({Reminder reminder, DateTime at, DateTime eventAt, bool isLead})>[];
    for (final r in reminders.where((r) => r.enabled)) {
      for (final alert in r.upcomingAlerts(_perReminderLimit, from: now)) {
        pending.add((
          reminder: r,
          at: alert.at,
          eventAt: alert.eventAt,
          isLead: alert.isLead,
        ));
      }
    }
    pending.sort((a, b) => a.at.compareTo(b.at));

    var id = 1;
    final alarms = <Map<String, Object>>[];
    for (final item in pending.take(_scheduleLimit)) {
      alarms.add({
        'id': id++,
        'at': item.at.millisecondsSinceEpoch,
        'title': item.reminder.title,
        'body': _body(item.reminder, item.eventAt, item.isLead),
        'payload': '${item.reminder.id}|${item.at.millisecondsSinceEpoch}'
            '|${item.isLead ? 1 : 0}',
      });
    }
    await _channel.invokeMethod<int>('scheduleAll', {'alarms': alarms});
  }

  String _body(Reminder reminder, DateTime eventAt, bool isLead) {
    final at = '${two(eventAt.hour)}:${two(eventAt.minute)}';
    if (isLead) {
      return 'Còn ${reminder.leadMinutes} phút nữa — bắt đầu lúc $at';
    }
    final note = reminder.note.trim();
    return 'Đến giờ rồi — $at${note.isEmpty ? '' : ' · $note'}';
  }
}

/// Parsed form of an alarm payload.
({String reminderId, DateTime at, bool isLead})? parseAlarmPayload(String raw) {
  final parts = raw.split('|');
  if (parts.length != 3) return null;
  final millis = int.tryParse(parts[1]);
  if (millis == null) return null;
  return (
    reminderId: parts[0],
    at: DateTime.fromMillisecondsSinceEpoch(millis),
    isLead: parts[2] == '1',
  );
}
