import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// [UnsaveClip] for a selection: moves every saved clip in it back to the temp
/// list, skipping those that are not saved. Yields the clips it moved, as
/// stored, in the order given. Stops at the first failure.
class UnsaveClips implements UseCase<List<ClipItem>, List<ClipItem>> {
  UnsaveClips(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<List<ClipItem>>> call(List<ClipItem> clips) async {
    final now = _clock.now();
    final unsaved = <ClipItem>[];
    for (final clip in clips.where((c) => c.isSaved)) {
      if (await _repo.detachFromServer(clip.id) case Err(:final failure)) {
        return Err(failure);
      }
      final next = ClipEdits.unsaved(clip, now);
      if (await _repo.saveClip(next) case Err(:final failure)) {
        return Err(failure);
      }
      unsaved.add(next);
    }
    return Ok(unsaved);
  }
}
