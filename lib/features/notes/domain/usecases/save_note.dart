import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/note.dart';
import '../repositories/note_repository.dart';

/// Adds a note or replaces the one with the same id, stamping it as edited
/// now.
class SaveNote implements UseCase<void, Note> {
  SaveNote(this._repo, this._clock);

  final NoteRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(Note note) {
    // An empty note is deleted: backing out of the editor leaves nothing behind.
    if (note.isEmpty) return _repo.delete(note.id);
    return _repo.save(note.copyWith(updatedAt: _clock.now()));
  }
}
