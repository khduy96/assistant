import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_group.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';

/// Deletes a group but keeps its clips: they fall back to "chưa phân nhóm",
/// stay saved, and are stamped as edited now so other devices hear that they
/// left the group. Yields those clips as stored.
///
/// The clips are moved out before the group goes, so a failure part way
/// leaves the group in place.
class DeleteClipGroup implements UseCase<List<ClipItem>, ClipGroup> {
  DeleteClipGroup(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<List<ClipItem>>> call(ClipGroup group) async {
    final List<ClipItem> members;
    switch (await _repo.getClips()) {
      case Ok(:final value):
        members = [
          for (final clip in value)
            if (clip.groupId == group.id) clip,
        ];
      case Err(:final failure):
        return Err(failure);
    }
    final now = _clock.now();
    final ungrouped = <ClipItem>[];
    for (final clip in members) {
      final next = clip.copyWith(groupId: null, updatedAt: now);
      if (await _repo.saveClip(next) case Err(:final failure)) {
        return Err(failure);
      }
      ungrouped.add(next);
    }
    return switch (await _repo.deleteGroup(group.id)) {
      Ok() => Ok(ungrouped),
      Err(:final failure) => Err(failure),
    };
  }
}
