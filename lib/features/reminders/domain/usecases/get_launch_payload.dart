import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// The payload of the OS alarm that opened the app, or null when something
/// else did.
class GetLaunchPayload implements UseCase<String?, NoParams> {
  GetLaunchPayload(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<String?>> call(NoParams params) => _scheduler.launchPayload();
}
