import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/failure.dart';
import '../../../core/domain/result.dart';
import '../../../core/domain/usecase.dart';
import '../domain/entities/pending_alert.dart';
import '../domain/entities/reminder.dart';
import '../domain/services/reminder_ordering.dart';
import '../domain/usecases/alert_from_payload.dart';
import '../domain/usecases/can_draw_overlays.dart';
import '../domain/usecases/can_schedule_exact_alarms.dart';
import '../domain/usecases/delete_reminder.dart';
import '../domain/usecases/dismiss_alert.dart';
import '../domain/usecases/get_due_alerts.dart';
import '../domain/usecases/get_launch_payload.dart';
import '../domain/usecases/get_reminders.dart';
import '../domain/usecases/get_ringing_payload.dart';
import '../domain/usecases/new_reminder_id.dart';
import '../domain/usecases/request_alarm_permissions.dart';
import '../domain/usecases/request_overlay_permission.dart';
import '../domain/usecases/save_reminder.dart';
import '../domain/usecases/schedule_alarms.dart';
import '../domain/usecases/set_reminder_enabled.dart';
import '../domain/usecases/snooze_alert.dart';
import '../domain/usecases/start_alarm_sound.dart';
import '../domain/usecases/stop_alarm_sound.dart';
import '../domain/usecases/stop_ringing.dart';
import '../domain/usecases/test_alarm_ring.dart';
import '../domain/usecases/watch_reminders.dart';
import 'reminder_labels.dart';

/// The reminders on screen, the queue of alerts waiting to be shown, and the
/// once-a-second ticker that keeps both moving.
///
/// Where the app rings itself ([ringsNatively] false, desktop) every tick
/// asks [GetDueAlerts] for what came due; the tone starts with the first
/// alert in the queue and stops once the queue is empty. Where the OS rings
/// (Android) the OS alarm clock holds the schedule, which this refills after
/// every change, and every [ringPollTicks] ticks this checks what the OS is
/// ringing, so the alert on screen follows the native alarm both ways.
///
/// Only talks to use cases. Listens to [WatchReminders] and reloads the list
/// on every event. The [Clock] says what "now" is for the countdowns.
class RemindersController extends ChangeNotifier {
  RemindersController({
    required this._getReminders,
    required this._watchReminders,
    required this._newReminderId,
    required this._saveReminder,
    required this._deleteReminder,
    required this._setReminderEnabled,
    required this._getDueAlerts,
    required this._snoozeAlert,
    required this._dismissAlert,
    required this._alertFromPayload,
    required this._scheduleAlarms,
    required this._stopRinging,
    required this._getRingingPayload,
    required this._getLaunchPayload,
    required this._requestAlarmPermissions,
    required this._canScheduleExactAlarms,
    required this._canDrawOverlays,
    required this._requestOverlayPermission,
    required this._testAlarmRing,
    required this._startAlarmSound,
    required this._stopAlarmSound,
    required this._clock,
    required this.ringsNatively,
  });

  final GetReminders _getReminders;
  final WatchReminders _watchReminders;
  final NewReminderId _newReminderId;
  final SaveReminder _saveReminder;
  final DeleteReminder _deleteReminder;
  final SetReminderEnabled _setReminderEnabled;
  final GetDueAlerts _getDueAlerts;
  final SnoozeAlert _snoozeAlert;
  final DismissAlert _dismissAlert;
  final AlertFromPayload _alertFromPayload;
  final ScheduleAlarms _scheduleAlarms;
  final StopRinging _stopRinging;
  final GetRingingPayload _getRingingPayload;
  final GetLaunchPayload _getLaunchPayload;
  final RequestAlarmPermissions _requestAlarmPermissions;
  final CanScheduleExactAlarms _canScheduleExactAlarms;
  final CanDrawOverlays _canDrawOverlays;
  final RequestOverlayPermission _requestOverlayPermission;
  final TestAlarmRing _testAlarmRing;
  final StartAlarmSound _startAlarmSound;
  final StopAlarmSound _stopAlarmSound;
  final Clock _clock;

  /// True where the OS alarm clock rings (Android); false where the app's own
  /// ticker raises the alerts and plays the tone (desktop).
  final bool ringsNatively;

  /// How often the ticker runs.
  static const Duration tickInterval = Duration(seconds: 1);

  /// Ticks between two checks for a native alarm ringing right now.
  static const int ringPollTicks = 2;

  List<Reminder> _reminders = const [];
  final List<PendingAlert> _queue = [];

  /// Alerts taken off the queue whose closing is still being written. They
  /// count as waiting, so neither the ticker nor a ringing native alarm
  /// brings them back meanwhile.
  final List<PendingAlert> _closing = [];

  Failure? _failure;
  Timer? _ticker;
  final List<StreamSubscription<void>> _watches = [];
  bool _started = false;
  bool _disposed = false;

  /// Ticks since the last check for an alarm ringing right now (Android).
  int _ringPolls = 0;

  /// True once the native alarm was seen ringing for the alert on screen, so
  /// its silence afterwards means it was turned off outside the app — with a
  /// volume key, the power button or the notification's button.
  bool _nativeRinging = false;

  /// A tick's check is still running; the next tick skips its own.
  bool _raising = false;
  bool _polling = false;

  /// Bumped by every load, so a slow one that finishes after a newer one does
  /// not overwrite it.
  int _loads = 0;

  /// The newest load, so an action can wait until the state it leaves behind
  /// is on screen.
  Future<void> _latestLoad = Future.value();

  /// False while the window is hidden in the tray or the app is in the
  /// background: the clock and countdowns are not on screen, so repainting
  /// them every second is pure waste.
  bool uiActive = true;

  /// Called when an alert starts showing / when the last one is cleared, so the
  /// window can be brought to the front and released again.
  VoidCallback? onAlertShown;
  VoidCallback? onAlertsCleared;

  /// Every reminder and deadline in display order: switched-on ones first,
  /// soonest first.
  List<Reminder> get reminders => _reminders;

  /// The reminders tab: everything but the deadlines, in display order.
  List<Reminder> get plainReminders =>
      _reminders.where((r) => !r.isDeadline).toList();

  /// The deadlines tab as of now: nearest first, the ones already past at the
  /// bottom.
  List<Reminder> get deadlines => ReminderOrdering.deadlines(_reminders, now());

  /// The alert on screen, or null when nothing is ringing.
  PendingAlert? get currentAlert => _queue.isEmpty ? null : _queue.first;

  /// Why the last call failed, or null when it went through.
  Failure? get failure => _failure;

  /// The current time, for the clocks and countdowns.
  DateTime now() => _clock.now();

  Reminder? reminderById(String id) =>
      _reminders.where((r) => r.id == id).firstOrNull;

  /// What rings next, for the Android ongoing notification and the tray
  /// tooltip.
  String nextAlertSummary() =>
      describeNextAlert(ReminderOrdering.nextAlertAt(_reminders, now()));

  /// The nearest deadline still ahead and its countdown, or null when there
  /// is none.
  String? nearestDeadlineSummary() {
    final at = now();
    return describeNearestDeadline(
      ReminderOrdering.nearestDeadline(_reminders, at),
      at,
    );
  }

  // --------------------------------------------------------------- lifecycle

  /// Starts listening for changes, loads the list, starts the ticker and
  /// refills the OS alarm schedule. Safe to call twice.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    final watch = await _watchReminders(const NoParams());
    if (_disposed) return;
    if (watch case Ok(:final value)) {
      _watches.add(value.listen((_) => _reload()));
    }
    await _reload();
    if (_disposed) return;
    if (watch case Err(:final failure)) _failed(Err(failure));
    _ticker = Timer.periodic(tickInterval, (_) => _tick());
    await _schedule();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    for (final watch in _watches) {
      unawaited(watch.cancel());
    }
    // Leaving with an alert on screen must not leave the tone looping.
    if (_queue.isNotEmpty || _closing.isNotEmpty) {
      unawaited(_stopAlarmSound(const NoParams()));
    }
    super.dispose();
  }

  // ----------------------------------------------------------------- editing

  /// A fresh id for the editor to give a new reminder. Null if none could be
  /// made.
  Future<String?> newId() async {
    final result = await _newReminderId(const NoParams());
    if (_failed(result)) return null;
    return result.valueOrNull;
  }

  /// Adds [reminder], or replaces the one with the same id, and returns what
  /// was stored; null when it could not be. Nothing before now rings for it.
  Future<Reminder?> save(Reminder reminder) async {
    final result = await _saveReminder(reminder);
    if (_failed(result)) return null;
    await _afterWrite();
    return result.valueOrNull;
  }

  /// Switches the reminder with [id] on or off, dropping any snooze.
  Future<void> setEnabled(String id, bool enabled) async {
    final result = await _setReminderEnabled((id: id, enabled: enabled));
    if (_failed(result)) return;
    await _afterWrite();
  }

  /// Deletes the reminder with [id], along with its alerts in the queue.
  Future<void> remove(String id) async {
    final passed = List.of(_queue);
    final result = await _deleteReminder((id: id, pending: passed));
    if (_failed(result)) return;
    final kept = result.valueOrNull ?? passed;
    final dropped = [
      for (final a in passed)
        if (!kept.any((k) => identical(k, a))) a,
    ];
    final hadAlert = _queue.isNotEmpty;
    // Alerts queued while deleting were not passed in, so they stay.
    _queue.removeWhere((a) => dropped.any((d) => identical(d, a)));
    if (hadAlert && _queue.isEmpty) await _alertsCleared();
    await _afterWrite();
  }

  // ------------------------------------------------------------------ alerts

  /// Turns off the alert on screen. A one-off reminder is marked done.
  Future<void> dismissCurrent() => _closeCurrent(_dismissAlert.call);

  /// Rings the alert on screen again after its reminder's snooze interval.
  Future<void> snoozeCurrent() => _closeCurrent(_snoozeAlert.call);

  /// Turns off every alert waiting on screen (closing the alarm window).
  Future<void> dismissAll() async {
    while (_queue.isNotEmpty && !_disposed) {
      await dismissCurrent();
    }
  }

  /// Shows the alert carried by an OS alarm payload, unless its reminder is
  /// gone or already has an alert waiting.
  Future<void> showAlertFromPayload(String payload) async {
    final result = await _alertFromPayload((
      payload: payload,
      queued: [..._queue, ..._closing],
    ));
    if (_disposed) return;
    switch (result) {
      case Ok(value: final alert?):
        _enqueue(alert, ring: false);
      case Ok():
        break;
      case Err(:final failure):
        _failed(Err(failure));
    }
  }

  /// Shows the alert of the OS alarm ringing right now, if any.
  Future<void> showRingingAlert() async {
    final result = await _getRingingPayload(const NoParams());
    if (_disposed || _failed(result)) return;
    final payload = result.valueOrNull;
    if (payload != null) await showAlertFromPayload(payload);
  }

  /// Shows the alert of the OS alarm that opened the app; when a full-screen
  /// alarm woke it instead (no tap, no payload), the one ringing right now.
  Future<void> showLaunchAlert() async {
    final result = await _getLaunchPayload(const NoParams());
    if (_disposed || _failed(result)) return;
    final payload = result.valueOrNull;
    if (payload != null) {
      await showAlertFromPayload(payload);
    } else {
      await showRingingAlert();
    }
  }

  /// Re-fills the OS alarm schedule, e.g. when the app comes back to the
  /// front, and picks up an alarm that is ringing right now.
  Future<void> resync() async {
    await showRingingAlert();
    if (_disposed) return;
    await _schedule();
    _notify();
  }

  // ------------------------------------------------------- OS alarm settings

  /// Asks for notifications and the "Alarms & reminders" permission.
  Future<void> requestPermissions() async {
    _failed(await _requestAlarmPermissions(const NoParams()));
  }

  /// Whether OS alarms may ring at the exact minute; false when unknown.
  Future<bool> canScheduleExactAlarms() async {
    final result = await _canScheduleExactAlarms(const NoParams());
    if (_failed(result)) return false;
    return result.valueOrNull ?? false;
  }

  /// Whether the alarm may take over the screen; false when unknown.
  Future<bool> canDrawOverlays() async {
    final result = await _canDrawOverlays(const NoParams());
    if (_failed(result)) return false;
    return result.valueOrNull ?? false;
  }

  /// Opens the "display over other apps" settings screen.
  Future<void> requestOverlayPermission() async {
    _failed(await _requestOverlayPermission(const NoParams()));
  }

  /// Rings an OS alarm right now so the user can check the sound.
  Future<void> testRing() async {
    _failed(await _testAlarmRing(const NoParams()));
  }

  // ---------------------------------------------------------------- internal

  void _tick() {
    if (_disposed) return;
    if (!ringsNatively) {
      unawaited(_raiseDueAlerts());
    } else if (++_ringPolls >= ringPollTicks) {
      // Android: the alarm can start and stop while this screen is already in
      // front, so there is no resume event to hang the check on.
      _ringPolls = 0;
      unawaited(_syncWithNativeRing());
    }
    if (uiActive) _notify(); // keeps the countdowns on screen live
  }

  Future<void> _raiseDueAlerts() async {
    if (_raising) return;
    _raising = true;
    try {
      final result = await _getDueAlerts([..._queue, ..._closing]);
      if (_disposed) return;
      switch (result) {
        case Ok(:final value):
          for (final alert in value.alerts) {
            _enqueue(alert, ring: true);
          }
          // The alarm rings anyway; the watermark is reported as not saved.
          if (value.saveFailure case final failure?) _failed(Err(failure));
        case Err(:final failure):
          _failed(Err(failure));
      }
    } finally {
      _raising = false;
    }
  }

  /// Keeps the screen in step with the native alarm.
  ///
  /// It rings on its own schedule and can be silenced without touching the
  /// app — a volume key, the power button, the notification's button — so the
  /// alert on screen follows it both ways.
  Future<void> _syncWithNativeRing() async {
    // While an alert is being closed its alarm may still ring for a moment;
    // that is not a new ring, and the silence after it is not a hardware key.
    if (_polling || _closing.isNotEmpty) return;
    _polling = true;
    try {
      final result = await _getRingingPayload(const NoParams());
      if (_disposed || _failed(result)) return;
      final payload = result.valueOrNull;
      if (payload != null) {
        _nativeRinging = true;
        await showAlertFromPayload(payload);
      } else if (_nativeRinging) {
        _nativeRinging = false;
        if (_queue.isNotEmpty) await dismissCurrent();
      }
    } finally {
      _polling = false;
    }
  }

  /// Puts [alert] in the queue unless its reminder already has one there. The
  /// first alert brings the window up and, when [ring] is set, starts the
  /// app's own tone.
  void _enqueue(PendingAlert alert, {required bool ring}) {
    if (_queue.any((a) => a.reminder.id == alert.reminder.id)) return;
    _queue.add(alert);
    if (_queue.length == 1) {
      if (ring) unawaited(_startAlarmSound(const NoParams()));
      onAlertShown?.call();
    }
    _notify();
  }

  /// Takes the alert on screen off the queue, then lets [close] record what
  /// the user did with it.
  Future<void> _closeCurrent(
    Future<Result<void>> Function(PendingAlert alert) close,
  ) async {
    if (_queue.isEmpty) return;
    // The app is closing this one itself, so the silence that follows is not a
    // hardware key and must not close the next alert in the queue too.
    _nativeRinging = false;
    final alert = _queue.removeAt(0);
    _closing.add(alert);
    _notify();
    if (_queue.isEmpty) await _alertsCleared();
    _failed(await close(alert));
    // Silences the ringing alarm on Android; the rest is rescheduled below.
    _failed(await _stopRinging(const NoParams()));
    _closing.removeWhere((a) => identical(a, alert));
    await _afterWrite();
  }

  /// Stops the app's tone and lets the window go, once no alert is left.
  Future<void> _alertsCleared() async {
    _failed(await _stopAlarmSound(const NoParams()));
    onAlertsCleared?.call();
  }

  /// Puts what a write left behind on screen, then refills the OS schedule.
  Future<void> _afterWrite() async {
    if (_disposed) return;
    await _reload();
    await _settle();
    await _schedule();
  }

  Future<void> _schedule() async {
    if (_disposed) return;
    _failed(await _scheduleAlarms(const NoParams()));
  }

  Future<void> _reload() => _latestLoad = _load(++_loads);

  Future<void> _load(int load) async {
    final result = await _getReminders(const NoParams());
    if (_disposed || load != _loads) return;
    switch (result) {
      case Ok(:final value):
        _reminders = List.unmodifiable(value);
        _failure = null;
      case Err(:final failure):
        _failure = failure;
    }
    _notify();
  }

  /// Waits until the newest load is done, including one a watch event
  /// started meanwhile: it supersedes the load the action itself started.
  Future<void> _settle() async {
    while (true) {
      final load = _latestLoad;
      await load;
      if (identical(load, _latestLoad)) return;
    }
  }

  /// Records the failure of [result], if any, and tells the listeners.
  bool _failed(Result<Object?> result) {
    if (result case Err(:final failure)) {
      _failure = failure;
      _notify();
      return true;
    }
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
