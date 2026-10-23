import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../entities/sync_settings.dart';
import '../sync_engine.dart';

/// Whether sync is set up, whether it runs on its own, and the space.
class GetSyncSettings implements UseCase<SyncSettings, NoParams> {
  GetSyncSettings(this._engine);

  final SyncEngine _engine;

  @override
  Future<Result<SyncSettings>> call(NoParams params) async =>
      Ok(_engine.settings);
}
