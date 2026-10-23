import 'package:get_it/get_it.dart';

import '../../core/data/app_database.dart';
import '../../core/data/sqlite_sync_state_store.dart';
import '../../core/data/system_clock.dart';
import '../../core/data/uuid_id_generator.dart';
import '../../core/domain/clock.dart';
import '../../core/domain/id_generator.dart';
import '../../core/sync/data/parse_config.dart';
import '../../core/sync/data/parse_sync_engine.dart';
import '../../core/sync/domain/entities/sync_settings.dart';
import '../../core/sync/domain/sync_channel.dart';
import '../../core/sync/domain/sync_engine.dart';
import '../../core/sync/domain/sync_state_store.dart';
import '../../core/sync/domain/usecases/get_month_requests.dart';
import '../../core/sync/domain/usecases/get_sync_settings.dart';
import '../../core/sync/domain/usecases/has_pending_changes.dart';
import '../../core/sync/domain/usecases/run_sync.dart';
import '../../core/sync/domain/usecases/watch_local_changes.dart';
import '../../core/sync/presentation/sync_controller.dart';
import '../../features/clipboard/clipboard_injection.dart';
import '../../features/clipboard/data/sync/clip_group_sync_collection.dart';
import '../../features/clipboard/data/sync/clip_sync_collection.dart';
import '../../features/notes/data/sync/note_sync_collection.dart';
import '../../features/notes/notes_injection.dart';
import '../../features/p2p/p2p_injection.dart';
import '../../features/p2p/presentation/p2p_files.dart';
import '../../features/reminders/reminders_injection.dart';
import '../../features/todos/data/sync/todo_sync_collection.dart';
import '../../features/todos/domain/repositories/linked_reminder_repository.dart';
import '../../features/todos/presentation/todo_reminder_editor.dart';
import '../../features/todos/todos_injection.dart';
import 'bridges/linked_reminder_bridge.dart';
import 'bridges/p2p_files_bridge.dart';
import 'bridges/todo_reminder_editor_bridge.dart';

/// Registers everything the app resolves from [sl]: the core services first,
/// then each migrated feature, then the sync that spans them.
///
/// The app passes `GetIt.instance`; tests pass `GetIt.asNewInstance()`.
void configureDependencies(GetIt sl) {
  sl
    ..registerLazySingleton<Clock>(() => const SystemClock())
    ..registerLazySingleton<IdGenerator>(() => const UuidIdGenerator());
  registerNotes(sl);
  registerReminders(sl);
  _registerReminderBridges(sl);
  registerTodos(sl);
  registerClipboard(sl);
  registerP2p(sl);
  // The "Gửi tệp" tab reaches this machine's files and file manager here.
  sl.registerLazySingleton<P2pFiles>(() => const P2pFilesBridge());
  _registerSync(sl);
}

/// Fills the app's own locator, once, before the first frame. The app shell
/// resolves what it shows from the locator returned here.
GetIt configureAppDependencies() {
  final sl = GetIt.instance;
  configureDependencies(sl);
  return sl;
}

/// One engine and one [SyncController] for clips, todos and notes: one
/// button, one timer and one status for everything the app keeps.
///
/// Groups before clips in the shared channel, so a pulled clip finds its
/// group in place; then the todos, then the notes. That is the push order
/// too.
void _registerSync(GetIt sl) {
  sl
    ..registerLazySingleton(() => ParseConfig.fromEnvironment())
    ..registerLazySingleton<SyncStateStore>(
      () => SqliteSyncStateStore(AppDatabase.instance),
    )
    ..registerLazySingleton<SyncEngine>(
      () => ParseSyncEngine(
        config: sl(),
        state: sl(),
        clock: sl(),
        channels: [
          SyncChannel.shared([
            sl<ClipGroupSyncCollection>(),
            sl<ClipSyncCollection>(),
          ]),
          SyncChannel.single(sl<TodoSyncCollection>()),
          SyncChannel.single(sl<NoteSyncCollection>()),
        ],
      ),
    )
    // Fixed at build time, so known before the controller starts: the sync
    // button reads it to be enabled from the first frame, as it always was.
    ..registerLazySingleton<SyncSettings>(() => sl<SyncEngine>().settings)
    ..registerLazySingleton(() => RunSync(sl()))
    ..registerLazySingleton(() => HasPendingChanges(sl()))
    ..registerLazySingleton(() => GetMonthRequests(sl()))
    ..registerLazySingleton(() => WatchLocalChanges(sl()))
    ..registerLazySingleton(() => GetSyncSettings(sl()))
    // A single controller: it owns the push and fallback timers.
    ..registerLazySingleton(
      () => SyncController(
        runSync: sl(),
        hasPendingChanges: sl(),
        getMonthRequests: sl(),
        watchLocalChanges: sl(),
        getSyncSettings: sl(),
        clock: sl(),
      ),
    );
}

/// The todo list reaches the reminders only through these two bridges, both
/// over the `RemindersController` the app shell shows: one queue of alerts
/// and one OS alarm schedule, whoever edits a reminder.
void _registerReminderBridges(GetIt sl) {
  sl
    ..registerLazySingleton<LinkedReminderRepository>(
      () => LinkedReminderBridge(sl()),
    )
    ..registerLazySingleton<TodoReminderEditor>(
      () => TodoReminderEditorBridge(sl()),
    );
}
