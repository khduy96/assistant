import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';

/// Undo for [DeleteClips]: [RestoreClip] for each clip, in the order given.
/// Yields the clips as stored. Stops at the first failure.
class RestoreClips implements UseCase<List<ClipItem>, List<ClipItem>> {
  RestoreClips(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<List<ClipItem>>> call(List<ClipItem> clips) async {
    final now = _clock.now();
    final revived = <ClipItem>[];
    for (final clip in clips) {
      final next = clip.copyWith(updatedAt: now);
      if (await _repo.restoreClip(next) case Err(:final failure)) {
        return Err(failure);
      }
      revived.add(next);
    }
    return Ok(revived);
  }
}
