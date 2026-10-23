import '../../../../core/domain/clock.dart';
import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/pending_alert.dart';
import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';
import '../services/reminder_ordering.dart';
import '../services/schedule_calculator.dart';

/// What [GetDueAlerts] yields: the alerts to add to the queue, in list order,
/// and the failure of saving the moved watermarks, if saving failed.
typedef DueAlerts = ({List<PendingAlert> alerts, Failure? saveFailure});

/// Finds the alerts that have come due since each reminder's watermark, for
/// the app's own ticker (desktop). Takes the alerts already waiting.
///
/// Each alert that comes due moves its reminder's watermark (`firedUpTo`) up
/// to it and drops the snooze, so it is raised exactly once. A reminder with
/// an alert waiting is left alone until that alert is closed. An alert missed
/// by more than [catchUpWindow] (app closed, machine asleep) is skipped
/// instead of ringing long after the fact, but its watermark still moves.
///
/// The moved watermarks are saved in one write. If that fails the alerts are
/// still returned, so the alarm rings anyway, and the failure is reported in
/// the `saveFailure` of [DueAlerts].
class GetDueAlerts implements UseCase<DueAlerts, List<PendingAlert>> {
  GetDueAlerts(this._repo, this._clock);

  final ReminderRepository _repo;
  final Clock _clock;

  /// How late an alert may still ring.
  static const catchUpWindow = Duration(minutes: 30);

  @override
  Future<Result<DueAlerts>> call(List<PendingAlert> queued) async {
    final List<Reminder> all;
    switch (await _repo.getAll()) {
      case Ok(:final value):
        all = value;
      case Err(:final failure):
        return Err(failure);
    }

    final now = _clock.now();
    final waiting = {for (final a in queued) a.reminder.id};
    final changed = <Reminder>[];
    final alerts = <PendingAlert>[];

    for (final r in ReminderOrdering.sorted(all, now)) {
      if (waiting.contains(r.id)) continue;
      final info = ScheduleCalculator.nextAlertInfoAfter(
        r,
        r.firedUpTo ?? now.subtract(const Duration(seconds: 1)),
        now: now,
      );
      if (info == null || info.at.isAfter(now)) continue;

      final updated = r.copyWith(firedUpTo: info.at, snoozedUntil: null);
      changed.add(updated);

      if (now.difference(info.at) > catchUpWindow) continue; // too stale
      alerts.add(
        PendingAlert(
          reminder: updated,
          at: info.at,
          eventAt: info.eventAt,
          isLead: info.isLead,
        ),
      );
    }

    Failure? saveFailure;
    if (changed.isNotEmpty) {
      saveFailure = (await _repo.saveAll(changed)).failureOrNull;
    }
    return Ok((alerts: alerts, saveFailure: saveFailure));
  }
}
