import '../../domain/entities/todo.dart';
import '../models/todo_model.dart';

/// Converts between the stored [TodoModel] and the domain [Todo].
abstract final class TodoMapper {
  /// The entity view of [model]. The sync state stays behind in the model.
  static Todo toEntity(TodoModel model) => Todo(
    id: model.id,
    title: model.title,
    note: model.note,
    done: model.done,
    priority: model.priority,
    dueDate: model.dueDate,
    completedAt: model.completedAt,
    reminderId: model.reminderId,
    createdAt: model.createdAt,
    updatedAt: model.updatedAt,
  );

  /// The model to store for an edited [todo]. Keeps the `remoteId` of
  /// [stored], the copy saved so far (null for a new item), so the next push
  /// updates the existing server object instead of creating a second one, and
  /// marks the result dirty so that push happens.
  static TodoModel toModel(Todo todo, {TodoModel? stored}) => TodoModel(
    id: todo.id,
    title: todo.title,
    note: todo.note,
    done: todo.done,
    priority: todo.priority,
    dueDate: todo.dueDate,
    completedAt: todo.completedAt,
    reminderId: todo.reminderId,
    createdAt: todo.createdAt,
    updatedAt: todo.updatedAt,
    remoteId: stored?.remoteId,
    dirty: true,
  );
}
