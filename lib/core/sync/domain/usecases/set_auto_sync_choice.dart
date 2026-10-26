import '../../../domain/failure.dart';
import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../sync_preferences.dart';

/// Stores whether sync runs on its own on this device.
class SetAutoSyncChoice implements UseCase<void, bool> {
  SetAutoSyncChoice(this._preferences);

  final SyncPreferences _preferences;

  @override
  Future<Result<void>> call(bool params) async {
    try {
      await _preferences.setAutoSync(params);
      return const Ok(null);
    } catch (e) {
      return Err(
        StorageFailure('Could not save the auto-sync choice', cause: e),
      );
    }
  }
}
