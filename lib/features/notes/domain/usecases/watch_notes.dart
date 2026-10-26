import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/note_repository.dart';

/// A stream that fires whenever the stored notes change, including changes a
/// sync applied, so a listener can reload the list.
class WatchNotes implements UseCase<Stream<void>, NoParams> {
  WatchNotes(this._repo);

  final NoteRepository _repo;

  @override
  Future<Result<Stream<void>>> call(NoParams params) async => Ok(_repo.changes);
}
