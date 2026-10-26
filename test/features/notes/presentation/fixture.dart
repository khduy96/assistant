import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/domain/repositories/note_repository.dart';
import 'package:event_notice/features/notes/domain/usecases/delete_note.dart';
import 'package:event_notice/features/notes/domain/usecases/get_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/new_note.dart';
import 'package:event_notice/features/notes/domain/usecases/save_note.dart';
import 'package:event_notice/features/notes/domain/usecases/search_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/set_note_pinned.dart';
import 'package:event_notice/features/notes/domain/usecases/watch_notes.dart';
import 'package:event_notice/features/notes/presentation/notes_controller.dart';

import '../domain/fakes.dart';

final t0 = DateTime(2026, 10, 22, 9, 30);

/// [t0] plus [m] minutes.
DateTime at(int m) => t0.add(Duration(minutes: m));

Note note(
  String id, {
  String title = '',
  String body = '',
  bool pinned = false,
  bool markdown = false,
  NoteColor color = NoteColor.none,
  int createdMin = 0,
  int updatedMin = 0,
}) => Note(
  id: id,
  title: title,
  body: body,
  pinned: pinned,
  markdown: markdown,
  color: color,
  createdAt: at(createdMin),
  updatedAt: at(updatedMin),
);

/// A controller wired to [repo] through the real use cases, with the time
/// taken from [clock] and new ids from [ids]. Any use case can be swapped for
/// a fake.
NotesController controllerFor(
  NoteRepository repo, {
  required Clock clock,
  IdGenerator? ids,
  GetNotes? getNotes,
  NewNote? newNote,
}) => NotesController(
  getNotes: getNotes ?? GetNotes(repo),
  searchNotes: SearchNotes(repo),
  saveNote: SaveNote(repo, clock),
  deleteNote: DeleteNote(repo),
  setNotePinned: SetNotePinned(repo, clock),
  watchNotes: WatchNotes(repo),
  newNote: newNote ?? NewNote(ids ?? SequentialIdGenerator(), clock),
);
