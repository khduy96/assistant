import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/time_of_day.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/reminder_draft.dart';
import '../entities/todo.dart';

/// What [DraftReminderFromTodo] takes: the todo, and true for a deadline or
/// false for a plain reminder.
typedef DraftReminderParams = ({Todo todo, bool deadline});

/// Carries an item across into a reminder form: same text, and the due date
/// becomes the ring time. A day with no clock rings at 08:00, an item with no
/// due date rings tomorrow, and a moment already past is pushed to tomorrow so
/// the new entry still has something to count down to. A deadline also
/// alerts 60 minutes ahead.
class DraftReminderFromTodo
    implements UseCase<ReminderDraft, DraftReminderParams> {
  DraftReminderFromTodo(this._clock);

  final Clock _clock;

  /// Ring time when the item has a day but no clock time.
  static final defaultTime = TimeOfDay(hour: 8, minute: 0);

  /// How long before a deadline its early alert rings.
  static const deadlineLeadMinutes = 60;

  @override
  Future<Result<ReminderDraft>> call(DraftReminderParams params) async {
    final todo = params.todo;
    final now = _clock.now();
    final due = todo.dueDate;
    final time = todo.hasDueTime
        ? TimeOfDay(hour: due!.hour, minute: due.minute)
        : defaultTime;
    var day = due ?? now.add(const Duration(days: 1));
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (at.isBefore(now)) day = now.add(const Duration(days: 1));
    return Ok(
      ReminderDraft(
        title: todo.title,
        note: todo.note,
        date: DateTime(day.year, day.month, day.day),
        time: time,
        leadMinutes: params.deadline ? deadlineLeadMinutes : 0,
        isDeadline: params.deadline,
      ),
    );
  }
}
