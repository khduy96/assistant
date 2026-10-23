import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/ports/clipboard_source.dart';
import 'package:event_notice/features/clipboard/domain/repositories/clipboard_repository.dart';

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

/// Keeps clips and groups in maps and plays the data layer's sync
/// bookkeeping as documented on [ClipboardRepository], so a test can see what
/// a real repository would record: server ids, rows ahead of the server, and
/// server deletes waiting to go out. Set [failure] to make every call return
/// it.
class InMemoryClipboardRepository implements ClipboardRepository {
  InMemoryClipboardRepository({
    Iterable<ClipItem> clips = const [],
    Iterable<ClipGroup> groups = const [],
  }) {
    for (final clip in clips) {
      _clips[clip.id] = clip;
    }
    for (final group in groups) {
      _groups[group.id] = group;
    }
  }

  final Map<String, ClipItem> _clips = {};
  final Map<String, ClipGroup> _groups = {};
  final _remote = StreamController<void>.broadcast(sync: true);

  /// Server object id of each clip that reached the server, by clip id.
  final Map<String, String> remoteIds = {};

  /// Ids of clips and groups holding edits the server has not seen.
  final Set<String> dirty = {};

  /// Server ids queued for deletion, oldest first.
  final List<String> pendingDeletes = [];

  /// Every call that would write, in order, e.g. `saveClip(c1, share)`.
  final List<String> log = [];

  /// Server ids of clips removed by [deleteClips], kept for [restoreClip].
  final Map<String, String> _deletedRemoteIds = {};

  Failure? failure;

  ClipItem? clip(String id) => _clips[id];

  ClipGroup? group(String id) => _groups[id];

  List<ClipItem> get clips => _clips.values.toList();

  /// Calls to write methods that asked for a push.
  int get pushRequests => log.where((l) => l.endsWith(', share)')).length;

  /// Pretends a sync wrote something.
  void emitRemoteChange() => _remote.add(null);

  @override
  Future<Result<List<ClipItem>>> getClips() async {
    if (failure case final f?) return Err(f);
    return Ok(_clips.values.toList());
  }

  @override
  Future<Result<ClipItem?>> findClipByContent(String content) async {
    if (failure case final f?) return Err(f);
    for (final clip in _clips.values) {
      if (clip.content == content) return Ok(clip);
    }
    return const Ok(null);
  }

  @override
  Future<Result<void>> saveClip(ClipItem clip, {bool share = true}) async {
    if (failure case final f?) return Err(f);
    log.add('saveClip(${clip.id}${share ? ', share' : ''})');
    _clips[clip.id] = clip;
    dirty.add(clip.id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> recordCopy(ClipItem clip) async {
    if (failure case final f?) return Err(f);
    log.add('recordCopy(${clip.id})');
    final stored = _clips[clip.id];
    if (stored != null) {
      _clips[clip.id] = stored.copyWith(
        copiedAt: clip.copiedAt,
        copyCount: clip.copyCount,
      );
    }
    return const Ok(null);
  }

  @override
  Future<Result<void>> detachFromServer(String id) async {
    if (failure case final f?) return Err(f);
    log.add('detachFromServer($id)');
    final remoteId = remoteIds.remove(id);
    if (remoteId != null) pendingDeletes.add(remoteId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteClips(
    Iterable<String> ids, {
    bool share = true,
  }) async {
    if (failure case final f?) return Err(f);
    log.add('deleteClips(${ids.join(' ')}${share ? ', share' : ''})');
    for (final id in ids) {
      _clips.remove(id);
      dirty.remove(id);
      final remoteId = remoteIds.remove(id);
      if (remoteId != null) {
        pendingDeletes.add(remoteId);
        _deletedRemoteIds[id] = remoteId;
      }
    }
    return const Ok(null);
  }

  @override
  Future<Result<void>> restoreClip(ClipItem clip) async {
    if (failure case final f?) return Err(f);
    log.add('restoreClip(${clip.id}, share)');
    _clips[clip.id] = clip;
    dirty.add(clip.id);
    final remoteId = _deletedRemoteIds.remove(clip.id);
    if (remoteId != null) {
      remoteIds[clip.id] = remoteId;
      pendingDeletes.remove(remoteId);
    }
    return const Ok(null);
  }

  @override
  Future<Result<List<ClipGroup>>> getGroups() async {
    if (failure case final f?) return Err(f);
    return Ok(_groups.values.toList());
  }

  @override
  Future<Result<void>> saveGroup(ClipGroup group) async {
    if (failure case final f?) return Err(f);
    log.add('saveGroup(${group.id}, share)');
    _groups[group.id] = group;
    dirty.add(group.id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteGroup(String id) async {
    if (failure case final f?) return Err(f);
    log.add('deleteGroup($id, share)');
    _groups.remove(id);
    dirty.remove(id);
    return const Ok(null);
  }

  @override
  Stream<void> get remoteChanges => _remote.stream;

  Future<void> dispose() => _remote.close();
}

/// A system clipboard a test drives by hand: [capture] feeds [captures], and
/// [write] records what the app put on the clipboard.
class FakeClipboardSource implements ClipboardSource {
  final _captures = StreamController<String>();

  /// Texts passed to [write], in order.
  final List<String> written = [];

  /// Set to make [write] return it.
  Failure? failure;

  @override
  bool isEnabled = true;

  /// Whether something is listening to [captures], i.e. the clipboard is
  /// being watched.
  bool get watching => _captures.hasListener;

  /// Pretends the user copied [text] somewhere.
  void capture(String text) => _captures.add(text);

  @override
  Stream<String> get captures => _captures.stream;

  @override
  void setEnabled(bool enabled) => isEnabled = enabled;

  @override
  Future<Result<void>> write(String text) async {
    if (failure case final f?) return Err(f);
    written.add(text);
    return const Ok(null);
  }

  /// Closes [captures]. Not awaited: on a stream nobody listens to, the
  /// close only completes once someone does.
  void dispose() => unawaited(_captures.close());
}
