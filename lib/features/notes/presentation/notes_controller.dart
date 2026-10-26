import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/failure.dart';
import '../../../core/domain/result.dart';
import '../../../core/domain/usecase.dart';
import '../domain/entities/note.dart';
import '../domain/usecases/delete_note.dart';
import '../domain/usecases/get_notes.dart';
import '../domain/usecases/new_note.dart';
import '../domain/usecases/save_note.dart';
import '../domain/usecases/search_notes.dart';
import '../domain/usecases/set_note_pinned.dart';
import '../domain/usecases/watch_notes.dart';

/// What the notes tab shows: every note, the current search and its matches.
///
/// Only talks to use cases. Listens to [WatchNotes] and reloads on every
/// event, so a change a sync applied shows up without anyone asking.
class NotesController extends ChangeNotifier {
  NotesController({
    required this._getNotes,
    required this._searchNotes,
    required this._saveNote,
    required this._deleteNote,
    required this._setNotePinned,
    required this._watchNotes,
    required this._newNote,
  });

  final GetNotes _getNotes;
  final SearchNotes _searchNotes;
  final SaveNote _saveNote;
  final DeleteNote _deleteNote;
  final SetNotePinned _setNotePinned;
  final WatchNotes _watchNotes;
  final NewNote _newNote;

  List<Note> _notes = const [];
  List<Note> _results = const [];
  String _query = '';
  Failure? _failure;

  StreamSubscription<void>? _watch;
  bool _started = false;
  bool _disposed = false;

  /// Bumped by every load, so a slow one that finishes after a newer one
  /// does not overwrite it.
  int _loads = 0;

  /// Every note, pinned first, then most recently edited.
  List<Note> get notes => _notes;

  /// The notes matching [query], in the same order. All of them while the
  /// query is blank.
  List<Note> get results => _results;

  String get query => _query;

  int get count => _notes.length;

  /// Why the last call failed, or null when it went through.
  Failure? get failure => _failure;

  Note? noteById(String id) => _notes.where((n) => n.id == id).firstOrNull;

  /// Starts listening for changes and loads the list. Safe to call twice.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    final watched = await _watchNotes(const NoParams());
    if (_disposed) return;
    switch (watched) {
      case Ok(:final value):
        _watch = value.listen((_) => _reload());
      case Err(:final failure):
        _failure = failure;
    }
    await _reload();
  }

  /// Narrows [results] to the notes containing [query].
  Future<void> setQuery(String query) async {
    if (query == _query) return;
    _query = query;
    _notify();
    await _reload();
  }

  /// A blank note with a fresh id, not stored yet. Null if it could not be
  /// made.
  Future<Note?> newNote() async {
    final result = await _newNote(const NoParams());
    if (_failed(result)) return null;
    return result.valueOrNull;
  }

  /// Adds [note], or replaces the one with the same id. An empty note is
  /// deleted instead.
  Future<void> save(Note note) => _run(_saveNote(note));

  Future<void> delete(String id) => _run(_deleteNote(id));

  Future<void> setPinned(Note note, bool pinned) =>
      _run(_setNotePinned((note: note, pinned: pinned)));

  /// Waits for [action], then reloads so the list is current when the caller
  /// resumes. The watch stream reloads too; the newer load simply wins.
  Future<void> _run(Future<Result<void>> action) async {
    if (_failed(await action)) return;
    await _reload();
  }

  /// Records the failure of [result], if any, and tells the listeners.
  bool _failed(Result<Object?> result) {
    if (result case Err(:final failure)) {
      _failure = failure;
      _notify();
      return true;
    }
    return false;
  }

  Future<void> _reload() async {
    final load = ++_loads;
    final query = _query;
    final all = await _getNotes(const NoParams());
    final found = query.trim().isEmpty ? all : await _searchNotes(query);
    if (_disposed || load != _loads) return;

    if (all case Ok(:final value)) _notes = List.unmodifiable(value);
    if (found case Ok(:final value)) _results = List.unmodifiable(value);
    _failure = all.failureOrNull ?? found.failureOrNull;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
    super.dispose();
  }
}
