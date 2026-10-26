import '../../../domain/failure.dart';
import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../entities/sync_status.dart';
import '../sync_engine.dart';

class RunSyncParams {
  const RunSyncParams({
    this.full = false,
    this.auto = false,
    this.checkRemote = true,
  });

  /// Pull every class whatever the server's change counters say.
  final bool full;

  /// A cycle no one asked for, held to this device's request budget.
  final bool auto;

  /// False to push only, without asking the server what changed.
  final bool checkRemote;
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
      return Ok(
        await _engine.sync(
          full: params.full,
          auto: params.auto,
          checkRemote: params.checkRemote,
        ),
      );
    } catch (e) {
      return Err(UnexpectedFailure('Sync cycle failed', cause: e));
    }
  }
}
