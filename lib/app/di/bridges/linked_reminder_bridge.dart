import 'dart:async';

import '../../../core/domain/failure.dart';
import '../../../core/domain/result.dart';
import '../../../features/reminders/domain/entities/reminder.dart';
import '../../../features/reminders/domain/services/schedule_calculator.dart';
import '../../../features/reminders/presentation/reminders_controller.dart';
import '../../../features/todos/domain/entities/linked_reminder.dart';
import '../../../features/todos/domain/repositories/linked_reminder_repository.dart';

/// The todo list's [LinkedReminderRepository], backed by the app's
/// [RemindersController].
///
/// Switching and removing go through the controller rather than straight to
/// the reminders' use cases, so an alert of the reminder waiting on screen is
/// dropped with it and the OS alarm schedule is refilled.
class LinkedReminderBridge implements LinkedReminderRepository {
  LinkedReminderBridge(this._reminders);

  final RemindersController _reminders;

  /// Relays the controller's notifications. Listens to the controller only
  /// while someone listens here, so nothing is left attached once they cancel.
  late final StreamController<void> _changes = StreamController.broadcast(
    onListen: () => _reminders.addListener(_relay),
    onCancel: () => _reminders.removeListener(_relay),
  );

  void _relay() => _changes.add(null);

  @override
  Future<Result<LinkedReminder?>> find(String id) async {
    final r = _reminders.reminderById(id);
    return Ok(r == null ? null : toLinkedReminder(r, _reminders.now()));
  }

  @override
  Future<Result<void>> setEnabled(String id, bool enabled) =>
      _guard('switch', () => _reminders.setEnabled(id, enabled));

  @override
  Future<Result<void>> remove(String id) =>
      _guard('remove', () => _reminders.remove(id));

  /// Fires on every notification of the controller: edits, and the
  /// once-a-second tick that moves the countdowns while the window is on
  /// screen.
  @override
  Stream<void> get changes => _changes.stream;

  /// Runs [body] and reports the failure it left on the controller, if any:
  /// the controller records failures instead of returning them.
  Future<Result<void>> _guard(
    String action,
    Future<void> Function() body,
  ) async {
    final before = _reminders.failure;
    try {
      await body();
    } catch (e) {
      return Err(StorageFailure('Could not $action reminder', cause: e));
    }
    final after = _reminders.failure;
    if (after != null && !identical(after, before)) return Err(after);
    return const Ok(null);
  }
}

/// What the todo list sees of [r]; its next occurrence as of [now].
LinkedReminder toLinkedReminder(Reminder r, DateTime now) => LinkedReminder(
  id: r.id,
  title: r.title,
  isDeadline: r.isDeadline,
  enabled: r.enabled,
  nextOccurrence: ScheduleCalculator.nextOccurrence(r, now),
);
