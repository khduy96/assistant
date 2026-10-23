import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../repositories/p2p_settings_repository.dart';

/// Forgets a device added by IP, by its saved `host:port` entry, and yields
/// the new settings.
class RemoveManualPeer implements UseCase<P2pSettings, String> {
  RemoveManualPeer(this._settings);

  final P2pSettingsRepository _settings;

  @override
  Future<Result<P2pSettings>> call(String entry) async {
    final P2pSettings current;
    switch (await _settings.load()) {
      case Ok(:final value):
        current = value;
      case Err(:final failure):
        return Err(failure);
    }
    final next = current.copyWith(
      manualPeers: [
        for (final e in current.manualPeers)
          if (e != entry) e,
      ],
    );
    return switch (await _settings.save(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
