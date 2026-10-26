import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_scheduler.dart';

/// Opens the "display over other apps" settings screen.
class RequestOverlayPermission implements UseCase<void, NoParams> {
  RequestOverlayPermission(this._scheduler);

  final AlarmScheduler _scheduler;

  @override
  Future<Result<void>> call(NoParams params) =>
      _scheduler.requestOverlayPermission();
}
