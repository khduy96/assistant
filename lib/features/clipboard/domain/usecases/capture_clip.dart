import '../../../../core/domain/clock.dart';
import '../../../../core/domain/id_generator.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';

/// Stores a value seen on the system clipboard, trimmed, as a new temp clip
/// and yields it. Blank text is ignored: nothing is stored and the result is
/// null.
///
/// When a clip with that exact content already exists it is bumped to the top
/// instead (see [ClipEdits.recaptured]), so repeated copies never flood the
/// list. Only a bumped saved clip asks for a push; temp clips stay local.
class CaptureClip implements UseCase<ClipItem?, String> {
  CaptureClip(this._repo, this._ids, this._clock);

  final ClipboardRepository _repo;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<ClipItem?>> call(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const Ok(null);

    final ClipItem? existing;
    switch (await _repo.findClipByContent(trimmed)) {
      case Ok(:final value):
        existing = value;
      case Err(:final failure):
        return Err(failure);
    }

    final now = _clock.now();
    final clip = existing != null
        ? ClipEdits.recaptured(existing, now)
        : ClipItem(
            id: _ids.newId(),
            content: trimmed,
            type: ClipItem.detectType(trimmed),
            createdAt: now,
            updatedAt: now,
          );
    return switch (await _repo.saveClip(clip, share: !clip.isTemp)) {
      Ok() => Ok(clip),
      Err(:final failure) => Err(failure),
    };
  }
}
