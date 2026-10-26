import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';

/// Deletes a clip for good; if it ever reached the server its object is
/// deleted there too on the next sync. [RestoreClip] undoes it.
class DeleteClip implements UseCase<void, ClipItem> {
  DeleteClip(this._repo);

  final ClipboardRepository _repo;

  @override
  Future<Result<void>> call(ClipItem clip) => _repo.deleteClips([clip.id]);
}
