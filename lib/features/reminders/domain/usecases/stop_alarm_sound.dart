import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_ringer.dart';

/// Stops the app's own alarm tone, once no alert is left on screen.
class StopAlarmSound implements UseCase<void, NoParams> {
  StopAlarmSound(this._ringer);

  final AlarmRinger _ringer;

  @override
  Future<Result<void>> call(NoParams params) async {
    await _ringer.stop();
    return const Ok(null);
  }
}
