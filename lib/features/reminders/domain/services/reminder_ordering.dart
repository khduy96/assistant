import '../entities/reminder.dart';
import 'schedule_calculator.dart';

/// The order reminders are listed in: switched-on ones first, then by the
/// next occurrence of the event (soonest first, none left last), then by
/// title.
abstract final class ReminderOrdering {
  /// [reminders] as a new list in display order, as of [now].
  static List<Reminder> sorted(Iterable<Reminder> reminders, DateTime now) {
    final list = reminders.toList();
    final next = {
      for (final r in list) r.id: ScheduleCalculator.nextOccurrence(r, now),
    };
    list.sort((a, b) {
      final an = next[a.id], bn = next[b.id];
      if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
      if (an == null && bn == null) return a.title.compareTo(b.title);
      if (an == null) return 1;
      if (bn == null) return -1;
      return an.compareTo(bn);
    });
    return list;
  }

  /// The deadlines among [reminders] as a new list: the nearest first, and
  /// the ones already past at [now] sunk to the bottom.
  static List<Reminder> deadlines(Iterable<Reminder> reminders, DateTime now) =>
      reminders.where((r) => r.isDeadline).toList()..sort((a, b) {
        final ap = ScheduleCalculator.timeLeft(a, now).isNegative;
        final bp = ScheduleCalculator.timeLeft(b, now).isNegative;
        if (ap != bp) return ap ? 1 : -1;
        return a.deadlineAt.compareTo(b.deadlineAt);
      });

  /// The soonest moment any of [reminders] rings after [now]; null when none
  /// is switched on with a ring left.
  static DateTime? nextAlertAt(Iterable<Reminder> reminders, DateTime now) {
    DateTime? soonest;
    for (final r in reminders) {
      final next = ScheduleCalculator.nextAlertAfter(r, now);
      if (next != null && (soonest == null || next.isBefore(soonest))) {
        soonest = next;
      }
    }
    return soonest;
  }

  /// The deadline among [reminders] that falls due soonest without having
  /// passed at [now], switched on or not; null when there is none.
  static Reminder? nearestDeadline(Iterable<Reminder> reminders, DateTime now) {
    Reminder? nearest;
    for (final r in reminders) {
      if (!r.isDeadline || ScheduleCalculator.timeLeft(r, now).isNegative) {
        continue;
      }
      if (nearest == null || r.deadlineAt.isBefore(nearest.deadlineAt)) {
        nearest = r;
      }
    }
    return nearest;
  }
}
