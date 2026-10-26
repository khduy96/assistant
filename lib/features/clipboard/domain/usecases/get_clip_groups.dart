import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_group.dart';
import '../repositories/clipboard_repository.dart';
import '../services/clip_ordering.dart';

/// Every group in list order: see [ClipOrdering.groups].
class GetClipGroups implements UseCase<List<ClipGroup>, NoParams> {
  GetClipGroups(this._repo);

  final ClipboardRepository _repo;

  @override
  Future<Result<List<ClipGroup>>> call(NoParams params) async =>
      switch (await _repo.getGroups()) {
        Ok(:final value) => Ok(value.toList()..sort(ClipOrdering.groups)),
        Err(:final failure) => Err(failure),
      };
}
