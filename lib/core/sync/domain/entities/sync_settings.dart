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

  /// Whether automatic cycles run; a manual sync runs either way.
  ///
  /// From the engine this is the build value (false when
  /// `PARSE_AUTO_SYNC=0`). From SyncController it is the value applied on
  /// this device: the user's choice, or the build value when they never
  /// chose.
  final bool autoSync;

  /// Namespace shared by the devices that sync together.
  final String space;
}
