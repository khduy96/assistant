/// `p2p.json` as stored: `{deviceId, deviceName, autoAccept, enabled,
/// saveDir?, manualPeers}`. The only place that knows these keys.
class P2pSettingsModel {
  const P2pSettingsModel({
    required this.deviceId,
    required this.deviceName,
    required this.autoAccept,
    required this.enabled,
    required this.saveDir,
    required this.manualPeers,
  });

  final String deviceId;
  final String deviceName;
  final bool autoAccept;
  final bool enabled;
  final String? saveDir;
  final List<String> manualPeers;

  /// Reads a saved object. A key that is missing takes its default:
  /// [newId] and [defaultName] are only called for a missing id or name,
  /// auto-accept is off, transfer is on, no folder and no manual devices.
  ///
  /// Throws a [TypeError] when a key holds a value of the wrong type.
  factory P2pSettingsModel.fromJson(
    Map<String, dynamic> json, {
    required String Function() newId,
    required String Function() defaultName,
  }) => P2pSettingsModel(
    deviceId: json['deviceId'] as String? ?? newId(),
    deviceName: json['deviceName'] as String? ?? defaultName(),
    autoAccept: json['autoAccept'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? true,
    saveDir: json['saveDir'] as String?,
    manualPeers:
        (json['manualPeers'] as List?)?.cast<String>().toList() ?? <String>[],
  );

  /// The keys in the order they have always been written. `saveDir` is left
  /// out when there is none.
  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'autoAccept': autoAccept,
    'enabled': enabled,
    if (saveDir != null) 'saveDir': saveDir,
    'manualPeers': manualPeers,
  };
}
