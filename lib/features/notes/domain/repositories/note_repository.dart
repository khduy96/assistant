import '../../../../core/domain/result.dart';
import '../entities/note.dart';

/// Where notes are kept. Implemented in the data layer.
///
/// No method throws: IO and format errors come back as an `Err`.
abstract interface class NoteRepository {
  /// Every stored note, in no particular order.
  Future<Result<List<Note>>> getAll();

  /// Adds [note], or replaces the stored note with the same id.
  Future<Result<void>> save(Note note);

  /// Removes the note with [id]. Removing an unknown id is not an error.
  Future<Result<void>> delete(String id);

  /// Fires after the stored notes change, including changes a sync applied.
  Stream<void> get changes;
}
