import '../../../domain/failure.dart';
import '../../../domain/result.dart';
import '../../../domain/usecase.dart';
import '../sync_engine.dart';

/// Server requests this device has made in the current calendar month.
class GetMonthRequests implements UseCase<int, NoParams> {
  GetMonthRequests(this._engine);

  final SyncEngine _engine;

  @override
  Future<Result<int>> call(NoParams params) async {
    try {
      return Ok(await _engine.requestsThisMonth());
    } catch (e) {
      return Err(StorageFailure('Could not read the request tally', cause: e));
    }
  }
}
