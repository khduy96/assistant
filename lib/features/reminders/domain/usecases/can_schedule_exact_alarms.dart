import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// Whether OS alarms may ring at the exact minute.
class CanScheduleExactAlarms implements UseCase<bool, NoParams> {
  CanScheduleExactAlarms(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<bool>> call(NoParams params) =>
      _scheduler.canScheduleExactAlarms();
}
