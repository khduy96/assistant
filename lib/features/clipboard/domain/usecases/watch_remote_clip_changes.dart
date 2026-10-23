import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/clipboard_repository.dart';

/// A stream that fires whenever a sync wrote clips or groups, so a listener
/// can reload them. Changes made through the other use cases do not fire it.
class WatchRemoteClipChanges implements UseCase<Stream<void>, NoParams> {
  WatchRemoteClipChanges(this._repo);

  final ClipboardRepository _repo;

  @override
  Future<Result<Stream<void>>> call(NoParams params) async =>
      Ok(_repo.remoteChanges);
}
