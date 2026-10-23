import 'package:get_it/get_it.dart';

import 'data/datasources/note_local_data_source.dart';
import 'data/repositories/note_repository_impl.dart';
import 'data/sync/note_sync_collection.dart';
import 'domain/repositories/note_repository.dart';
import 'domain/usecases/delete_note.dart';
import 'domain/usecases/get_notes.dart';
import 'domain/usecases/new_note.dart';
import 'domain/usecases/save_note.dart';
import 'domain/usecases/search_notes.dart';
import 'domain/usecases/set_note_pinned.dart';
import 'domain/usecases/watch_notes.dart';
import 'presentation/notes_controller.dart';

/// Registers the notes feature in [sl]. Expects a `Clock` and an
/// `IdGenerator` to be registered already.
///
/// [NoteRepositoryImpl] is one singleton seen under two types: the use cases
/// get it as [NoteRepository], while the app shell needs the concrete class
/// to load the file at startup, and [NoteSyncCollection] to reach the sync
/// state the interface hides.
void registerNotes(GetIt sl) {
  sl
    ..registerLazySingleton(() => NoteLocalDataSource(sl()))
    ..registerLazySingleton(() => NoteRepositoryImpl(sl()))
    ..registerLazySingleton<NoteRepository>(() => sl<NoteRepositoryImpl>())
    ..registerLazySingleton(() => NoteSyncCollection(sl(), sl()))
    ..registerLazySingleton(() => GetNotes(sl()))
    ..registerLazySingleton(() => SearchNotes(sl()))
    ..registerLazySingleton(() => SaveNote(sl(), sl()))
    ..registerLazySingleton(() => DeleteNote(sl()))
    ..registerLazySingleton(() => SetNotePinned(sl(), sl()))
    ..registerLazySingleton(() => WatchNotes(sl()))
    ..registerLazySingleton(() => NewNote(sl(), sl()))
    ..registerFactory(
      () => NotesController(
        getNotes: sl(),
        searchNotes: sl(),
        saveNote: sl(),
        deleteNote: sl(),
        setNotePinned: sl(),
        watchNotes: sl(),
        newNote: sl(),
      ),
    );
}
