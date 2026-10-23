import '../../../../core/domain/time_of_day.dart';

/// How often a reminder repeats across days. The data layer stores it by
/// name; the Vietnamese label lives in presentation.
enum RepeatRule { once, daily, weekly }

/// Marks a [Reminder.copyWith] argument that was not passed, so an explicit
/// null can clear a field.
const Object _unset = Object();

/// One scheduled alert. [date] only matters for [RepeatRule.once]; repeating
/// reminders use [time] plus [weekdays].
///
/// Within a single day the reminder can also repeat: starting at [time], every
/// [repeatEveryMinutes], stopping after [endTime] (e.g. 10:00 rồi mỗi 2 giờ
/// đến 22:00).
///
/// Immutable: edits go through [copyWith]. When it rings is worked out by
/// `ScheduleCalculator`, which takes the current time as an argument.
class Reminder {
  Reminder({
    required this.id,
    required this.title,
    this.note = '',
    this.enabled = true,
    this.repeat = RepeatRule.once,
    required this.date,
    required this.time,
    Set<int> weekdays = const {},
    this.repeatEveryMinutes = 0,
    this.endTime,
    this.leadMinutes = 0,
    this.snoozeMinutes = 5,
    this.snoozedUntil,
    this.firedUpTo,
    this.isDeadline = false,
    required this.createdAt,
  }) : weekdays = Set.unmodifiable(weekdays);

  final String id;
  final String title;
  final String note;
  final bool enabled;
  final RepeatRule repeat;

  /// The day of a one-off reminder or deadline; [time] gives the clock time.
  final DateTime date;

  final TimeOfDay time;

  /// Days a weekly reminder rings, as `DateTime.monday` .. `DateTime.sunday`.
  /// Unmodifiable.
  final Set<int> weekdays;

  /// Gap between in-day repeats (0 = ring once a day).
  final int repeatEveryMinutes;

  /// Last moment of the day an in-day repeat may ring.
  final TimeOfDay? endTime;

  /// Extra alert this many minutes before each occurrence (0 = off).
  final int leadMinutes;
  final int snoozeMinutes;

  /// Set while the user has snoozed an alert; it rings again at this moment.
  final DateTime? snoozedUntil;

  /// Watermark: alerts at or before this instant have already been handled.
  final DateTime? firedUpTo;

  /// A deadline is a single fixed moment the user counts down to. It rings
  /// like any other reminder, but the app shows a live countdown for it and
  /// never repeats it.
  final bool isDeadline;

  /// When the entry was created — the start of the countdown bar.
  final DateTime createdAt;

  /// The moment a deadline falls due: [date] at [time].
  DateTime get deadlineAt =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  /// True when it rings more than once a day.
  bool get repeatsWithinDay => repeatEveryMinutes > 0 && endTime != null;

  /// A copy with the given fields replaced. The id never changes.
  ///
  /// [endTime], [snoozedUntil] and [firedUpTo] can be cleared by passing an
  /// explicit null; leaving them out keeps the current value.
  Reminder copyWith({
    String? title,
    String? note,
    bool? enabled,
    RepeatRule? repeat,
    DateTime? date,
    TimeOfDay? time,
    Set<int>? weekdays,
    int? repeatEveryMinutes,
    Object? endTime = _unset,
    int? leadMinutes,
    int? snoozeMinutes,
    Object? snoozedUntil = _unset,
    Object? firedUpTo = _unset,
    bool? isDeadline,
    DateTime? createdAt,
  }) => Reminder(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    enabled: enabled ?? this.enabled,
    repeat: repeat ?? this.repeat,
    date: date ?? this.date,
    time: time ?? this.time,
    weekdays: weekdays ?? this.weekdays,
    repeatEveryMinutes: repeatEveryMinutes ?? this.repeatEveryMinutes,
    endTime: identical(endTime, _unset) ? this.endTime : endTime as TimeOfDay?,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    snoozedUntil: identical(snoozedUntil, _unset)
        ? this.snoozedUntil
        : snoozedUntil as DateTime?,
    firedUpTo: identical(firedUpTo, _unset)
        ? this.firedUpTo
        : firedUpTo as DateTime?,
    isDeadline: isDeadline ?? this.isDeadline,
    createdAt: createdAt ?? this.createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.title == title &&
      other.note == note &&
      other.enabled == enabled &&
      other.repeat == repeat &&
      other.date == date &&
      other.time == time &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.repeatEveryMinutes == repeatEveryMinutes &&
      other.endTime == endTime &&
      other.leadMinutes == leadMinutes &&
      other.snoozeMinutes == snoozeMinutes &&
      other.snoozedUntil == snoozedUntil &&
      other.firedUpTo == firedUpTo &&
      other.isDeadline == isDeadline &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    note,
    enabled,
    repeat,
    date,
    time,
    Object.hashAllUnordered(weekdays),
    repeatEveryMinutes,
    endTime,
    leadMinutes,
    snoozeMinutes,
    snoozedUntil,
    firedUpTo,
    isDeadline,
    createdAt,
  );

  @override
  String toString() =>
      'Reminder($id, ${repeat.name} at $time, enabled: $enabled, '
      'deadline: $isDeadline, firedUpTo: $firedUpTo)';
}
