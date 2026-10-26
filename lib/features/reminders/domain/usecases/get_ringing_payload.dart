import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// The payload of the OS alarm ringing right now, or null when none is.
class GetRingingPayload implements UseCase<String?, NoParams> {
  GetRingingPayload(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<String?>> call(NoParams params) => _scheduler.ringingPayload();
}
