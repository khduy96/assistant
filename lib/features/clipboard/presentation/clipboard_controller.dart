import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/failure.dart';
import '../../../core/domain/result.dart';
import '../../../core/domain/usecase.dart';
import '../domain/entities/clip_group.dart';
import '../domain/entities/clip_item.dart';
import '../domain/services/clip_filter.dart';
import '../domain/services/clip_lists.dart';
import '../domain/services/clip_ordering.dart';
import '../domain/usecases/add_manual_clip.dart';
import '../domain/usecases/assign_clip_group.dart';
import '../domain/usecases/assign_clips_group.dart';
import '../domain/usecases/clear_temp_clips.dart';
import '../domain/usecases/copy_clip.dart';
import '../domain/usecases/copy_clips.dart';
import '../domain/usecases/create_clip_group.dart';
import '../domain/usecases/delete_clip.dart';
import '../domain/usecases/delete_clip_group.dart';
import '../domain/usecases/delete_clips.dart';
import '../domain/usecases/get_capture_enabled.dart';
import '../domain/usecases/get_clip_groups.dart';
import '../domain/usecases/get_clips.dart';
import '../domain/usecases/purge_expired_clips.dart';
import '../domain/usecases/restore_clip.dart';
import '../domain/usecases/restore_clips.dart';
import '../domain/usecases/save_clip.dart';
import '../domain/usecases/save_clips.dart';
import '../domain/usecases/set_capture_enabled.dart';
import '../domain/usecases/toggle_clip_pin.dart';
import '../domain/usecases/toggle_clips_pin.dart';
import '../domain/usecases/unsave_clip.dart';
import '../domain/usecases/unsave_clips.dart';
import '../domain/usecases/update_clip_content.dart';
import '../domain/usecases/update_clip_group.dart';
import '../domain/usecases/watch_captured_clips.dart';
import '../domain/usecases/watch_remote_clip_changes.dart';

/// The clipboard lists on screen, the search over them and the clips picked
/// for a bulk action.
///
/// Only talks to use cases. What it changes itself it already holds, so it
/// only reloads when a sync wrote something ([WatchRemoteClipChanges]),
/// coalescing a burst of those into one reload. Syncing is not its job: the
/// sync button belongs to the SyncController. The [Clock] only says what
/// "now" is for the card labels.
class ClipboardController extends ChangeNotifier {
  ClipboardController({
    required this._getClips,
    required this._getClipGroups,
    required this._watchRemoteClipChanges,
    required this._watchCapturedClips,
    required this._getCaptureEnabled,
    required this._setCaptureEnabled,
    required this._purgeExpiredClips,
    required this._copyClip,
    required this._copyClips,
    required this._saveClip,
    required this._saveClips,
    required this._unsaveClip,
    required this._unsaveClips,
    required this._toggleClipPin,
    required this._toggleClipsPin,
    required this._assignClipGroup,
    required this._assignClipsGroup,
    required this._updateClipContent,
    required this._addManualClip,
    required this._deleteClip,
    required this._deleteClips,
    required this._restoreClip,
    required this._restoreClips,
    required this._clearTempClips,
    required this._createClipGroup,
    required this._updateClipGroup,
    required this._deleteClipGroup,
    required this._clock,
  });

  final GetClips _getClips;
  final GetClipGroups _getClipGroups;
  final WatchRemoteClipChanges _watchRemoteClipChanges;
  final WatchCapturedClips _watchCapturedClips;
  final GetCaptureEnabled _getCaptureEnabled;
  final SetCaptureEnabled _setCaptureEnabled;
  final PurgeExpiredClips _purgeExpiredClips;
  final CopyClip _copyClip;
  final CopyClips _copyClips;
  final SaveClip _saveClip;
  final SaveClips _saveClips;
  final UnsaveClip _unsaveClip;
  final UnsaveClips _unsaveClips;
  final ToggleClipPin _toggleClipPin;
  final ToggleClipsPin _toggleClipsPin;
  final AssignClipGroup _assignClipGroup;
  final AssignClipsGroup _assignClipsGroup;
  final UpdateClipContent _updateClipContent;
  final AddManualClip _addManualClip;
  final DeleteClip _deleteClip;
  final DeleteClips _deleteClips;
  final RestoreClip _restoreClip;
  final RestoreClips _restoreClips;
  final ClearTempClips _clearTempClips;
  final CreateClipGroup _createClipGroup;
  final UpdateClipGroup _updateClipGroup;
  final DeleteClipGroup _deleteClipGroup;
  final Clock _clock;

  /// Quiet time after the last change a sync wrote before the lists reload,
  /// so a pull that writes hundreds of rows repaints once.
  static const Duration syncReloadDelay = Duration(milliseconds: 300);

  /// Temp clips expire after a day; sweeping hourly is precise enough.
  static const Duration purgeInterval = Duration(hours: 1);

  final List<StreamSubscription<Object?>> _watches = [];
  Timer? _purgeTimer;
  Timer? _syncReloadTimer;
  bool _started = false;
  bool _disposed = false;

  /// Bumped by every load, so a slow one that finishes after a newer one does
  /// not overwrite it.
  int _loads = 0;

  /// Bumped by every change this controller puts on screen itself, so a load
  /// that read the store before that change landed is not shown.
  int _edits = 0;

  /// Every clip, newest first.
  List<ClipItem> _clips = const [];

  /// Every group, in list order.
  List<ClipGroup> _groups = const [];

  ClipFilter _filter = ClipFilter.none;
  bool _loading = true;
  bool _captureEnabled = true;
  Failure? _failure;

  bool get isLoading => _loading;
  bool get captureEnabled => _captureEnabled;
  String get query => _filter.query;
  ClipType? get typeFilter => _filter.type;
  List<ClipGroup> get groups => _groups;

  /// Why the last call failed, or null when it went through.
  Failure? get failure => _failure;

  /// The current time, for the "captured ago" and "expires in" labels.
  DateTime now() => _clock.now();

  /// Temp clips: captured automatically, auto-deleted after one day.
  List<ClipItem> get tempClips => ClipLists.temp(_clips, _filter);

  /// Saved clips (pinned first), what the user explicitly kept.
  List<ClipItem> get savedClips => ClipLists.saved(_clips, _filter);

  List<ClipItem> get pinnedClips => ClipLists.pinned(_clips, _filter);

  List<ClipItem> clipsOfGroup(String groupId) =>
      ClipLists.ofGroup(_clips, groupId, _filter);

  List<ClipItem> get ungroupedSaved =>
      ClipLists.ungroupedSaved(_clips, _filter);

  int countOfGroup(String groupId) =>
      _clips.where((c) => c.groupId == groupId).length;

  int get tempCount => _clips.where((c) => c.isTemp).length;
  int get savedCount => _clips.where((c) => c.isSaved).length;
  int get pinnedCount => _clips.where((c) => c.isPinned).length;

  ClipGroup? groupById(String? id) {
    if (id == null) return null;
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  // --------------------------------------------------------------- lifecycle

  /// Drops expired temp clips, loads the lists, then starts capturing the
  /// clipboard and sweeping expired clips every [purgeInterval]. Safe to call
  /// twice.
  Future<void> init() async {
    if (_started) return;
    _started = true;

    // What this controller writes it already holds; only a sync's writes need
    // a reload.
    final remote = await _watchRemoteClipChanges(const NoParams());
    if (_disposed) return;
    if (remote case Ok(:final value)) {
      _watches.add(value.listen((_) => _scheduleSyncReload()));
    }
    final purged = await _purgeExpiredClips(const NoParams());
    final enabled = await _getCaptureEnabled(const NoParams());
    if (_disposed) return;
    if (enabled case Ok(:final value)) _captureEnabled = value;
    await _reload();
    if (_disposed) return;
    final setupFailure =
        remote.failureOrNull ?? purged.failureOrNull ?? enabled.failureOrNull;
    if (setupFailure != null) _failed(setupFailure);

    switch (await _watchCapturedClips(const NoParams())) {
      case Ok(:final value):
        if (_disposed) return;
        _watches.add(value.listen(_onCaptured));
      case Err(:final failure):
        _failed(failure);
    }
    if (_disposed) return;
    _purgeTimer = Timer.periodic(purgeInterval, (_) => unawaited(_purge()));
  }

  @override
  void dispose() {
    _disposed = true;
    _purgeTimer?.cancel();
    _syncReloadTimer?.cancel();
    for (final watch in _watches) {
      unawaited(watch.cancel());
    }
    super.dispose();
  }

  Future<void> _reload() => _load(++_loads);

  Future<void> _load(int load) async {
    final edits = _edits;
    final clips = await _getClips(const NoParams());
    final groups = await _getClipGroups(const NoParams());
    if (_disposed || load != _loads) return;
    // A change made here landed while reading; what was read may be older.
    if (edits != _edits) return _reload();
    if (clips case Ok(:final value)) _clips = List.unmodifiable(value);
    if (groups case Ok(:final value)) _groups = List.unmodifiable(value);
    _failure = clips.failureOrNull ?? groups.failureOrNull;
    _loading = false;
    _notify();
  }

  /// Coalesces a burst of sync writes into one reload after the last of them.
  void _scheduleSyncReload() {
    if (_disposed) return;
    _syncReloadTimer?.cancel();
    _syncReloadTimer = Timer(syncReloadDelay, () => unawaited(_reload()));
  }

  Future<void> _purge() async {
    switch (await _purgeExpiredClips(const NoParams())) {
      case Ok(:final value) when value > 0:
        await _reload();
      case Ok():
        break;
      case Err(:final failure):
        _failed(failure);
    }
  }

  void _onCaptured(Result<ClipItem> result) {
    switch (result) {
      case Ok(:final value):
        _upsert(value);
        _notify();
      case Err(:final failure):
        _failed(failure);
    }
  }

  // ------------------------------------------------------------------ search

  void setQuery(String value) {
    if (_filter.query == value) return;
    _filter = ClipFilter(query: value, type: _filter.type);
    _notify();
  }

  void setTypeFilter(ClipType? type) {
    if (_filter.type == type) return;
    _filter = ClipFilter(query: _filter.query, type: type);
    _notify();
  }

  Future<void> setCaptureEnabled(bool value) async {
    if (await _setCaptureEnabled(value) case Err(:final failure)) {
      _failed(failure);
      return;
    }
    _captureEnabled = value;
    _notify();
  }

  // ----------------------------------------------------------------- actions
  //
  // Each action takes the clip as stored now: a sync may have replaced the
  // one the caller holds. Each returns false (or nothing) when it failed;
  // [failure] says why.

  /// Puts a clip back on the system clipboard, ready to paste.
  Future<bool> copyToClipboard(ClipItem item) =>
      _applyOne(_copyClip(_current(item)));

  Future<bool> saveClip(ClipItem item, {String? groupId}) =>
      _applyOne(_saveClip((clip: _current(item), groupId: groupId)));

  Future<bool> unsaveClip(ClipItem item) =>
      _applyOne(_unsaveClip(_current(item)));

  /// Pin toggle. Pinning a temp clip also saves it so it survives the purge.
  Future<bool> togglePin(ClipItem item) =>
      _applyOne(_toggleClipPin(_current(item)));

  Future<bool> assignGroup(ClipItem item, String? groupId) =>
      _applyOne(_assignClipGroup((clip: _current(item), groupId: groupId)));

  Future<bool> updateContent(ClipItem item, String content, {String? note}) =>
      _applyOne(
        _updateClipContent((
          clip: _current(item),
          content: content,
          note: note,
        )),
      );

  /// Adds a clip typed by the user; null if it could not be stored.
  Future<ClipItem?> addManual(String content, {String? groupId}) async {
    final result = await _addManualClip((content: content, groupId: groupId));
    if (!await _apply(result, _upsert)) return null;
    return result.valueOrNull;
  }

  /// Deletes a clip; [restoreClip] undoes it.
  Future<bool> deleteClip(ClipItem item) async =>
      _apply(await _deleteClip(item), (_) => _remove({item.id}));

  /// Undo for [deleteClip].
  Future<bool> restoreClip(ClipItem item) => _applyOne(_restoreClip(item));

  Future<bool> clearTemp() async => _apply(
    await _clearTempClips(const NoParams()),
    (_) => _remove({
      for (final c in _clips)
        if (c.isTemp) c.id,
    }),
  );

  // --------------------------------------------------------- multi-selection

  final Set<String> _selected = <String>{};

  bool get isSelecting => _selected.isNotEmpty;
  int get selectedCount => _selected.length;
  bool isSelected(String id) => _selected.contains(id);

  List<ClipItem> get selectedClips =>
      _clips.where((c) => _selected.contains(c.id)).toList();

  void toggleSelection(String id) {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    _notify();
  }

  void selectAll(Iterable<ClipItem> items) {
    _selected.addAll(items.map((c) => c.id));
    _notify();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _notify();
  }

  // A bulk action that went through ends the selection and returns how many
  // clips it touched; one that failed keeps the selection and returns null.

  /// Copies every selected clip as one block, oldest first, one per line.
  /// Returns how many were copied.
  Future<int?> copySelected() async {
    final items = selectedClips;
    if (items.isEmpty) return 0;
    return _applySelection(await _copyClips(items));
  }

  Future<int?> saveSelected({String? groupId}) async => _applySelection(
    await _saveClips((clips: selectedClips, groupId: groupId)),
  );

  /// Moves the saved clips of the selection back to the temp list.
  Future<int?> unsaveSelected() async =>
      _applySelection(await _unsaveClips(selectedClips));

  /// Pins every selection, or unpins it when all of them are already pinned.
  /// Returns how many clips changed and whether they were pinned.
  Future<(int, bool)?> togglePinSelected() async {
    final result = await _toggleClipsPin(selectedClips);
    final count = await _applySelection(switch (result) {
      Ok(:final value) => Ok(value.clips),
      Err(:final failure) => Err(failure),
    });
    final pinned = result.valueOrNull?.pinned;
    return count == null || pinned == null ? null : (count, pinned);
  }

  Future<int?> assignGroupSelected(String? groupId) async => _applySelection(
    await _assignClipsGroup((clips: selectedClips, groupId: groupId)),
  );

  /// Deletes the selection and returns it, so the caller can offer an undo.
  Future<List<ClipItem>?> deleteSelected() async {
    final result = await _deleteClips(selectedClips);
    final ok = await _apply(result, (removed) {
      _remove({for (final c in removed) c.id});
      _selected.clear();
    });
    return ok ? result.valueOrNull : null;
  }

  /// Undo for [deleteSelected].
  Future<bool> restoreClips(List<ClipItem> items) async => _apply(
    await _restoreClips(items),
    (restored) => restored.forEach(_upsert),
  );

  // ------------------------------------------------------------------ groups

  /// Creates a group at the end of the list; null if it could not be stored.
  Future<ClipGroup?> createGroup(String name, int color) async {
    final result = await _createClipGroup((name: name, color: color));
    final ok = await _apply(result, (group) {
      _groups = List.unmodifiable([..._groups, group]);
    });
    return ok ? result.valueOrNull : null;
  }

  /// Renames and recolours [group]; returns it as stored, or null if it
  /// could not be.
  Future<ClipGroup?> renameGroup(
    ClipGroup group,
    String name,
    int color,
  ) async {
    final result = await _updateClipGroup((
      group: group,
      name: name,
      color: color,
    ));
    final ok = await _apply(result, (updated) {
      _groups = List.unmodifiable([
        for (final g in _groups) g.id == updated.id ? updated : g,
      ]);
    });
    return ok ? result.valueOrNull : null;
  }

  /// Deleting a group keeps its clips — they fall back to "chưa phân nhóm".
  Future<bool> deleteGroup(ClipGroup group) async =>
      _apply(await _deleteClipGroup(group), (ungrouped) {
        ungrouped.forEach(_upsert);
        _groups = List.unmodifiable(_groups.where((g) => g.id != group.id));
      });

  // ----------------------------------------------------------------- helpers

  /// The stored version of [clip], or [clip] itself when it is not on the
  /// list (a clip just deleted, say).
  ClipItem _current(ClipItem clip) {
    for (final c in _clips) {
      if (c.id == clip.id) return c;
    }
    return clip;
  }

  Future<bool> _applyOne(Future<Result<ClipItem>> action) async =>
      _apply(await action, _upsert);

  /// Shows what a selection action stored, ends the selection and returns
  /// how many clips it touched; null when it failed.
  Future<int?> _applySelection(Result<List<ClipItem>> result) async {
    final ok = await _apply(result, (clips) {
      clips.forEach(_upsert);
      _selected.clear();
    });
    return ok ? result.valueOrNull?.length : null;
  }

  /// Puts the value of an `Ok` [result] on screen through [show] and
  /// repaints once. On an `Err`, reloads (the action may have stored part of
  /// its work) and records the failure. Returns whether it was `Ok`.
  Future<bool> _apply<T>(Result<T> result, void Function(T value) show) async {
    if (_disposed) return result.isOk;
    switch (result) {
      case Ok(:final value):
        show(value);
        _edits++;
        _notify();
        return true;
      case Err(:final failure):
        await _reload();
        _failed(failure);
        return false;
    }
  }

  /// Records [failure] and tells the listeners.
  void _failed(Failure failure) {
    _failure = failure;
    _notify();
  }

  void _upsert(ClipItem item) {
    final next = [..._clips];
    final index = next.indexWhere((c) => c.id == item.id);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.insert(0, item);
    }
    next.sort(ClipOrdering.newestFirst);
    _clips = List.unmodifiable(next);
    _edits++;
  }

  void _remove(Set<String> ids) {
    _clips = List.unmodifiable(_clips.where((c) => !ids.contains(c.id)));
    _edits++;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
