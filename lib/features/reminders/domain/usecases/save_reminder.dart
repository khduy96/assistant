import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';

/// Adds a reminder or replaces the one with the same id, and yields what was
/// stored.
///
/// Anything before now counts as handled, so saving an edit never rings for a
/// moment that has already passed.
class SaveReminder implements UseCase<Reminder, Reminder> {
  SaveReminder(this._repo, this._clock);

  final ReminderRepository _repo;
  final Clock _clock;

  @override
  Future<Result<Reminder>> call(Reminder reminder) async {
    final saved = reminder.copyWith(firedUpTo: _clock.now());
    return switch (await _repo.save(saved)) {
      Ok() => Ok(saved),
      Err(:final failure) => Err(failure),
    };
  }
}
