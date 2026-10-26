import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../ports/clipboard_source.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// Puts a clip back on the system clipboard, ready to paste, then records the
/// copy (see [ClipEdits.copied]) and yields the clip as recorded.
class CopyClip implements UseCase<ClipItem, ClipItem> {
  CopyClip(this._source, this._repo, this._clock);

  final ClipboardSource _source;
  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(ClipItem clip) async {
    if (await _source.write(clip.content) case Err(:final failure)) {
      return Err(failure);
    }
    final copied = ClipEdits.copied(clip, _clock.now());
    return switch (await _repo.recordCopy(copied)) {
      Ok() => Ok(copied),
      Err(:final failure) => Err(failure),
    };
  }
}
