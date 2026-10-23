enum SyncState { idle, running, ok, error, notConfigured }

/// Outcome of a sync cycle, or where the sync stands between cycles.
class SyncStatus {
  const SyncStatus({
    this.state = SyncState.notConfigured,
    this.message,
    this.lastSyncAt,
    this.pushed = 0,
    this.pulled = 0,
    this.monthRequests,
  });

  final SyncState state;
  final String? message;
  final DateTime? lastSyncAt;
  final int pushed;
  final int pulled;

  /// Back4App requests this device has made in the current calendar month.
  final int? monthRequests;

  bool get isRunning => state == SyncState.running;

  SyncStatus withMonthRequests(int? value) => SyncStatus(
    state: state,
    message: message,
    lastSyncAt: lastSyncAt,
    pushed: pushed,
    pulled: pulled,
    monthRequests: value,
  );
}
