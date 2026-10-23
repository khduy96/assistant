import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// Silences the OS alarm that is ringing, e.g. after the alert on screen was
/// turned off or put off.
class StopRinging implements UseCase<void, NoParams> {
  StopRinging(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<void>> call(NoParams params) => _scheduler.stopRinging();
}
