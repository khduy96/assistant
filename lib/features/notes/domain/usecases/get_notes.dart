import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/note.dart';
import '../repositories/note_repository.dart';
import '../services/note_ordering.dart';

/// Every note, pinned first, then most recently edited.
class GetNotes implements UseCase<List<Note>, NoParams> {
  GetNotes(this._repo);

  final NoteRepository _repo;

  @override
  Future<Result<List<Note>>> call(NoParams params) async =>
      switch (await _repo.getAll()) {
        Ok(:final value) => Ok(NoteOrdering.sorted(value)),
        Err(:final failure) => Err(failure),
      };
}
