import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/linked_reminder_repository.dart';

/// Deletes the reminder with the given id. The todo keeps its link until the
/// caller clears it with `LinkReminder`.
class RemoveLinkedReminder implements UseCase<void, String> {
  RemoveLinkedReminder(this._reminders);

  final LinkedReminderRepository _reminders;

  @override
  Future<Result<void>> call(String reminderId) => _reminders.remove(reminderId);
}
