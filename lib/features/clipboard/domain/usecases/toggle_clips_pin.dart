import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// What [ToggleClipsPin] yields: the clips as stored, in the order given, and
/// whether they were pinned (true) or unpinned (false).
typedef ToggleClipsPinResult = ({List<ClipItem> clips, bool pinned});

/// Pins every clip of a selection, or unpins them all when every one is
/// already pinned. Pinning a temp clip also saves it: see [ClipEdits.pinned].
/// An empty selection writes nothing and yields `(clips: [], pinned: false)`.
/// Stops at the first failure.
class ToggleClipsPin implements UseCase<ToggleClipsPinResult, List<ClipItem>> {
  ToggleClipsPin(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ToggleClipsPinResult>> call(List<ClipItem> clips) async {
    if (clips.isEmpty) return const Ok((clips: [], pinned: false));
    final pin = !clips.every((c) => c.isPinned);
    final now = _clock.now();
    final done = <ClipItem>[];
    for (final clip in clips) {
      final next = ClipEdits.pinned(clip, pin, now);
      if (await _repo.saveClip(next) case Err(:final failure)) {
        return Err(failure);
      }
      done.add(next);
    }
    return Ok((clips: done, pinned: pin));
  }
}
