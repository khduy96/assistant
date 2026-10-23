import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// Pins a clip, or unpins it when it is pinned, and yields it as stored.
/// Pinning a temp clip also saves it: see [ClipEdits.pinned].
class ToggleClipPin implements UseCase<ClipItem, ClipItem> {
  ToggleClipPin(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(ClipItem clip) async {
    final next = ClipEdits.pinned(clip, !clip.isPinned, _clock.now());
    return switch (await _repo.saveClip(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
