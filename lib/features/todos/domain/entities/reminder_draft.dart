import '../../../../core/domain/time_of_day.dart';

/// The prefilled form for turning a todo into a one-off reminder or deadline.
/// Nothing is stored: the reminder editor opens with it, and the user can
/// still change every field before saving.
class ReminderDraft {
  const ReminderDraft({
    required this.title,
    this.note = '',
    required this.date,
    required this.time,
    this.leadMinutes = 0,
    this.isDeadline = false,
  });

  final String title;
  final String note;

  /// The day it rings, at midnight; [time] gives the clock time.
  final DateTime date;

  final TimeOfDay time;

  /// Extra alert this many minutes before it rings (0 = off).
  final int leadMinutes;

  /// True asks for a deadline, false for a plain reminder.
  final bool isDeadline;

  /// The moment it rings: [date] at [time].
  DateTime get at =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  @override
  bool operator ==(Object other) =>
      other is ReminderDraft &&
      other.title == title &&
      other.note == note &&
      other.date == date &&
      other.time == time &&
      other.leadMinutes == leadMinutes &&
      other.isDeadline == isDeadline;

  @override
  int get hashCode =>
      Object.hash(title, note, date, time, leadMinutes, isDeadline);

  @override
  String toString() =>
      'ReminderDraft($title, at: $at, lead: $leadMinutes, '
      'deadline: $isDeadline)';
}
