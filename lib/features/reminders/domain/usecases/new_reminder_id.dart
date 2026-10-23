import '../../../../core/domain/id_generator.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';

/// A fresh id for a reminder the editor is about to create.
class NewReminderId implements UseCase<String, NoParams> {
  NewReminderId(this._ids);

  final IdGenerator _ids;

  @override
  Future<Result<String>> call(NoParams params) async => Ok(_ids.newId());
}
