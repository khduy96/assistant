import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// Asks for notifications and the "Alarms & reminders" permission.
class RequestAlarmPermissions implements UseCase<void, NoParams> {
  RequestAlarmPermissions(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<void>> call(NoParams params) => _scheduler.requestPermissions();
}
