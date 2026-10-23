/// Marks a [P2pSettings.copyWith] argument that was not passed, so an explicit
/// null can clear [P2pSettings.saveDir].
const Object _unset = Object();

/// This device's identity on the LAN and the options of file transfer.
///
/// Immutable: edits go through [copyWith] and are kept by the
/// `P2pSettingsRepository`. How they are stored is the data layer's business.
class P2pSettings {
  P2pSettings({
    required this.deviceId,
    required this.deviceName,
    this.autoAccept = false,
    this.enabled = true,
    this.saveDir,
    List<String> manualPeers = const [],
  }) : manualPeers = List.unmodifiable(manualPeers);

  /// Fixed id of this device, made on first run and never changed.
  final String deviceId;
  final String deviceName;

  /// Receive without asking. Off by default: every incoming file has to be
  /// accepted.
  final bool autoAccept;

  /// Whether file transfer is on at all (port open, announcing).
  final bool enabled;

  /// Folder for received files; null means the default folder.
  final String? saveDir;

  /// Devices the user added by IP, as `host:port` (see `normalizeEntry`).
  /// For networks that block broadcasts, where two devices never find each
  /// other on their own. Unmodifiable.
  final List<String> manualPeers;

  /// A copy with the given fields replaced. An explicit null for [saveDir]
  /// goes back to the default folder. The device id never changes.
  P2pSettings copyWith({
    String? deviceName,
    bool? autoAccept,
    bool? enabled,
    Object? saveDir = _unset,
    List<String>? manualPeers,
  }) => P2pSettings(
    deviceId: deviceId,
    deviceName: deviceName ?? this.deviceName,
    autoAccept: autoAccept ?? this.autoAccept,
    enabled: enabled ?? this.enabled,
    saveDir: identical(saveDir, _unset) ? this.saveDir : saveDir as String?,
    manualPeers: manualPeers ?? this.manualPeers,
  );

  @override
  bool operator ==(Object other) =>
      other is P2pSettings &&
      other.deviceId == deviceId &&
      other.deviceName == deviceName &&
      other.autoAccept == autoAccept &&
      other.enabled == enabled &&
      other.saveDir == saveDir &&
      _sameList(other.manualPeers, manualPeers);

  @override
  int get hashCode => Object.hash(
    deviceId,
    deviceName,
    autoAccept,
    enabled,
    saveDir,
    Object.hashAll(manualPeers),
  );

  @override
  String toString() =>
      'P2pSettings($deviceId, $deviceName, autoAccept: $autoAccept, '
      'enabled: $enabled, saveDir: $saveDir, manualPeers: $manualPeers)';

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
