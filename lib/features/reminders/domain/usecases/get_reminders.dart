import '../../../../core/domain/clock.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';
import '../services/reminder_ordering.dart';

/// Every reminder in display order as of now: see [ReminderOrdering.sorted].
class GetReminders implements UseCase<List<Reminder>, NoParams> {
  GetReminders(this._repo, this._clock);

  final ReminderRepository _repo;
  final Clock _clock;

  @override
  Future<Result<List<Reminder>>> call(NoParams params) async =>
      switch (await _repo.getAll()) {
        Ok(:final value) => Ok(ReminderOrdering.sorted(value, _clock.now())),
        Err(:final failure) => Err(failure),
      };
}
