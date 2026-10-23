import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/domain/repositories/note_repository.dart';

/// A clock that stays at [current] until a test moves it.
class FakeClock implements Clock {
  FakeClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

/// Hands out `id-1`, `id-2`, ... in order.
class SequentialIdGenerator implements IdGenerator {
  int _next = 1;

  @override
  String newId() => 'id-${_next++}';
}

/// Keeps notes in a map. Set [failure] to make every call return it.
class InMemoryNoteRepository implements NoteRepository {
  InMemoryNoteRepository([Iterable<Note> initial = const []]) {
    for (final note in initial) {
      _notes[note.id] = note;
    }
  }

  final Map<String, Note> _notes = {};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Ids passed to [delete], in call order.
  final List<String> deleted = [];

  Failure? failure;

  Note? operator [](String id) => _notes[id];

  int get length => _notes.length;

  @override
  Future<Result<List<Note>>> getAll() async {
    if (failure case final f?) return Err(f);
    return Ok(_notes.values.toList());
  }

  @override
  Future<Result<void>> save(Note note) async {
    if (failure case final f?) return Err(f);
    _notes[note.id] = note;
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    if (failure case final f?) return Err(f);
    deleted.add(id);
    if (_notes.remove(id) != null) _changes.add(null);
    return const Ok(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();
}
