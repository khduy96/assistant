import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/clipboard_repository.dart';

/// Deletes every temp clip, leaving saved and pinned ones alone, and yields
/// how many went. Writes nothing when there is none.
class ClearTempClips implements UseCase<int, NoParams> {
  ClearTempClips(this._repo);

  final ClipboardRepository _repo;

  @override
  Future<Result<int>> call(NoParams params) async {
    final List<String> ids;
    switch (await _repo.getClips()) {
      case Ok(:final value):
        ids = [
          for (final clip in value)
            if (clip.isTemp) clip.id,
        ];
      case Err(:final failure):
        return Err(failure);
    }
    if (ids.isEmpty) return const Ok(0);
    return switch (await _repo.deleteClips(ids)) {
      Ok() => Ok(ids.length),
      Err(:final failure) => Err(failure),
    };
  }
}
