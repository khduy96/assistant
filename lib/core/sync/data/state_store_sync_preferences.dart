import '../domain/sync_preferences.dart';
import '../domain/sync_state_store.dart';

/// [SyncPreferences] kept in the [SyncStateStore], next to the engine's own
/// keys.
class StateStoreSyncPreferences implements SyncPreferences {
  StateStoreSyncPreferences(this._store);

  /// The only key this class reads or writes: '1' on, '0' off.
  static const String autoSyncKey = 'sync_auto';

  final SyncStateStore _store;

  @override
  Future<bool?> autoSync() async => switch (await _store.read(autoSyncKey)) {
    '1' => true,
    '0' => false,
    _ => null,
  };

  @override
  Future<void> setAutoSync(bool enabled) =>
      _store.write(autoSyncKey, enabled ? '1' : '0');
}
