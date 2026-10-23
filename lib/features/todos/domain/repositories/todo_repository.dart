import '../../../../core/domain/result.dart';
import '../entities/todo.dart';

/// Where todos are kept. Implemented in the data layer.
///
/// No method throws: IO and format errors come back as an `Err`.
abstract interface class TodoRepository {
  /// Every stored todo, in no particular order.
  Future<Result<List<Todo>>> getAll();

  /// Adds [todo], or replaces the stored todo with the same id.
  Future<Result<void>> save(Todo todo);

  /// Removes the todo with [id]. Removing an unknown id is not an error.
  Future<Result<void>> delete(String id);

  /// Removes every todo whose id is in [ids] in one write. Unknown ids are
  /// skipped.
  Future<Result<void>> deleteAll(Iterable<String> ids);

  /// Fires after the stored todos change, including changes a sync applied.
  Stream<void> get changes;
}
