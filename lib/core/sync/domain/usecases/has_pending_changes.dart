import '../../../domain/failure.dart';
import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../sync_engine.dart';

/// Whether edits, deletes or a change-counter bump still wait to go out.
/// Sends no request.
class HasPendingChanges implements UseCase<bool, NoParams> {
  HasPendingChanges(this._engine);

  final SyncEngine _engine;

  @override
  Future<Result<bool>> call(NoParams params) async {
    try {
      return Ok(await _engine.hasLocalChanges());
    } catch (e) {
      return Err(StorageFailure('Could not read pending changes', cause: e));
    }
  }
}
