import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/note.dart';
import '../repositories/note_repository.dart';

/// What [SetNotePinned] takes: the note and whether it should be pinned.
typedef SetNotePinnedParams = ({Note note, bool pinned});

/// Pins a note to the top of the list or unpins it. Counts as an edit, so the
/// note is stamped as edited now and the next sync pushes it.
class SetNotePinned implements UseCase<void, SetNotePinnedParams> {
  SetNotePinned(this._repo, this._clock);

  final NoteRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(SetNotePinnedParams params) => _repo.save(
    params.note.copyWith(pinned: params.pinned, updatedAt: _clock.now()),
  );
}
