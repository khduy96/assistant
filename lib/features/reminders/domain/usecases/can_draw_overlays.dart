import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// Whether the alarm may take over the screen while the phone is in use.
class CanDrawOverlays implements UseCase<bool, NoParams> {
  CanDrawOverlays(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<bool>> call(NoParams params) => _scheduler.canDrawOverlays();
}
