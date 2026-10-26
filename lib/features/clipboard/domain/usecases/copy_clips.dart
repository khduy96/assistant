import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../ports/clipboard_source.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_edits.dart';
import '../services/clip_ordering.dart';

/// Copies several clips as one block, oldest first, one per line, then
/// records a copy of each. Yields the clips as recorded, in that order; an
/// empty list copies and writes nothing.
class CopyClips implements UseCase<List<ClipItem>, List<ClipItem>> {
  CopyClips(this._source, this._repo, this._clock);

  final ClipboardSource _source;
  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<List<ClipItem>>> call(List<ClipItem> clips) async {
    final items = clips.toList()..sort(ClipOrdering.oldestFirst);
    if (items.isEmpty) return const Ok([]);
    final text = items.map((c) => c.content).join('\n');
    if (await _source.write(text) case Err(:final failure)) {
      return Err(failure);
    }
    final now = _clock.now();
    final copied = <ClipItem>[];
    for (final item in items) {
      final next = ClipEdits.copied(item, now);
      if (await _repo.recordCopy(next) case Err(:final failure)) {
        return Err(failure);
      }
      copied.add(next);
    }
    return Ok(copied);
  }
}
