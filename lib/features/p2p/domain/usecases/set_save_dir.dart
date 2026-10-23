import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../repositories/p2p_settings_repository.dart';
import '../repositories/transfer_repository.dart';

/// Chooses the folder for received files (null: back to the default one),
/// for files that arrive from now on, and yields the new settings.
class SetSaveDir implements UseCase<P2pSettings, String?> {
  SetSaveDir(this._settings, this._transfers);

  final P2pSettingsRepository _settings;
  final TransferRepository _transfers;

  @override
  Future<Result<P2pSettings>> call(String? path) async {
    final P2pSettings current;
    switch (await _settings.load()) {
      case Ok(:final value):
        current = value;
      case Err(:final failure):
        return Err(failure);
    }
    final next = current.copyWith(saveDir: path);
    if (await _settings.save(next) case Err(:final failure)) {
      return Err(failure);
    }
    return switch (await _transfers.updateSettings(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
