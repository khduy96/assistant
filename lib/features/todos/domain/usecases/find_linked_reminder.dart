import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/linked_reminder.dart';
import '../entities/todo.dart';
import '../repositories/linked_reminder_repository.dart';

/// The reminder a todo was turned into, or null when it never was — or when
/// that reminder has since been deleted, which reads the same here.
class FindLinkedReminder implements UseCase<LinkedReminder?, Todo> {
  FindLinkedReminder(this._reminders);

  final LinkedReminderRepository _reminders;

  @override
  Future<Result<LinkedReminder?>> call(Todo todo) async {
    final id = todo.reminderId;
    if (id == null) return const Ok(null);
    return _reminders.find(id);
  }
}
