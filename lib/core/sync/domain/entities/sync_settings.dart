/// What the rest of the app needs to know about the sync setup, without the
/// keys or the server address.
class SyncSettings {
  const SyncSettings({
    required this.isConfigured,
    required this.autoSync,
    required this.space,
  });

  /// True once there is enough to talk to the server.
  final bool isConfigured;

  /// False when the build turned automatic cycles off (`PARSE_AUTO_SYNC=0`);
  /// a manual sync still runs.
  final bool autoSync;

  /// Namespace shared by the devices that sync together.
  final String space;
}
