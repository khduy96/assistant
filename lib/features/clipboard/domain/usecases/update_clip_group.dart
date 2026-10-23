import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/clip_group.dart';
import '../repositories/clipboard_repository.dart';

/// What [UpdateClipGroup] takes: the group, its new name and ARGB colour.
typedef UpdateClipGroupParams = ({ClipGroup group, String name, int color});

/// Renames and recolours a group, stamped as edited now, and yields it as
/// stored.
class UpdateClipGroup implements UseCase<ClipGroup, UpdateClipGroupParams> {
  UpdateClipGroup(this._repo, this._clock);

  final ClipboardRepository _repo;
  final Clock _clock;

  @override
  Future<Result<ClipGroup>> call(UpdateClipGroupParams params) async {
    final updated = params.group.copyWith(
      name: params.name,
      color: params.color,
      updatedAt: _clock.now(),
    );
    return switch (await _repo.saveGroup(updated)) {
      Ok() => Ok(updated),
      Err(:final failure) => Err(failure),
    };
  }
}
