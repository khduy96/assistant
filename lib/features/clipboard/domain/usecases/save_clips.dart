import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// What [SaveClips] takes: the clips, and the group to file them in (null
/// keeps each clip's group).
typedef SaveClipsParams = ({List<ClipItem> clips, String? groupId});

/// [SaveClip] for a selection: keeps every clip in the saved list and yields
/// them as stored, in the order given. Stops at the first failure.
class SaveClips implements UseCase<List<ClipItem>, SaveClipsParams> {
  SaveClips(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<List<ClipItem>>> call(SaveClipsParams params) async {
    final now = _clock.now();
    final saved = <ClipItem>[];
    for (final clip in params.clips) {
      final next = ClipEdits.saved(clip, now, groupId: params.groupId);
      if (await _repo.saveClip(next) case Err(:final failure)) {
        return Err(failure);
      }
      saved.add(next);
    }
    return Ok(saved);
  }
}
