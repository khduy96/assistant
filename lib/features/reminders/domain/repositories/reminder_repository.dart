import '../../../../core/domain/result.dart';
import '../entities/reminder.dart';

/// Where reminders are kept. Implemented in the data layer.
///
/// The ticker asks for the reminders once a second on desktop, so an
/// implementation keeps them in memory and only touches the disk on writes;
/// a write updates the memory copy even when the disk write then fails.
///
/// No method throws: IO and format errors come back as an `Err`.
abstract interface class ReminderRepository {
  /// Every stored reminder, in no particular order.
  Future<Result<List<Reminder>>> getAll();

  /// The reminder with [id], or null when there is none.
  Future<Result<Reminder?>> find(String id);

  /// Adds [reminder], or replaces the stored reminder with the same id.
  Future<Result<void>> save(Reminder reminder);

  /// Saves every reminder in [reminders] like [save], in one write.
  Future<Result<void>> saveAll(Iterable<Reminder> reminders);

  /// Removes the reminder with [id]. Removing an unknown id is not an error.
  Future<Result<void>> delete(String id);

  /// Fires after the stored reminders change.
  Stream<void> get changes;
}
