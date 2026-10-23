import '../../../domain/failure.dart';
import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../entities/sync_status.dart';
import '../sync_engine.dart';

class RunSyncParams {
  const RunSyncParams({this.full = false});

  /// Pull every class whatever the server's change counters say.
  final bool full;
}

/// Runs one sync cycle and reports how it went.
///
/// A cycle that failed is still [Ok]: its [SyncStatus] says what went wrong,
/// in words meant for the user.
class RunSync implements UseCase<SyncStatus, RunSyncParams> {
  RunSync(this._engine);

  final SyncEngine _engine;

  @override
  Future<Result<SyncStatus>> call(RunSyncParams params) async {
    try {
      return Ok(await _engine.sync(full: params.full));
    } catch (e) {
      return Err(UnexpectedFailure('Sync cycle failed', cause: e));
    }
  }
}
