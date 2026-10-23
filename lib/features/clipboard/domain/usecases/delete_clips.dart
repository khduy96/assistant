import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';

/// [DeleteClip] for a selection, in one write. Yields the deleted clips as
/// given, so the caller can offer an undo through [RestoreClips]. An empty
/// selection writes nothing.
class DeleteClips implements UseCase<List<ClipItem>, List<ClipItem>> {
  DeleteClips(this._repo);

  final ClipboardRepository _repo;

  @override
  Future<Result<List<ClipItem>>> call(List<ClipItem> clips) async {
    if (clips.isEmpty) return const Ok([]);
    return switch (await _repo.deleteClips([for (final c in clips) c.id])) {
      Ok() => Ok(clips),
      Err(:final failure) => Err(failure),
    };
  }
}
