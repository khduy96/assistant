import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/linked_reminder_repository.dart';

/// A stream that fires whenever reminders change or their countdowns move on,
/// so a listener can look its linked reminders up again.
class WatchLinkedReminders implements UseCase<Stream<void>, NoParams> {
  WatchLinkedReminders(this._reminders);

  final LinkedReminderRepository _reminders;

  @override
  Future<Result<Stream<void>>> call(NoParams params) async =>
      Ok(_reminders.changes);
}
