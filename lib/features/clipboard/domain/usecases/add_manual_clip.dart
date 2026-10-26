import '../../../../core/domain/clock.dart';
import '../../../../core/domain/id_generator.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';

/// What [AddManualClip] takes: the typed content, and the group to file the
/// clip in, if any.
typedef AddManualClipParams = ({String content, String? groupId});

/// Adds a clip typed by the user, trimmed, created and edited now. It goes
/// straight to the saved list. Yields the clip as stored.
class AddManualClip implements UseCase<ClipItem, AddManualClipParams> {
  AddManualClip(this._repo, this._ids, this._clock);

  final ClipboardRepository _repo;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(AddManualClipParams params) async {
    final now = _clock.now();
    final clip = ClipItem(
      id: _ids.newId(),
      content: params.content.trim(),
      type: ClipItem.detectType(params.content),
      createdAt: now,
      updatedAt: now,
      isSaved: true,
      groupId: params.groupId,
    );
    return switch (await _repo.saveClip(clip)) {
      Ok() => Ok(clip),
      Err(:final failure) => Err(failure),
    };
  }
}
