import 'dart:async';

import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../../../core/sync/domain/sync_collection.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';
import '../datasources/note_local_data_source.dart';
import '../mappers/note_mapper.dart';
import '../models/note_model.dart';

/// Keeps the notes in memory and on disk, along with their sync state and the
/// tombstones of deleted notes.
///
/// The user's edits come in through [NoteRepository]; the sync engine's come
/// in through `NoteSyncCollection`, which uses the members below the
/// "Sync side" mark. Both fire [changes]; only the user's fire
/// [localChanges], so applying a pull never schedules a push of its own.
class NoteRepositoryImpl implements NoteRepository {
  NoteRepositoryImpl(this._source);

  final NoteLocalDataSource _source;
  final List<NoteModel> _notes = [];

  /// Notes deleted here whose Back4App object is still waiting to be removed.
  final List<SyncTombstone> _deleted = [];

  Future<void>? _loading;
  bool _loaded = false;

  final _changes = StreamController<void>.broadcast();
  final _localChanges = StreamController<void>.broadcast();

  /// Reads `notes.json`. Same as [ensureLoaded]; the app awaits this once at
  /// startup, before the sync engine first looks at the notes.
  Future<void> init() => ensureLoaded();

  /// Loads the file on the first call; later calls wait for that load. A
  /// load that throws is retried on the next call.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final saved = await _source.load();
      _notes
        ..clear()
        ..addAll(saved.items);
      _deleted
        ..clear()
        ..addAll(saved.deleted);
      _loaded = true;
    } catch (_) {
      _loading = null;
      rethrow;
    }
    _emit(local: false);
  }

  @override
  Stream<void> get changes => _changes.stream;

  /// Fires after a change made on this device through [save] or [delete],
  /// so the sync engine can push it soon. Never fires for a change a sync
  /// applied.
  Stream<void> get localChanges => _localChanges.stream;

  @override
  Future<Result<List<Note>>> getAll() => _guard('read', () async {
    await ensureLoaded();
    return [for (final m in _notes) NoteMapper.toEntity(m)];
  });

  @override
  Future<Result<void>> save(Note note) => _guard('save', () async {
    await ensureLoaded();
    final i = _indexOf(note.id);
    final model = NoteMapper.toModel(note, stored: i == -1 ? null : _notes[i]);
    if (i == -1) {
      _notes.add(model);
    } else {
      _notes[i] = model;
    }
    await _persist(local: true);
  });

  @override
  Future<Result<void>> delete(String id) => _guard('delete', () async {
    await ensureLoaded();
    final i = _indexOf(id);
    if (i == -1) return;
    final gone = _notes.removeAt(i);
    // Never pushed: there is nothing on the server to delete.
    final remoteId = gone.remoteId;
    if (remoteId != null) {
      _deleted.add(SyncTombstone(localId: gone.id, remoteId: remoteId));
    }
    await _persist(local: true);
  });

  Future<void> dispose() async {
    await _changes.close();
    await _localChanges.close();
  }

  // Sync side. Read these only after [ensureLoaded]. The writers change the
  // memory synchronously, before their first await, so a check made just
  // before calling one still holds when it lands.

  /// Every stored note with its sync state, in storage order.
  List<NoteModel> get models => List.unmodifiable(_notes);

  /// Deleted notes still waiting for their server object to go.
  List<SyncTombstone> get tombstones => List.unmodifiable(_deleted);

  /// Adds [model], or replaces the stored note with the same id, as it is.
  Future<void> putFromSync(NoteModel model) {
    _checkLoaded();
    final i = _indexOf(model.id);
    if (i == -1) {
      _notes.add(model);
    } else {
      _notes[i] = model;
    }
    return _persist(local: false);
  }

  /// Drops the note with [id] without queueing a delete to the server.
  Future<void> removeFromSync(String id) {
    _checkLoaded();
    _notes.removeWhere((n) => n.id == id);
    return _persist(local: false);
  }

  /// Forgets the tombstone whose server object is [remoteId], once that
  /// object is gone.
  Future<void> clearTombstone(String remoteId) {
    _checkLoaded();
    _deleted.removeWhere((t) => t.remoteId == remoteId);
    return _persist(local: false);
  }

  int _indexOf(String id) => _notes.indexWhere((n) => n.id == id);

  void _checkLoaded() {
    if (!_loaded) {
      throw StateError('NoteRepositoryImpl used before ensureLoaded()');
    }
  }

  /// Writes the file, then tells the listeners. They hear about the change
  /// even when the write fails: the memory, which they read, has changed.
  Future<void> _persist({required bool local}) async {
    try {
      await _source.save(_notes, _deleted);
    } finally {
      _emit(local: local);
    }
  }

  void _emit({required bool local}) {
    if (!_changes.isClosed) _changes.add(null);
    if (local && !_localChanges.isClosed) _localChanges.add(null);
  }

  Future<Result<T>> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(StorageFailure('Could not $action notes', cause: e));
    }
  }
}
