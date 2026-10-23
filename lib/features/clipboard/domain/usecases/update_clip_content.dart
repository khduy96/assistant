import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// What [UpdateClipContent] takes: the clip, its new content, and a new note
/// (null keeps the current one).
typedef UpdateClipContentParams = ({
  ClipItem clip,
  String content,
  String? note,
});

/// Replaces a clip's content (see [ClipEdits.edited]) and yields it as stored.
class UpdateClipContent implements UseCase<ClipItem, UpdateClipContentParams> {
  UpdateClipContent(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(UpdateClipContentParams params) async {
    final next = ClipEdits.edited(
      params.clip,
      params.content,
      _clock.now(),
      note: params.note,
    );
    return switch (await _repo.saveClip(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
