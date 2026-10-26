import '../../domain/entities/p2p_settings.dart';
import '../models/p2p_settings_model.dart';

/// Converts between the stored [P2pSettingsModel] and the domain
/// [P2pSettings].
abstract final class P2pSettingsMapper {
  static P2pSettings toEntity(P2pSettingsModel model) => P2pSettings(
    deviceId: model.deviceId,
    deviceName: model.deviceName,
    autoAccept: model.autoAccept,
    enabled: model.enabled,
    saveDir: model.saveDir,
    manualPeers: model.manualPeers,
  );

  static P2pSettingsModel toModel(P2pSettings settings) => P2pSettingsModel(
    deviceId: settings.deviceId,
    deviceName: settings.deviceName,
    autoAccept: settings.autoAccept,
    enabled: settings.enabled,
    saveDir: settings.saveDir,
    manualPeers: settings.manualPeers.toList(),
  );
}
