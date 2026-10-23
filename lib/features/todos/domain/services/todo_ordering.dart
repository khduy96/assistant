import '../entities/todo.dart';

/// The order todos are listed in. Unfinished first: high priority floats to
/// the top, then the nearest due date (items with one above items without),
/// then the oldest. Finished items sink to the bottom, most recently finished
/// first.
abstract final class TodoOrdering {
  static int compare(Todo a, Todo b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    if (a.done) {
      final ac = a.completedAt, bc = b.completedAt;
      if (ac != null && bc != null) return bc.compareTo(ac);
      return b.createdAt.compareTo(a.createdAt);
    }
    if (a.priority != b.priority) {
      return b.priority.index.compareTo(a.priority.index);
    }
    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    return a.createdAt.compareTo(b.createdAt);
  }

  /// [todos] as a new list in display order.
  static List<Todo> sorted(Iterable<Todo> todos) =>
      todos.toList()..sort(compare);
}
