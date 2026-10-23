import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// What [AssignClipsGroup] takes: the clips, and the group to file them in,
/// or null to take them out of any group.
typedef AssignClipsGroupParams = ({List<ClipItem> clips, String? groupId});

/// [AssignClipGroup] for a selection: yields the clips as stored, in the
/// order given. Stops at the first failure.
class AssignClipsGroup
    implements UseCase<List<ClipItem>, AssignClipsGroupParams> {
  AssignClipsGroup(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<List<ClipItem>>> call(AssignClipsGroupParams params) async {
    final now = _clock.now();
    final done = <ClipItem>[];
    for (final clip in params.clips) {
      final next = ClipEdits.grouped(clip, params.groupId, now);
      if (await _repo.saveClip(next) case Err(:final failure)) {
        return Err(failure);
      }
      done.add(next);
    }
    return Ok(done);
  }
}
