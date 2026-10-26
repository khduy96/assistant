import '../../../../core/domain/result.dart';

/// The reminders feature's view of the todo list: the items that were turned
/// into a deadline point at it by its id. Implemented by an adapter in
/// `lib/app/di/bridges/`, so this feature never imports todos.
///
/// No method throws: failures come back as an `Err`.
abstract interface class LinkedTodos {
  /// Titles of the items that are not done yet and point at the reminder with
  /// [reminderId]; empty when there are none.
  Future<Result<List<String>>> openTitlesFor(String reminderId);

  /// Marks every item that points at the reminder with [reminderId] as done.
  /// Items already done are left as they are, and having no item is not an
  /// error.
  Future<Result<void>> completeFor(String reminderId);
}
