import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';

/// Drops temp clips captured more than [ClipItem.tempTtl] ago and yields how
/// many went. Saved and pinned clips never expire. Housekeeping: it asks for
/// no push, and writes nothing when no clip is due.
class PurgeExpiredClips implements UseCase<int, NoParams> {
  PurgeExpiredClips(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<int>> call(NoParams params) async {
    final cutoff = _clock.now().subtract(ClipItem.tempTtl);
    final List<String> ids;
    switch (await _repo.getClips()) {
      case Ok(:final value):
        ids = [
          for (final clip in value)
            if (clip.isTemp && clip.createdAt.isBefore(cutoff)) clip.id,
        ];
      case Err(:final failure):
        return Err(failure);
    }
    if (ids.isEmpty) return const Ok(0);
    return switch (await _repo.deleteClips(ids, share: false)) {
      Ok() => Ok(ids.length),
      Err(:final failure) => Err(failure),
    };
  }
}
