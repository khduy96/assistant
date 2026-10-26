import '../../../../core/domain/time_of_day.dart';
import '../entities/reminder.dart';

/// One moment a reminder rings: [at] is when it rings, [eventAt] when the
/// event itself happens (later than [at] for a lead alert), and [isLead] tells
/// the "remind me N minutes before" alert apart from the event.
typedef AlertTime = ({DateTime at, DateTime eventAt, bool isLead});

/// Works out when a [Reminder] rings. Nothing here reads the clock: whatever
/// depends on the current time takes it as `now`.
abstract final class ScheduleCalculator {
  /// Time left until the deadline at [now]; negative once it has passed.
  static Duration timeLeft(Reminder r, DateTime now) =>
      r.deadlineAt.difference(now);

  /// How much of the countdown has elapsed at [now], 0..1, for the progress
  /// bar.
  static double elapsedFraction(Reminder r, DateTime now) {
    final total = r.deadlineAt.difference(r.createdAt).inSeconds;
    if (total <= 0) return 1;
    final gone = now.difference(r.createdAt).inSeconds;
    return (gone / total).clamp(0.0, 1.0);
  }

  static DateTime _at(DateTime day, TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  /// Every time [r] rings on [day], in ascending order.
  static Iterable<DateTime> _seriesOn(Reminder r, DateTime day) sync* {
    var moment = _at(day, r.time);
    yield moment;
    final end = r.endTime;
    if (r.repeatEveryMinutes <= 0 || end == null) return;
    final last = _at(day, end);
    while (true) {
      moment = moment.add(Duration(minutes: r.repeatEveryMinutes));
      if (moment.isAfter(last)) return;
      yield moment;
    }
  }

  /// Occurrences of the event itself (not counting lead alerts) after [from].
  static Iterable<DateTime> _occurrencesAfter(Reminder r, DateTime from) sync* {
    switch (r.repeat) {
      case RepeatRule.once:
        yield* _seriesOn(r, r.date).where((d) => d.isAfter(from));
      case RepeatRule.daily:
        for (var i = 0; i <= 2; i++) {
          final day = DateTime(from.year, from.month, from.day + i);
          yield* _seriesOn(r, day).where((d) => d.isAfter(from));
        }
      case RepeatRule.weekly:
        if (r.weekdays.isEmpty) return;
        for (var i = 0; i <= 14; i++) {
          final day = DateTime(from.year, from.month, from.day + i);
          if (!r.weekdays.contains(day.weekday)) continue;
          yield* _seriesOn(r, day).where((d) => d.isAfter(from));
        }
    }
  }

  /// Next moment [r] should ring after [from], lead alert included; null when
  /// it is switched off or has nothing left to ring.
  ///
  /// [now] only matters while the reminder is snoozed: the snoozed alert's
  /// event is the next occurrence after [now]. It defaults to [from].
  static AlertTime? nextAlertInfoAfter(
    Reminder r,
    DateTime from, {
    DateTime? now,
  }) {
    if (!r.enabled) return null;
    final snoozed = r.snoozedUntil;
    if (snoozed != null && snoozed.isAfter(from)) {
      return (
        at: snoozed,
        eventAt: nextOccurrence(r, now ?? from) ?? snoozed,
        isLead: false,
      );
    }

    // Look a little further back so a lead alert whose event is still ahead
    // is not skipped.
    final scanFrom = from.subtract(Duration(minutes: r.leadMinutes));
    for (final occ in _occurrencesAfter(r, scanFrom)) {
      if (r.leadMinutes > 0) {
        final lead = occ.subtract(Duration(minutes: r.leadMinutes));
        if (lead.isAfter(from)) return (at: lead, eventAt: occ, isLead: true);
      }
      if (occ.isAfter(from)) return (at: occ, eventAt: occ, isLead: false);
    }
    return null;
  }

  /// When [r] next rings after [from]; see [nextAlertInfoAfter].
  static DateTime? nextAlertAfter(Reminder r, DateTime from, {DateTime? now}) =>
      nextAlertInfoAfter(r, from, now: now)?.at;

  /// The next [count] alerts of [r] after [from], used to fill the Android
  /// alarm schedule (the OS, not a Dart timer, rings while the app is
  /// closed). [from] is also taken as the current time.
  static List<AlertTime> upcomingAlerts(
    Reminder r,
    int count, {
    required DateTime from,
  }) {
    final alerts = <AlertTime>[];
    var cursor = from;
    for (var i = 0; i < count; i++) {
      final next = nextAlertInfoAfter(r, cursor, now: from);
      if (next == null) break;
      alerts.add(next);
      cursor = next.at;
    }
    return alerts;
  }

  /// The alert [r] is waiting on at [now], honouring the watermark. May be in
  /// the past when the app was closed while the alert came due.
  static DateTime? nextAlert(Reminder r, DateTime now) => nextAlertAfter(
    r,
    r.firedUpTo ?? now.subtract(const Duration(seconds: 1)),
    now: now,
  );

  /// The next occurrence of the event itself after [now], used for the
  /// countdown in the UI.
  static DateTime? nextOccurrence(Reminder r, DateTime now) {
    for (final occ in _occurrencesAfter(r, now)) {
      return occ;
    }
    return null;
  }

  /// True when a one-off reminder has no ring left after [now].
  static bool isExpired(Reminder r, DateTime now) =>
      r.repeat == RepeatRule.once && _occurrencesAfter(r, now).isEmpty;
}
