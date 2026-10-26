import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// Moves a clip back to the temp list (see [ClipEdits.unsaved]) and yields it
/// as stored.
///
/// Temp clips stay on this device, so the clip is first taken off the server
/// ([ClipboardRepository.detachFromServer]); saving it again later pushes it
/// as a new object.
class UnsaveClip implements UseCase<ClipItem, ClipItem> {
  UnsaveClip(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(ClipItem clip) async {
    if (await _repo.detachFromServer(clip.id) case Err(:final failure)) {
      return Err(failure);
    }
    final next = ClipEdits.unsaved(clip, _clock.now());
    return switch (await _repo.saveClip(next)) {
      Ok() => Ok(next),
      Err(:final failure) => Err(failure),
    };
  }
}
