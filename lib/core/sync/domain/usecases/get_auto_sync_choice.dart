import '../../../domain/failure.dart';
import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../sync_preferences.dart';

/// Whether the user turned sync on its own on or off on this device; null
/// when they never chose.
class GetAutoSyncChoice implements UseCase<bool?, NoParams> {
  GetAutoSyncChoice(this._preferences);

  final SyncPreferences _preferences;

  @override
  Future<Result<bool?>> call(NoParams params) async {
    try {
      return Ok(await _preferences.autoSync());
    } catch (e) {
      return Err(
        StorageFailure('Could not read the auto-sync choice', cause: e),
      );
    }
  }
}
