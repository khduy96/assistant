import 'package:flutter/material.dart';

/// How often a reminder repeats across days.
enum RepeatRule { once, daily, weekly }

extension RepeatRuleLabel on RepeatRule {
  String get label => switch (this) {
        RepeatRule.once => 'Một lần',
        RepeatRule.daily => 'Hàng ngày',
        RepeatRule.weekly => 'Hàng tuần',
      };
}

const weekdayShortNames = {
  DateTime.monday: 'T2',
  DateTime.tuesday: 'T3',
  DateTime.wednesday: 'T4',
  DateTime.thursday: 'T5',
  DateTime.friday: 'T6',
  DateTime.saturday: 'T7',
  DateTime.sunday: 'CN',
};

/// One scheduled alert. [date] only matters for [RepeatRule.once]; repeating
/// reminders use [time] plus [weekdays].
///
/// Within a single day the reminder can also repeat: starting at [time], every
/// [repeatEveryMinutes], stopping after [endTime] (e.g. 10:00 rồi mỗi 2 giờ
/// đến 22:00).
class Reminder {
  Reminder({
    required this.id,
    required this.title,
    this.note = '',
    this.enabled = true,
    this.repeat = RepeatRule.once,
    required this.date,
    required this.time,
    Set<int>? weekdays,
    this.repeatEveryMinutes = 0,
    this.endTime,
    this.leadMinutes = 0,
    this.snoozeMinutes = 5,
    this.snoozedUntil,
    this.firedUpTo,
    this.isDeadline = false,
    DateTime? createdAt,
  })  : weekdays = weekdays ?? {},
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  String note;
  bool enabled;
  RepeatRule repeat;
  DateTime date;
  TimeOfDay time;
  Set<int> weekdays;

  /// Gap between in-day repeats (0 = ring once a day).
  int repeatEveryMinutes;

  /// Last moment of the day an in-day repeat may ring.
  TimeOfDay? endTime;

  /// Extra alert this many minutes before each occurrence (0 = off).
  int leadMinutes;
  int snoozeMinutes;

  /// Set while the user has snoozed an alert; it rings again at this moment.
  DateTime? snoozedUntil;

  /// Watermark: alerts at or before this instant have already been handled.
  DateTime? firedUpTo;

  /// A deadline is a single fixed moment the user counts down to. It rings
  /// like any other reminder, but the app shows a live countdown for it and
  /// never repeats it.
  bool isDeadline;

  /// When the entry was created — the start of the countdown bar.
  final DateTime createdAt;

  /// The moment a deadline falls due.
  DateTime get deadlineAt => _at(date, time);

  /// Time left until the deadline; negative once it has passed.
  Duration get timeLeft => deadlineAt.difference(DateTime.now());

  /// How much of the countdown has elapsed, 0..1, for the progress bar.
  double get elapsedFraction {
    final total = deadlineAt.difference(createdAt).inSeconds;
    if (total <= 0) return 1;
    final gone = DateTime.now().difference(createdAt).inSeconds;
    return (gone / total).clamp(0.0, 1.0);
  }

  bool get repeatsWithinDay => repeatEveryMinutes > 0 && endTime != null;

  DateTime _at(DateTime day, TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  /// Every time this reminder rings on [day], in ascending order.
  Iterable<DateTime> _seriesOn(DateTime day) sync* {
    var moment = _at(day, time);
    yield moment;
    final end = endTime;
    if (repeatEveryMinutes <= 0 || end == null) return;
    final last = _at(day, end);
    while (true) {
      moment = moment.add(Duration(minutes: repeatEveryMinutes));
      if (moment.isAfter(last)) return;
      yield moment;
    }
  }

  /// Occurrences of the event itself (not counting lead alerts) after [from].
  Iterable<DateTime> _occurrencesAfter(DateTime from) sync* {
    switch (repeat) {
      case RepeatRule.once:
        yield* _seriesOn(date).where((d) => d.isAfter(from));
      case RepeatRule.daily:
        for (var i = 0; i <= 2; i++) {
          final day = DateTime(from.year, from.month, from.day + i);
          yield* _seriesOn(day).where((d) => d.isAfter(from));
        }
      case RepeatRule.weekly:
        if (weekdays.isEmpty) return;
        for (var i = 0; i <= 14; i++) {
          final day = DateTime(from.year, from.month, from.day + i);
          if (!weekdays.contains(day.weekday)) continue;
          yield* _seriesOn(day).where((d) => d.isAfter(from));
        }
    }
  }

  /// Next moment this reminder should ring after [from], lead alert included.
  ({DateTime at, DateTime eventAt, bool isLead})? nextAlertInfoAfter(DateTime from) {
    if (!enabled) return null;
    final snoozed = snoozedUntil;
    if (snoozed != null && snoozed.isAfter(from)) {
      return (at: snoozed, eventAt: nextOccurrence ?? snoozed, isLead: false);
    }

    // Look a little further back so a lead alert whose event is still ahead
    // is not skipped.
    final scanFrom = from.subtract(Duration(minutes: leadMinutes));
    for (final occ in _occurrencesAfter(scanFrom)) {
      if (leadMinutes > 0) {
        final lead = occ.subtract(Duration(minutes: leadMinutes));
        if (lead.isAfter(from)) return (at: lead, eventAt: occ, isLead: true);
      }
      if (occ.isAfter(from)) return (at: occ, eventAt: occ, isLead: false);
    }
    return null;
  }

  DateTime? nextAlertAfter(DateTime from) => nextAlertInfoAfter(from)?.at;

  /// The next [count] alerts from [from], used to fill the Android alarm
  /// schedule (the OS, not a Dart timer, rings while the app is closed).
  List<({DateTime at, DateTime eventAt, bool isLead})> upcomingAlerts(
    int count, {
    DateTime? from,
  }) {
    final alerts = <({DateTime at, DateTime eventAt, bool isLead})>[];
    var cursor = from ?? DateTime.now();
    for (var i = 0; i < count; i++) {
      final next = nextAlertInfoAfter(cursor);
      if (next == null) break;
      alerts.add(next);
      cursor = next.at;
    }
    return alerts;
  }

  /// The alert this reminder is currently waiting on, honouring the watermark.
  /// May be in the past when the app was closed while the alert came due.
  DateTime? get nextAlert => nextAlertAfter(
      firedUpTo ?? DateTime.now().subtract(const Duration(seconds: 1)));

  /// The next occurrence of the event itself, used for the countdown in the UI.
  DateTime? get nextOccurrence {
    for (final occ in _occurrencesAfter(DateTime.now())) {
      return occ;
    }
    return null;
  }

  /// True when a one-off reminder has no ring left.
  bool get isExpired =>
      repeat == RepeatRule.once && _occurrencesAfter(DateTime.now()).isEmpty;

  Reminder copy() => Reminder.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'enabled': enabled,
        'repeat': repeat.name,
        'date': date.toIso8601String(),
        'hour': time.hour,
        'minute': time.minute,
        'weekdays': weekdays.toList()..sort(),
        'repeatEveryMinutes': repeatEveryMinutes,
        'endHour': endTime?.hour,
        'endMinute': endTime?.minute,
        'leadMinutes': leadMinutes,
        'snoozeMinutes': snoozeMinutes,
        'snoozedUntil': snoozedUntil?.toIso8601String(),
        'firedUpTo': firedUpTo?.toIso8601String(),
        'isDeadline': isDeadline,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, dynamic> j) {
    final endHour = j['endHour'] as int?;
    return Reminder(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      note: j['note'] as String? ?? '',
      enabled: j['enabled'] as bool? ?? true,
      repeat: RepeatRule.values.firstWhere(
        (m) => m.name == j['repeat'],
        orElse: () => RepeatRule.once,
      ),
      date: DateTime.parse(j['date'] as String),
      time: TimeOfDay(hour: j['hour'] as int? ?? 8, minute: j['minute'] as int? ?? 0),
      weekdays: ((j['weekdays'] as List?) ?? const []).map((e) => e as int).toSet(),
      repeatEveryMinutes: j['repeatEveryMinutes'] as int? ?? 0,
      endTime: endHour == null
          ? null
          : TimeOfDay(hour: endHour, minute: j['endMinute'] as int? ?? 0),
      leadMinutes: j['leadMinutes'] as int? ?? 0,
      snoozeMinutes: j['snoozeMinutes'] as int? ?? 5,
      snoozedUntil: j['snoozedUntil'] == null ? null : DateTime.parse(j['snoozedUntil'] as String),
      firedUpTo: j['firedUpTo'] == null ? null : DateTime.parse(j['firedUpTo'] as String),
      isDeadline: j['isDeadline'] as bool? ?? false,
      createdAt: j['createdAt'] == null
          ? null
          : DateTime.tryParse(j['createdAt'] as String),
    );
  }
}
