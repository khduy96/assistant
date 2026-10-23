/// How urgent a todo is; drives the sort order and the colour of its tag.
/// The data layer stores it by name.
enum TodoPriority { low, normal, high }

/// Marks a [Todo.copyWith] argument that was not passed, so an explicit null
/// can clear a field.
const Object _unset = Object();

/// One item on the todo list. Unlike a reminder it never rings — it is just a
/// thing to tick off, optionally with a day it should be done by.
///
/// Immutable: edits go through [copyWith]. Sync state (the server id, whether
/// the local copy is ahead) lives in the data layer, not here.
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.note = '',
    this.done = false,
    this.priority = TodoPriority.normal,
    this.dueDate,
    this.completedAt,
    this.reminderId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String note;
  final bool done;
  final TodoPriority priority;

  /// When the item is due. A time of exactly 00:00 means "sometime that day"
  /// — see [hasDueTime] — so items saved before the clock existed still read
  /// the same way.
  final DateTime? dueDate;

  /// When the item was ticked off, so finished work can be shown in order.
  final DateTime? completedAt;

  /// Id of the reminder this item was turned into, null while it is only a
  /// checklist line. The reminder keeps its own copy of the text; the link
  /// exists so the list can show the alarm and offer to open it instead of
  /// creating a second one.
  final String? reminderId;

  final DateTime createdAt;

  /// Bumped on every edit; what the sync uses to settle conflicts.
  final DateTime updatedAt;

  /// True when the deadline carries an explicit clock time rather than just a
  /// day. Midnight is the marker for "no time picked".
  bool get hasDueTime {
    final due = dueDate;
    return due != null && (due.hour != 0 || due.minute != 0);
  }

  /// True when an unfinished item is past its deadline at [now]: past that
  /// minute when a time was picked, otherwise past the whole day.
  bool isOverdue(DateTime now) {
    final due = dueDate;
    if (done || due == null) return false;
    if (hasDueTime) return due.isBefore(now);
    return DateTime(
      due.year,
      due.month,
      due.day,
    ).isBefore(DateTime(now.year, now.month, now.day));
  }

  /// True when an unfinished item is due on the day of [now].
  bool isDueToday(DateTime now) {
    final due = dueDate;
    if (done || due == null) return false;
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }

  /// A copy with the given fields replaced. The id never changes.
  ///
  /// [dueDate], [completedAt] and [reminderId] can be cleared by passing an
  /// explicit null; leaving them out keeps the current value.
  Todo copyWith({
    String? title,
    String? note,
    bool? done,
    TodoPriority? priority,
    Object? dueDate = _unset,
    Object? completedAt = _unset,
    Object? reminderId = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Todo(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    done: done ?? this.done,
    priority: priority ?? this.priority,
    dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as DateTime?,
    completedAt: identical(completedAt, _unset)
        ? this.completedAt
        : completedAt as DateTime?,
    reminderId: identical(reminderId, _unset)
        ? this.reminderId
        : reminderId as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Todo &&
      other.id == id &&
      other.title == title &&
      other.note == note &&
      other.done == done &&
      other.priority == priority &&
      other.dueDate == dueDate &&
      other.completedAt == completedAt &&
      other.reminderId == reminderId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    note,
    done,
    priority,
    dueDate,
    completedAt,
    reminderId,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'Todo($id, done: $done, priority: ${priority.name}, due: $dueDate)';
}
