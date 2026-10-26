import '../../../core/presentation/format.dart';
import '../domain/entities/linked_reminder.dart';
import '../domain/entities/todo.dart';

extension TodoPriorityLabel on TodoPriority {
  String get label => switch (this) {
    TodoPriority.low => 'Thấp',
    TodoPriority.normal => 'Bình thường',
    TodoPriority.high => 'Quan trọng',
  };
}

/// Text of the deadline chip as of [now]: the clock is only shown when one
/// was picked.
String dueLabel(Todo todo, DateTime due, DateTime now) {
  final time = todo.hasDueTime ? ' ${two(due.hour)}:${two(due.minute)}' : '';
  if (todo.isOverdue(now)) return 'Quá hạn ${formatDate(due)}$time';
  if (todo.isDueToday(now)) return todo.hasDueTime ? 'Hôm nay$time' : 'Hôm nay';
  return 'Hạn ${formatDate(due)}$time';
}

/// Text of the alarm chip on a converted item as of [now]: the countdown to
/// its next ring, or why there is not one. Null when the item was never
/// converted.
String? alarmLabel(LinkedReminder? linked, DateTime now) {
  if (linked == null) return null;
  final kind = linked.isDeadline ? 'Deadline' : 'Nhắc';
  if (!linked.enabled) return '$kind · đang tắt';
  final next = linked.nextOccurrence;
  if (next == null) return '$kind · đã qua';
  return '$kind · ${formatCountdown(next.difference(now))}';
}
