import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// What [AssignClipGroup] takes: the clip, and the group to file it in, or
/// null to take it out of any group.
typedef AssignClipGroupParams = ({ClipItem clip, String? groupId});

/// Files a clip into a group, or takes it out, and yields it as stored.
/// Filing a temp clip also saves it: see [ClipEdits.grouped].
class AssignClipGroup implements UseCase<ClipItem, AssignClipGroupParams> {
  AssignClipGroup(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(AssignClipGroupParams params) async {
    final next = ClipEdits.grouped(params.clip, params.groupId, _clock.now());
    return switch (await _repo.saveClip(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
