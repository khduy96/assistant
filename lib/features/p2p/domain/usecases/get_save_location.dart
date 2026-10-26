import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/save_location.dart';
import '../repositories/p2p_settings_repository.dart';
import '../repositories/transfer_repository.dart';

/// Where received files go with the current settings.
class GetSaveLocation implements UseCase<SaveLocation, NoParams> {
  GetSaveLocation(this._settings, this._transfers);

  final P2pSettingsRepository _settings;
  final TransferRepository _transfers;

  @override
  Future<Result<SaveLocation>> call(NoParams params) async =>
      switch (await _settings.load()) {
        Ok(:final value) => await _transfers.saveLocation(value.saveDir),
        Err(:final failure) => Err(failure),
      };
}
