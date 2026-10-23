import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/note_repository.dart';

/// Removes the note with the given id.
class DeleteNote implements UseCase<void, String> {
  DeleteNote(this._repo);

  final NoteRepository _repo;

  @override
  Future<Result<void>> call(String id) => _repo.delete(id);
}
