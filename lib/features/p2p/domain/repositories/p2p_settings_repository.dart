import '../../../../core/domain/result.dart';
import '../entities/p2p_settings.dart';

/// Where this device's file-transfer settings are kept (`p2p.json` in the data
/// layer, whose format must not change).
///
/// No method throws: IO errors come back as an `Err`.
abstract interface class P2pSettingsRepository {
  /// The settings as last saved.
  ///
  /// The first call reads them from disk. When there is nothing usable there
  /// (no file, or a broken one), fresh settings are made — a new device id, a
  /// default name for this machine, auto-accept off, transfer on — and saved
  /// at once, so the id stays the same from then on. If that save fails, the
  /// fresh settings are still returned and kept for this run.
  Future<Result<P2pSettings>> load();

  /// Stores [settings] in place of the previous ones; later [load] calls
  /// yield them. When writing fails, the previous settings stay in effect and
  /// an `Err` is returned.
  Future<Result<void>> save(P2pSettings settings);
}
