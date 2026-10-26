import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';

/// Undo for [DeleteClip]: puts the clip back as it was, stamped as edited
/// now, and yields it as stored. A server delete that has not gone out yet is
/// cancelled rather than raced.
class RestoreClip implements UseCase<ClipItem, ClipItem> {
  RestoreClip(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipItem>> call(ClipItem clip) async {
    final revived = clip.copyWith(updatedAt: _clock.now());
    return switch (await _repo.restoreClip(revived)) {
      Ok() => Ok(revived),
      Err(:final failure) => Err(failure),
    };
  }
}
