/// Where the sync engine keeps its own state between cycles: cursors, change
/// counters, the request tally. It also holds per-device user choices such
/// as `sync_auto` (written by `StateStoreSyncPreferences`), so resetting the
/// engine's keys must leave those alone.
///
/// A flat string-to-string store. The keys are already on disk on devices in
/// use, so implementations store them exactly as given.
abstract interface class SyncStateStore {
  /// Every stored entry.
  Future<Map<String, String>> readAll();

  /// The value stored under [key], or null when there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing what was there.
  Future<void> write(String key, String value);
}
