import '../../../../core/domain/clock.dart';
import '../../../../core/domain/id_generator.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_group.dart';
import '../repositories/clipboard_repository.dart';

/// What [CreateClipGroup] takes: the name and the ARGB colour.
typedef CreateClipGroupParams = ({String name, int color});

/// Creates a group with a trimmed name at the end of the group list, created
/// and edited now, and yields it as stored.
class CreateClipGroup implements UseCase<ClipGroup, CreateClipGroupParams> {
  CreateClipGroup(this._repo, this._ids, this._clock);

  final ClipboardRepository _repo;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<ClipGroup>> call(CreateClipGroupParams params) async {
    final int count;
    switch (await _repo.getGroups()) {
      case Ok(:final value):
        count = value.length;
      case Err(:final failure):
        return Err(failure);
    }
    final now = _clock.now();
    final group = ClipGroup(
      id: _ids.newId(),
      name: params.name.trim(),
      color: params.color,
      createdAt: now,
      updatedAt: now,
      sortOrder: count,
    );
    return switch (await _repo.saveGroup(group)) {
      Ok() => Ok(group),
      Err(:final failure) => Err(failure),
    };
  }
}
