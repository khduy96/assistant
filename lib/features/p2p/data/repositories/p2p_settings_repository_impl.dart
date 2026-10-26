import '../../../../core/domain/failure.dart';
import '../../../../core/domain/id_generator.dart';
import '../../../../core/domain/result.dart';
import '../../domain/entities/p2p_settings.dart';
import '../../domain/repositories/p2p_settings_repository.dart';
import '../datasources/local_device.dart';
import '../datasources/p2p_settings_local_data_source.dart';
import '../mappers/p2p_settings_mapper.dart';
import '../models/p2p_settings_model.dart';

/// Keeps the file-transfer settings in memory and in `p2p.json`.
///
/// The file is read once; later loads come from memory. A device id missing
/// from the file comes from the [IdGenerator], a missing name from
/// [LocalDevice.defaultName]. When the file is missing or unreadable as a
/// whole, the fresh settings are written at once so the id sticks.
class P2pSettingsRepositoryImpl implements P2pSettingsRepository {
  P2pSettingsRepositoryImpl(
    this._source,
    this._ids, {
    this.device = const LocalDevice(),
  });

  final P2pSettingsLocalDataSource _source;
  final IdGenerator _ids;
  final LocalDevice device;

  P2pSettings? _current;
  Future<P2pSettings>? _loading;

  @override
  Future<Result<P2pSettings>> load() async {
    final cached = _current;
    if (cached != null) return Ok(cached);
    try {
      return Ok(await (_loading ??= _read()));
    } catch (e) {
      // Try the file again on the next call.
      _loading = null;
      return Err(StorageFailure('p2p.json could not be read', cause: e));
    }
  }

  Future<P2pSettings> _read() async {
    final raw = await _source.load();
    final model = P2pSettingsModel.fromJson(
      raw,
      newId: _ids.newId,
      defaultName: device.defaultName,
    );
    if (raw.isEmpty) {
      try {
        await _source.save(model.toJson());
      } catch (_) {
        // Still used for this run; the next start tries again.
      }
    }
    // A save that landed while the file was being read wins.
    return _current ??= P2pSettingsMapper.toEntity(model);
  }

  @override
  Future<Result<void>> save(P2pSettings settings) async {
    try {
      await _source.save(P2pSettingsMapper.toModel(settings).toJson());
    } catch (e) {
      return Err(StorageFailure('p2p.json could not be written', cause: e));
    }
    _current = settings;
    return const Ok(null);
  }
}
