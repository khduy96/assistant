import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../sync_engine.dart';

/// A stream that fires after any synced list changed on this device, so a
/// push can be scheduled. Changes a sync applied do not fire it.
class WatchLocalChanges implements UseCase<Stream<void>, NoParams> {
  WatchLocalChanges(this._engine);

  final SyncEngine _engine;

  @override
  Future<Result<Stream<void>>> call(NoParams params) async =>
      Ok(_engine.localChanges);
}
