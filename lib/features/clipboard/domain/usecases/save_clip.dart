import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// What [SaveClip] takes: the clip, and the group to file it in (null keeps
/// its group).
typedef SaveClipParams = ({ClipItem clip, String? groupId});

/// Keeps a clip in the saved list (see [ClipEdits.saved]) and yields it as
/// stored.
class SaveClip implements UseCase<ClipItem, SaveClipParams> {
  SaveClip(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(SaveClipParams params) async {
    final next = ClipEdits.saved(
      params.clip,
      _clock.now(),
      groupId: params.groupId,
    );
    return switch (await _repo.saveClip(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
