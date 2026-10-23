import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../ports/alarm_ringer.dart';

/// Starts looping the app's own alarm tone (desktop), when the first alert
/// shows.
class StartAlarmSound implements UseCase<void, NoParams> {
  StartAlarmSound(this._ringer);

  final AlarmRinger _ringer;

  @override
  Future<Result<void>> call(NoParams params) async {
    await _ringer.start();
    return const Ok(null);
  }
}
