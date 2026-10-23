import '../../../../core/domain/result.dart';
import '../entities/linked_reminder.dart';

/// The todo list's view of the reminders feature: looks up, switches and
/// removes the reminder an item was turned into. Implemented by an adapter in
/// `lib/app/di/bridges/`, so this feature never imports reminders.
///
/// No method throws: failures come back as an `Err`.
abstract interface class LinkedReminderRepository {
  /// The reminder with [id], or null when there is none — e.g. it has been
  /// deleted since the item was linked.
  Future<Result<LinkedReminder?>> find(String id);

  /// Switches the reminder with [id] on or off. An unknown id is not an error.
  Future<Result<void>> setEnabled(String id, bool enabled);

  /// Deletes the reminder with [id]. An unknown id is not an error.
  Future<Result<void>> remove(String id);

  /// Fires whenever reminders change or their countdowns move on, so a
  /// listener can look its linked reminders up again.
  Stream<void> get changes;
}
