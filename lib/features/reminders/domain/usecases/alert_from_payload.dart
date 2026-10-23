import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/alarm_payload.dart';
import '../entities/pending_alert.dart';
import '../repositories/reminder_repository.dart';

/// What [AlertFromPayload] takes: an OS alarm payload, and the alerts already
/// waiting to be shown.
typedef AlertFromPayloadParams = ({String payload, List<PendingAlert> queued});

/// Rebuilds the alert an OS alarm carries, so the app can show it when the
/// alarm opens it or rings while it is in front. Yields null when the payload
/// does not parse, its reminder is gone, or that reminder already has an
/// alert waiting. Nothing is stored.
class AlertFromPayload
    implements UseCase<PendingAlert?, AlertFromPayloadParams> {
  AlertFromPayload(this._repo);

  final ReminderRepository _repo;

  @override
  Future<Result<PendingAlert?>> call(AlertFromPayloadParams params) async {
    final parsed = parseAlarmPayload(params.payload);
    if (parsed == null) return const Ok(null);
    switch (await _repo.find(parsed.reminderId)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: null):
        return const Ok(null);
      case Ok(value: final r?):
        if (params.queued.any((a) => a.reminder.id == r.id)) {
          return const Ok(null);
        }
        return Ok(
          PendingAlert(
            reminder: r,
            at: parsed.at,
            eventAt: parsed.isLead
                ? parsed.at.add(Duration(minutes: r.leadMinutes))
                : parsed.at,
            isLead: parsed.isLead,
          ),
        );
    }
  }
}
