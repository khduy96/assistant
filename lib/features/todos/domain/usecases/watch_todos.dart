import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/todo_repository.dart';

/// A stream that fires whenever the stored todos change, including changes a
/// sync applied, so a listener can reload the list.
class WatchTodos implements UseCase<Stream<void>, NoParams> {
  WatchTodos(this._repo);

  final TodoRepository _repo;

  @override
  Future<Result<Stream<void>>> call(NoParams params) async => Ok(_repo.changes);
}
