import '../../../../core/domain/clock.dart';
import '../../../../core/domain/id_generator.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

/// Adds a bare item typed into the quick-add box, trimmed, created and edited
/// now. A blank title is ignored: nothing is stored and the result is null.
class AddTodo implements UseCase<Todo?, String> {
  AddTodo(this._repo, this._ids, this._clock);

  final TodoRepository _repo;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<Todo?>> call(String title) async {
    final text = title.trim();
    if (text.isEmpty) return const Ok(null);
    final now = _clock.now();
    final todo = Todo(
      id: _ids.newId(),
      title: text,
      createdAt: now,
      updatedAt: now,
    );
    return switch (await _repo.save(todo)) {
      Ok() => Ok(todo),
      Err(:final failure) => Err(failure),
    };
  }
}
