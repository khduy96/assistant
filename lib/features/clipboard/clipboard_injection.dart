import 'package:get_it/get_it.dart';

import '../../core/data/app_database.dart';
import '../../core/domain/id_generator.dart';
import 'data/clip_id_generator.dart';
import 'data/datasources/clip_local_data_source.dart';
import 'data/datasources/clipboard_watcher.dart';
import 'data/repositories/clipboard_repository_impl.dart';
import 'data/sync/clip_group_sync_collection.dart';
import 'data/sync/clip_sync_collection.dart';
import 'domain/ports/clipboard_source.dart';
import 'domain/repositories/clipboard_repository.dart';
import 'domain/usecases/add_manual_clip.dart';
import 'domain/usecases/assign_clip_group.dart';
import 'domain/usecases/assign_clips_group.dart';
import 'domain/usecases/capture_clip.dart';
import 'domain/usecases/clear_temp_clips.dart';
import 'domain/usecases/copy_clip.dart';
import 'domain/usecases/copy_clips.dart';
import 'domain/usecases/create_clip_group.dart';
import 'domain/usecases/delete_clip.dart';
import 'domain/usecases/delete_clip_group.dart';
import 'domain/usecases/delete_clips.dart';
import 'domain/usecases/get_capture_enabled.dart';
import 'domain/usecases/get_clip_groups.dart';
import 'domain/usecases/get_clips.dart';
import 'domain/usecases/purge_expired_clips.dart';
import 'domain/usecases/restore_clip.dart';
import 'domain/usecases/restore_clips.dart';
import 'domain/usecases/save_clip.dart';
import 'domain/usecases/save_clips.dart';
import 'domain/usecases/set_capture_enabled.dart';
import 'domain/usecases/toggle_clip_pin.dart';
import 'domain/usecases/toggle_clips_pin.dart';
import 'domain/usecases/unsave_clip.dart';
import 'domain/usecases/unsave_clips.dart';
import 'domain/usecases/update_clip_content.dart';
import 'domain/usecases/update_clip_group.dart';
import 'domain/usecases/watch_captured_clips.dart';
import 'domain/usecases/watch_remote_clip_changes.dart';
import 'presentation/clipboard_controller.dart';

/// Name of the [IdGenerator] that hands out clip and group ids. The default
/// one makes UUIDs; clips and groups keep the `<micro>-<salt>` ids they
/// already have on disk and on other devices.
const String clipIdsName = 'clipIds';

/// Registers the clipboard feature in [sl]. Expects a `Clock` to be
/// registered already.
///
/// [ClipboardRepositoryImpl] is one singleton seen under two types: the use
/// cases get it as [ClipboardRepository], while the two sync collections need
/// the sync state the interface hides, and the app shell closes it. Likewise
/// [ClipboardWatcher] is the [ClipboardSource] of the use cases, and the app
/// shell disposes it.
void registerClipboard(GetIt sl) {
  sl
    ..registerLazySingleton(() => ClipLocalDataSource(AppDatabase.instance))
    ..registerLazySingleton(() => ClipboardRepositoryImpl(sl(), sl()))
    ..registerLazySingleton<ClipboardRepository>(
      () => sl<ClipboardRepositoryImpl>(),
    )
    ..registerLazySingleton(() => ClipboardWatcher())
    ..registerLazySingleton<ClipboardSource>(() => sl<ClipboardWatcher>())
    ..registerLazySingleton<IdGenerator>(
      () => ClipIdGenerator(sl()),
      instanceName: clipIdsName,
    )
    ..registerLazySingleton(() => ClipGroupSyncCollection(sl(), sl()))
    ..registerLazySingleton(() => ClipSyncCollection(sl(), sl()))
    ..registerLazySingleton(() => GetClips(sl()))
    ..registerLazySingleton(() => GetClipGroups(sl()))
    ..registerLazySingleton(() => WatchRemoteClipChanges(sl()))
    ..registerLazySingleton(
      () => CaptureClip(sl(), sl(instanceName: clipIdsName), sl()),
    )
    ..registerLazySingleton(() => WatchCapturedClips(sl(), sl()))
    ..registerLazySingleton(() => GetCaptureEnabled(sl()))
    ..registerLazySingleton(() => SetCaptureEnabled(sl()))
    ..registerLazySingleton(() => PurgeExpiredClips(sl(), sl()))
    ..registerLazySingleton(() => CopyClip(sl(), sl(), sl()))
    ..registerLazySingleton(() => CopyClips(sl(), sl(), sl()))
    ..registerLazySingleton(() => SaveClip(sl(), sl()))
    ..registerLazySingleton(() => SaveClips(sl(), sl()))
    ..registerLazySingleton(() => UnsaveClip(sl(), sl()))
    ..registerLazySingleton(() => UnsaveClips(sl(), sl()))
    ..registerLazySingleton(() => ToggleClipPin(sl(), sl()))
    ..registerLazySingleton(() => ToggleClipsPin(sl(), sl()))
    ..registerLazySingleton(() => AssignClipGroup(sl(), sl()))
    ..registerLazySingleton(() => AssignClipsGroup(sl(), sl()))
    ..registerLazySingleton(() => UpdateClipContent(sl(), sl()))
    ..registerLazySingleton(
      () => AddManualClip(sl(), sl(instanceName: clipIdsName), sl()),
    )
    ..registerLazySingleton(() => DeleteClip(sl()))
    ..registerLazySingleton(() => DeleteClips(sl()))
    ..registerLazySingleton(() => RestoreClip(sl(), sl()))
    ..registerLazySingleton(() => RestoreClips(sl(), sl()))
    ..registerLazySingleton(() => ClearTempClips(sl()))
    ..registerLazySingleton(
      () => CreateClipGroup(sl(), sl(instanceName: clipIdsName), sl()),
    )
    ..registerLazySingleton(() => UpdateClipGroup(sl(), sl()))
    ..registerLazySingleton(() => DeleteClipGroup(sl(), sl()))
    ..registerFactory(
      () => ClipboardController(
        getClips: sl(),
        getClipGroups: sl(),
        watchRemoteClipChanges: sl(),
        watchCapturedClips: sl(),
        getCaptureEnabled: sl(),
        setCaptureEnabled: sl(),
        purgeExpiredClips: sl(),
        copyClip: sl(),
        copyClips: sl(),
        saveClip: sl(),
        saveClips: sl(),
        unsaveClip: sl(),
        unsaveClips: sl(),
        toggleClipPin: sl(),
        toggleClipsPin: sl(),
        assignClipGroup: sl(),
        assignClipsGroup: sl(),
        updateClipContent: sl(),
        addManualClip: sl(),
        deleteClip: sl(),
        deleteClips: sl(),
        restoreClip: sl(),
        restoreClips: sl(),
        clearTempClips: sl(),
        createClipGroup: sl(),
        updateClipGroup: sl(),
        deleteClipGroup: sl(),
        clock: sl(),
      ),
    );
}
