import 'package:get_it/get_it.dart';

import 'data/datasources/todo_local_data_source.dart';
import 'data/repositories/todo_repository_impl.dart';
import 'data/sync/todo_sync_collection.dart';
import 'domain/repositories/todo_repository.dart';
import 'domain/usecases/add_todo.dart';
import 'domain/usecases/clear_done_todos.dart';
import 'domain/usecases/draft_reminder_from_todo.dart';
import 'domain/usecases/find_linked_reminder.dart';
import 'domain/usecases/get_todos.dart';
import 'domain/usecases/link_reminder.dart';
import 'domain/usecases/new_todo_id.dart';
import 'domain/usecases/remove_linked_reminder.dart';
import 'domain/usecases/remove_todo.dart';
import 'domain/usecases/save_todo.dart';
import 'domain/usecases/set_linked_reminder_enabled.dart';
import 'domain/usecases/set_todo_done.dart';
import 'domain/usecases/watch_linked_reminders.dart';
import 'domain/usecases/watch_todos.dart';
import 'presentation/todos_controller.dart';

/// Registers the todos feature in [sl]. Expects a `Clock`, an `IdGenerator`
/// and a `LinkedReminderRepository` to be registered already; the last one is
/// the app's bridge to the reminders, which this feature never imports.
///
/// [TodoRepositoryImpl] is one singleton seen under two types: the use cases
/// get it as [TodoRepository], while the app shell needs the concrete class
/// to load the file at startup, and [TodoSyncCollection] to reach the sync
/// state the interface hides.
void registerTodos(GetIt sl) {
  sl
    ..registerLazySingleton(() => TodoLocalDataSource(sl()))
    ..registerLazySingleton(() => TodoRepositoryImpl(sl()))
    ..registerLazySingleton<TodoRepository>(() => sl<TodoRepositoryImpl>())
    ..registerLazySingleton(() => TodoSyncCollection(sl(), sl()))
    ..registerLazySingleton(() => GetTodos(sl()))
    ..registerLazySingleton(() => WatchTodos(sl()))
    ..registerLazySingleton(() => AddTodo(sl(), sl(), sl()))
    ..registerLazySingleton(() => SaveTodo(sl(), sl()))
    ..registerLazySingleton(() => SetTodoDone(sl(), sl()))
    ..registerLazySingleton(() => LinkReminder(sl(), sl()))
    ..registerLazySingleton(() => RemoveTodo(sl()))
    ..registerLazySingleton(() => ClearDoneTodos(sl()))
    ..registerLazySingleton(() => NewTodoId(sl()))
    ..registerLazySingleton(() => DraftReminderFromTodo(sl()))
    ..registerLazySingleton(() => FindLinkedReminder(sl()))
    ..registerLazySingleton(() => SetLinkedReminderEnabled(sl()))
    ..registerLazySingleton(() => RemoveLinkedReminder(sl()))
    ..registerLazySingleton(() => WatchLinkedReminders(sl()))
    ..registerFactory(
      () => TodosController(
        getTodos: sl(),
        watchTodos: sl(),
        addTodo: sl(),
        saveTodo: sl(),
        setTodoDone: sl(),
        linkReminder: sl(),
        removeTodo: sl(),
        clearDoneTodos: sl(),
        newTodoId: sl(),
        draftReminderFromTodo: sl(),
        findLinkedReminder: sl(),
        setLinkedReminderEnabled: sl(),
        removeLinkedReminder: sl(),
        watchLinkedReminders: sl(),
        clock: sl(),
      ),
    );
}
