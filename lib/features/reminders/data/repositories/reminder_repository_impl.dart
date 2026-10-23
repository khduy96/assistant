import 'dart:async';

import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../domain/entities/reminder.dart';
import '../../domain/repositories/reminder_repository.dart';
import '../datasources/reminder_local_data_source.dart';
import '../mappers/reminder_mapper.dart';

/// Keeps the reminders in memory and in `reminders.json`.
///
/// The ticker reads them once a second, so reads never touch the disk. Every
/// write changes the memory first and then rewrites the whole file; when that
/// write fails the memory keeps the change, so a handled alert is not raised
/// again, and the caller gets a [StorageFailure].
class ReminderRepositoryImpl implements ReminderRepository {
  ReminderRepositoryImpl(this._source);

  final ReminderLocalDataSource _source;

  /// In storage order, which is the order they were first saved in.
  final List<Reminder> _reminders = [];

  Future<void>? _loading;

  final _changes = StreamController<void>.broadcast();

  /// Reads `reminders.json`. Same as [ensureLoaded]; the app awaits this once
  /// at startup.
  Future<void> init() => ensureLoaded();

  /// Loads the file on the first call; later calls wait for that load. A
  /// load that throws is retried on the next call.
  Future<void> ensureLoaded() =>
      _loading ??= _load().catchError((Object e, StackTrace s) {
        // Runs after [_loading] was set, even when the source threw right away,
        // so the reset sticks.
        _loading = null;
        Error.throwWithStackTrace(e, s);
      });

  Future<void> _load() async {
    final saved = await _source.load();
    _reminders
      ..clear()
      ..addAll(saved.map(ReminderMapper.toEntity));
    _emit();
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Result<List<Reminder>>> getAll() => _guard('read', () async {
    await ensureLoaded();
    return List<Reminder>.unmodifiable(_reminders);
  });

  @override
  Future<Result<Reminder?>> find(String id) => _guard('read', () async {
    await ensureLoaded();
    final i = _indexOf(id);
    return i == -1 ? null : _reminders[i];
  });

  @override
  Future<Result<void>> save(Reminder reminder) => saveAll([reminder]);

  @override
  Future<Result<void>> saveAll(Iterable<Reminder> reminders) =>
      _guard('save', () async {
        await ensureLoaded();
        final incoming = reminders.toList();
        if (incoming.isEmpty) return;
        for (final r in incoming) {
          final i = _indexOf(r.id);
          if (i == -1) {
            _reminders.add(r);
          } else {
            _reminders[i] = r;
          }
        }
        await _persist();
      });

  @override
  Future<Result<void>> delete(String id) => _guard('delete', () async {
    await ensureLoaded();
    final i = _indexOf(id);
    if (i == -1) return;
    _reminders.removeAt(i);
    await _persist();
  });

  Future<void> dispose() => _changes.close();

  int _indexOf(String id) => _reminders.indexWhere((r) => r.id == id);

  /// Writes the file, then tells the listeners. They hear about the change
  /// even when the write fails: the memory, which they read, has changed.
  Future<void> _persist() async {
    try {
      await _source.save([
        for (final r in _reminders) ReminderMapper.toModel(r),
      ]);
    } finally {
      _emit();
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<Result<T>> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(StorageFailure('Could not $action reminders', cause: e));
    }
  }
}
