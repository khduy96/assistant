import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/todo.dart';
import '../repositories/todo_repository.dart';
import 'find_open_todos_linked_to.dart';
import 'set_todo_done.dart';

/// Ticks off every unfinished todo that was turned into the reminder with the
/// given id, as if each were ticked by hand. Works on the stored copies, so a
/// todo already done keeps its completion time and is not written again.
///
/// Stops at the first save that fails and returns that failure; the todos
/// ticked before it stay ticked, the one that failed is put back as it was.
/// Nothing to tick is not an error.
class CompleteTodosLinkedTo implements UseCase<void, String> {
  CompleteTodosLinkedTo(this._findOpen, this._setDone, this._repo, this._clock);

  final FindOpenTodosLinkedTo _findOpen;
  final SetTodoDone _setDone;
  final TodoRepository _repo;
  final Clock _clock;

  @override
  Future<Result<void>> call(String reminderId) async {
    switch (await _findOpen(reminderId)) {
      case Ok(:final value):
        for (final todo in value) {
          final saved = await _setDone((todo: todo, done: true));
          if (saved case Err(:final failure)) {
            await _untick(todo);
            return Err(failure);
          }
        }
        return const Ok(null);
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// Puts [todo] back after its tick could not be saved. A repository may
  /// keep a failed save in memory, to write it with the next save that
  /// succeeds; left there, the tick would read as done, and trying again
  /// would find nothing to tick and let the reminder go while the file still
  /// has the todo open. Only a copy that differs from [todo] by the tick
  /// alone is put back, so a later edit stays. The copy put back is stamped
  /// as edited now: sync keeps whichever copy was edited last, and with its
  /// old stamp this one would still be pushed over a newer edit made on
  /// another device, which that device would then never take back. Best
  /// effort: a failure here is not reported over the one that brought us
  /// here.
  Future<void> _untick(Todo todo) async {
    final current = switch (await _repo.getAll()) {
      Ok(:final value) => value.where((t) => t.id == todo.id).firstOrNull,
      Err() => null,
    };
    if (current == null || !current.done) return;
    final ticked = todo.copyWith(
      done: true,
      completedAt: current.completedAt,
      updatedAt: current.updatedAt,
    );
    if (current != ticked) return;
    await _repo.save(todo.copyWith(updatedAt: _clock.now()));
  }
}
