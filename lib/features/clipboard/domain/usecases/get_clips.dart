import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_item.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_ordering.dart';

/// Every clip, newest first: see [ClipOrdering.newestFirst].
class GetClips implements UseCase<List<ClipItem>, NoParams> {
  GetClips(this._repo);

  final ClipboardRepository _repo;

  @override
  Future<Result<List<ClipItem>>> call(NoParams params) async =>
      switch (await _repo.getClips()) {
        Ok(:final value) => Ok(value.toList()..sort(ClipOrdering.newestFirst)),
        Err(:final failure) => Err(failure),
      };
}
