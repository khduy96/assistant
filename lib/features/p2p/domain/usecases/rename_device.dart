import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../repositories/p2p_settings_repository.dart';
import '../repositories/peer_repository.dart';
import '../repositories/transfer_repository.dart';

/// Renames this device, trimmed, and yields the settings in effect.
///
/// A blank name or the current one changes nothing. Otherwise the new name is
/// saved, used from now on by both discovery and transfers, and announced at
/// once so the other devices update their list without waiting.
class RenameDevice implements UseCase<P2pSettings, String> {
  RenameDevice(this._settings, this._transfers, this._peers);

  final P2pSettingsRepository _settings;
  final TransferRepository _transfers;
  final PeerRepository _peers;

  @override
  Future<Result<P2pSettings>> call(String name) async {
    final P2pSettings current;
    switch (await _settings.load()) {
      case Ok(:final value):
        current = value;
      case Err(:final failure):
        return Err(failure);
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == current.deviceName) return Ok(current);

    final next = current.copyWith(deviceName: trimmed);
    if (await _settings.save(next) case Err(:final failure)) {
      return Err(failure);
    }
    if (await _transfers.updateSettings(next) case Err(:final failure)) {
      return Err(failure);
    }
    if (await _peers.updateSettings(next) case Err(:final failure)) {
      return Err(failure);
    }
    return switch (await _peers.announce()) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
