import '../../../../core/domain/clock.dart';
import '../../../../core/domain/id_generator.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/note.dart';

/// A blank note with a fresh id, created and edited now. Nothing is stored:
/// the editor fills it in and hands it to `SaveNote`.
class NewNote implements UseCase<Note, NoParams> {
  NewNote(this._ids, this._clock);

  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<Note>> call(NoParams params) async {
    final now = _clock.now();
    return Ok(Note(id: _ids.newId(), createdAt: now, updatedAt: now));
  }
}
