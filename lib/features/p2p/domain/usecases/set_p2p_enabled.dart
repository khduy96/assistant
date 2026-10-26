import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../repositories/p2p_settings_repository.dart';

/// Saves whether file transfer is on, and yields the new settings.
///
/// Only the choice is saved: turning the service on or off is `StartP2p`'s
/// and `StopP2p`'s job, called next.
class SetP2pEnabled implements UseCase<P2pSettings, bool> {
  SetP2pEnabled(this._settings);

  final P2pSettingsRepository _settings;

  @override
  Future<Result<P2pSettings>> call(bool enabled) async {
    final P2pSettings current;
    switch (await _settings.load()) {
      case Ok(:final value):
        current = value;
      case Err(:final failure):
        return Err(failure);
    }
    final next = current.copyWith(enabled: enabled);
    return switch (await _settings.save(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
