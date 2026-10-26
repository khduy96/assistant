import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/reminder_repository.dart';

/// A stream that fires whenever the stored reminders change, so a listener
/// can reload the list.
class WatchReminders implements UseCase<Stream<void>, NoParams> {
  WatchReminders(this._repo);

  final ReminderRepository _repo;

  @override
  Future<Result<Stream<void>>> call(NoParams params) async => Ok(_repo.changes);
}
