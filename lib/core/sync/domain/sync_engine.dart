import 'entities/sync_settings.dart';
import 'entities/sync_status.dart';

/// Two-way sync between the local lists and the server.
abstract interface class SyncEngine {
  /// How this build is set up to sync.
  SyncSettings get settings;

  /// Runs one cycle: push local changes, then pull remote ones.
  ///
  /// [full] pulls every class even when the server says it has not changed.
  /// [auto] marks a cycle no one asked for (a timer, the app coming back),
  /// which keeps to this device's share of the request budget; a manual cycle
  /// never does. [checkRemote] false only pushes, without asking the server
  /// what changed.
  /// Never throws: a failure comes back as [SyncState.error].
  Future<SyncStatus> sync({
    bool full = false,
    bool auto = false,
    bool checkRemote = true,
  });

  /// Whether anything here still waits to go out. Answered locally, without
  /// a request.
  Future<bool> hasLocalChanges();

  /// Requests counted so far this month on this device.
  Future<int> requestsThisMonth();

  /// Fires after any synced list changed on this device, so a push can be
  /// scheduled. Never fires for a change a sync applied.
  Stream<void> get localChanges;
}
