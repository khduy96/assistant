import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// Rings an OS alarm right now so the user can check the sound.
class TestAlarmRing implements UseCase<void, NoParams> {
  TestAlarmRing(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<void>> call(NoParams params) => _scheduler.testRing();
}
