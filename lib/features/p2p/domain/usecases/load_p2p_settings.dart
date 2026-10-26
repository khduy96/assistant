import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/p2p_settings.dart';
import '../repositories/p2p_settings_repository.dart';

/// This device's file-transfer settings, made and saved on first run.
class LoadP2pSettings implements UseCase<P2pSettings, NoParams> {
  LoadP2pSettings(this._settings);

  final P2pSettingsRepository _settings;

  @override
  Future<Result<P2pSettings>> call(NoParams params) => _settings.load();
}
