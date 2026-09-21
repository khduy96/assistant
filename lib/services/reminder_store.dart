import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/reminder.dart';
import '../ui/format.dart';
import 'alarm_sound.dart';
import 'android_alarm_service.dart';
import 'storage_service.dart';

/// An alert that is due and waiting to be shown.
class PendingAlert {
  PendingAlert({required this.reminder, required this.at, required this.eventAt, required this.isLead});

  final Reminder reminder;
  final DateTime at;
  final DateTime eventAt;

  /// True for the "remind me N minutes before" alert, false for the event itself.
  final bool isLead;
}

/// Holds every reminder, ticks once a second and raises alerts when due.
///
/// On desktop the in-app ticker is what rings. On Android the OS alarm clock
/// rings (see [AndroidAlarmService]) because the app is usually not
/// running, and the ticker only keeps the countdowns on screen fresh.
class ReminderStore extends ChangeNotifier {
  ReminderStore({AlarmSound? sound, this.notifications})
      : _sound = sound ?? AlarmSound();

  /// Alerts missed by more than this (app closed, machine asleep) are skipped
  /// instead of ringing long after the fact.
  static const catchUpWindow = Duration(minutes: 30);

  /// True where a running Dart timer is what raises alerts.
  static final ringsInApp = !Platform.isAndroid && !Platform.isIOS;

  final _storage = StorageService();
  final AlarmSound _sound;
  final _uuid = const Uuid();

  /// Only set on Android.
  final AndroidAlarmService? notifications;

  final List<Reminder> _reminders = [];
  final List<PendingAlert> _queue = [];
  Timer? _ticker;

  /// Ticks since the last check for an alarm ringing right now (Android).
  int _ringPolls = 0;

  /// True once the native alarm was seen ringing for the alert on screen, so
  /// its silence afterwards means it was turned off outside the app — with a
  /// volume key, the power button or the notification's button.
  bool _nativeRinging = false;

  /// False while the window is hidden in the tray or the app is in the
  /// background: the clock and countdowns are not on screen, so repainting
  /// them every second is pure waste.
  bool uiActive = true;

  /// Called when an alert starts showing / when the last one is cleared, so the
  /// window can be brought to the front and released again.
  VoidCallback? onAlertShown;
  VoidCallback? onAlertsCleared;

  List<Reminder> get reminders => List.unmodifiable(_reminders);

  PendingAlert? get currentAlert => _queue.isEmpty ? null : _queue.first;

  Future<void> init() async {
    _reminders.addAll(await _storage.load());
    _sortReminders();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
    await notifications?.sync(_reminders);
  }

  String newId() => _uuid.v4();

  Future<void> upsert(Reminder reminder) async {
    final i = _reminders.indexWhere((r) => r.id == reminder.id);
    // Anything before now is considered handled, so editing never fires the past.
    reminder.firedUpTo = DateTime.now();
    if (i == -1) {
      _reminders.add(reminder);
    } else {
      _reminders[i] = reminder;
    }
    _sortReminders();
    await _persist();
  }

  Future<void> remove(String id) async {
    _reminders.removeWhere((r) => r.id == id);
    _queue.removeWhere((a) => a.reminder.id == id);
    await _persist();
  }

  Future<void> setEnabled(Reminder reminder, bool enabled) async {
    reminder.enabled = enabled;
    reminder.snoozedUntil = null;
    reminder.firedUpTo = DateTime.now();
    _sortReminders();
    await _persist();
  }

  /// Shows the alert carried by an Android alarm payload.
  Future<void> showAlertFromPayload(String payload) async {
    final parsed = parseAlarmPayload(payload);
    if (parsed == null) return;
    final reminder =
        _reminders.where((r) => r.id == parsed.reminderId).firstOrNull;
    if (reminder == null) return;
    if (_queue.any((a) => a.reminder.id == reminder.id)) return;

    _queue.add(PendingAlert(
      reminder: reminder,
      at: parsed.at,
      eventAt: parsed.isLead
          ? parsed.at.add(Duration(minutes: reminder.leadMinutes))
          : parsed.at,
      isLead: parsed.isLead,
    ));
    if (_queue.length == 1) onAlertShown?.call();
    notifyListeners();
  }

  /// Turns off the current alert. A one-off reminder is marked done.
  Future<void> dismissCurrent() async {
    final alert = currentAlert;
    if (alert == null) return;
    final r = alert.reminder;
    r.snoozedUntil = null;
    if (!alert.isLead && r.repeat == RepeatRule.once) r.enabled = false;
    await _closeCurrent();
  }

  /// Rings again after the reminder's snooze interval.
  Future<void> snoozeCurrent() async {
    final alert = currentAlert;
    if (alert == null) return;
    final r = alert.reminder;
    r.snoozedUntil = DateTime.now().add(Duration(minutes: r.snoozeMinutes));
    r.firedUpTo = DateTime.now();
    await _closeCurrent();
  }

  /// Turns off every alert waiting on screen (closing the alarm window).
  Future<void> dismissAll() async {
    while (_queue.isNotEmpty) {
      await dismissCurrent();
    }
  }

  /// Re-fills the OS alarm schedule, e.g. when the app comes back to the front,
  /// and picks up an alarm that is ringing right now.
  Future<void> resync() async {
    await showRingingAlert();
    await notifications?.sync(_reminders);
    notifyListeners();
  }

  /// One-line summary of what rings next, shown in the Android ongoing
  /// notification.
  String nextAlertSummary() {
    final upcoming = <DateTime>[];
    for (final r in _reminders) {
      final next = r.nextAlertAfter(DateTime.now());
      if (next != null) upcoming.add(next);
    }
    if (upcoming.isEmpty) return 'Chưa có nhắc nhở nào đang bật';
    upcoming.sort();
    return 'Lần báo kế tiếp: ${formatDateTime(upcoming.first)}';
  }

  /// Nearest deadline still ahead, for the tray tooltip / ongoing notification.
  String? nearestDeadlineSummary() {
    final upcoming = _reminders
        .where((r) => r.isDeadline && !r.timeLeft.isNegative)
        .toList()
      ..sort((a, b) => a.deadlineAt.compareTo(b.deadlineAt));
    if (upcoming.isEmpty) return null;
    final next = upcoming.first;
    return '${next.title}: còn ${formatLongCountdown(next.timeLeft)}';
  }

  /// Shows the alert for a notification that is currently ringing, if any.
  Future<void> showRingingAlert() async {
    final payload = await notifications?.ringingPayload();
    if (payload != null) await showAlertFromPayload(payload);
  }

  /// Keeps the screen in step with the native alarm.
  ///
  /// It rings on its own schedule and can be silenced without touching the
  /// app — a volume key, the power button, the notification's button — so the
  /// alert on screen follows it both ways.
  Future<void> _syncWithNativeRing() async {
    final payload = await notifications?.ringingPayload();
    if (payload != null) {
      _nativeRinging = true;
      await showAlertFromPayload(payload);
    } else if (_nativeRinging) {
      _nativeRinging = false;
      if (_queue.isNotEmpty) await dismissCurrent();
    }
  }

  Future<void> _closeCurrent() async {
    // The app is closing this one itself, so the silence that follows is not a
    // hardware key and must not close the next alert in the queue too.
    _nativeRinging = false;
    _queue.removeAt(0);
    _sortReminders();
    if (_queue.isEmpty) {
      await _sound.stop();
      onAlertsCleared?.call();
    }
    // Silences the ringing alarm on Android; _persist reschedules the rest.
    await notifications?.stopRinging();
    await _persist();
  }

  void _tick() {
    if (ringsInApp) {
      _raiseDueAlerts();
    } else if (++_ringPolls >= 2) {
      // Android: the alarm can start and stop while this screen is already in
      // front, so there is no resume event to hang the check on.
      _ringPolls = 0;
      unawaited(_syncWithNativeRing());
    }
    if (uiActive) notifyListeners(); // keeps the countdowns on screen live
  }

  void _raiseDueAlerts() {
    final now = DateTime.now();
    var changed = false;

    for (final r in _reminders) {
      if (_queue.any((a) => a.reminder.id == r.id)) continue;
      final info = r.nextAlertInfoAfter(
          r.firedUpTo ?? now.subtract(const Duration(seconds: 1)));
      if (info == null || info.at.isAfter(now)) continue;

      r.firedUpTo = info.at;
      r.snoozedUntil = null;
      changed = true;

      if (now.difference(info.at) > catchUpWindow) continue; // too stale to ring
      _queue.add(PendingAlert(
        reminder: r,
        at: info.at,
        eventAt: info.eventAt,
        isLead: info.isLead,
      ));
      if (_queue.length == 1) {
        _sound.start();
        onAlertShown?.call();
      }
    }

    if (changed) {
      _sortReminders();
      unawaited(_persist());
    }
  }

  void _sortReminders() {
    _reminders.sort((a, b) {
      final an = a.nextOccurrence, bn = b.nextOccurrence;
      if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
      if (an == null && bn == null) return a.title.compareTo(b.title);
      if (an == null) return 1;
      if (bn == null) return -1;
      return an.compareTo(bn);
    });
  }

  Future<void> _persist() async {
    await _storage.save(_reminders);
    await notifications?.sync(_reminders);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sound.dispose();
    super.dispose();
  }
}
