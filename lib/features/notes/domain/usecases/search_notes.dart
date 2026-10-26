import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/note.dart';
import '../repositories/note_repository.dart';
import '../services/note_ordering.dart';

/// Notes whose title or body contains the query, ignoring case, pinned first,
/// then most recently edited. An empty or blank query returns all.
class SearchNotes implements UseCase<List<Note>, String> {
  SearchNotes(this._repo);

  final NoteRepository _repo;

  @override
  Future<Result<List<Note>>> call(String query) async =>
      switch (await _repo.getAll()) {
        Ok(:final value) => Ok(
          NoteOrdering.sorted(value.where((n) => n.matches(query))),
        ),
        Err(:final failure) => Err(failure),
      };
}
