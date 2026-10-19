import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../services/sync/sync_collection.dart';
import '../data/clip_repository.dart';
import '../models/clip_group.dart';
import '../models/clip_item.dart';
import '../services/clipboard_watcher.dart';
import '../sync/parse_config.dart';
import '../sync/sync_service.dart';

class ClipboardStore extends ChangeNotifier {
  ClipboardStore({ClipRepository? repository, this.extraCollections = const []})
      : _repo = repository ?? ClipRepository() {
    _watcher = ClipboardWatcher(onCapture: _onCaptured);
  }

  /// Lists outside the clipboard that ride along on the same sync cycle: the
  /// todo list and the notes. One button, one timer, one status for all of it.
  final List<SyncCollection> extraCollections;

  final ClipRepository _repo;
  late final ClipboardWatcher _watcher;
  late SyncService _sync;
  Timer? _purgeTimer;
  Timer? _syncTimer;

  List<ClipItem> _clips = const [];
  List<ClipGroup> _groups = const [];
  String _query = '';
  ClipType? _typeFilter;
  bool _loading = true;
  final ParseConfig _config = ParseConfig.fromEnvironment();
  SyncStatus _syncStatus = const SyncStatus();

  bool get isLoading => _loading;
  ParseConfig get config => _config;
  SyncStatus get syncStatus => _syncStatus;
  bool get captureEnabled => _watcher.isEnabled;
  String get query => _query;
  ClipType? get typeFilter => _typeFilter;
  List<ClipGroup> get groups => _groups;

  /// Temp clips: captured automatically, auto-deleted after one day.
  List<ClipItem> get tempClips =>
      _filter(_clips.where((c) => c.isTemp)).toList();

  /// Saved clips (pinned first), what the user explicitly kept.
  List<ClipItem> get savedClips {
    final list = _filter(_clips.where((c) => c.isSaved)).toList();
    list.sort(_savedOrder);
    return list;
  }

  List<ClipItem> get pinnedClips {
    final list = _filter(_clips.where((c) => c.isPinned)).toList();
    list.sort(_savedOrder);
    return list;
  }

  List<ClipItem> clipsOfGroup(String groupId) {
    final list = _filter(_clips.where((c) => c.groupId == groupId)).toList();
    list.sort(_savedOrder);
    return list;
  }

  List<ClipItem> get ungroupedSaved {
    final list =
        _filter(_clips.where((c) => c.isSaved && c.groupId == null)).toList();
    list.sort(_savedOrder);
    return list;
  }

  int countOfGroup(String groupId) =>
      _clips.where((c) => c.groupId == groupId).length;

  int get tempCount => _clips.where((c) => c.isTemp).length;
  int get savedCount => _clips.where((c) => c.isSaved).length;
  int get pinnedCount => _clips.where((c) => c.isPinned).length;

  static int _savedOrder(ClipItem a, ClipItem b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  Iterable<ClipItem> _filter(Iterable<ClipItem> source) {
    final q = _query.trim().toLowerCase();
    return source.where((clip) {
      if (_typeFilter != null && clip.type != _typeFilter) return false;
      if (q.isEmpty) return true;
      return clip.content.toLowerCase().contains(q) ||
          (clip.note?.toLowerCase().contains(q) ?? false);
    });
  }

  // --------------------------------------------------------------- lifecycle

  Future<void> init() async {
    _sync = SyncService(
      repository: _repo,
      config: _config,
      collections: extraCollections,
    );
    await _repo.purgeExpired();
    await _reload();
    _loading = false;
    _syncStatus = _config.isConfigured
        ? SyncStatus(
            state: SyncState.idle,
            monthRequests: await _sync.requestsThisMonth(),
          )
        : const SyncStatus(state: SyncState.notConfigured);
    notifyListeners();

    _watcher.start();
    // Temp clips expire after a day; sweeping hourly is precise enough and the
    // UI also hides anything already past its deadline.
    _purgeTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      if (await _repo.purgeExpired() > 0) await _reload(notify: true);
    });
    // The cycle schedules the next one when it ends.
    if (_autoSync) unawaited(syncNow());
  }

  @override
  void dispose() {
    _purgeTimer?.cancel();
    _syncTimer?.cancel();
    _pushTimer?.cancel();
    _watcher.stop();
    super.dispose();
  }

  Future<void> _reload({bool notify = false}) async {
    _clips = await _repo.loadClips();
    _groups = await _repo.loadGroups();
    if (notify) notifyListeners();
  }

  Future<void> _onCaptured(String content) async {
    final item = await _repo.capture(content);
    if (item == null) return;
    _upsert(item);
    notifyListeners();
    // Copying a saved clip's text again bumps it; a new temp clip stays local.
    if (!item.isTemp) requestSync();
  }

  void _upsert(ClipItem item) {
    final next = [..._clips];
    final index = next.indexWhere((c) => c.id == item.id);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.insert(0, item);
    }
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _clips = next;
  }

  // ------------------------------------------------------------------ search

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void setTypeFilter(ClipType? type) {
    if (_typeFilter == type) return;
    _typeFilter = type;
    notifyListeners();
  }

  void setCaptureEnabled(bool value) {
    _watcher.setEnabled(value);
    notifyListeners();
  }

  // ----------------------------------------------------------------- actions

  /// Puts a clip back on the system clipboard, ready to paste.
  Future<void> copyToClipboard(ClipItem item) async {
    await Clipboard.setData(ClipboardData(text: item.content));
    _watcher.acknowledge(item.content);
    _upsert(await _repo.markCopied(item));
    notifyListeners();
  }

  Future<void> saveClip(ClipItem item, {String? groupId}) async {
    _upsert(await _repo.save(item, groupId: groupId));
    _changed();
  }

  Future<void> unsaveClip(ClipItem item) async {
    _upsert(await _repo.unsave(item));
    _changed();
  }

  /// Pin toggle. Pinning a temp clip also saves it so it survives the purge.
  Future<void> togglePin(ClipItem item) async {
    _upsert(await _repo.setPinned(item, !item.isPinned));
    _changed();
  }

  Future<void> assignGroup(ClipItem item, String? groupId) async {
    _upsert(await _repo.assignGroup(item, groupId));
    _changed();
  }

  Future<void> updateContent(ClipItem item, String content,
      {String? note}) async {
    _upsert(await _repo.updateContent(item, content, note: note));
    _changed();
  }

  Future<ClipItem> addManual(String content, {String? groupId}) async {
    final item = await _repo.createManual(content, groupId: groupId);
    _upsert(item);
    _changed();
    return item;
  }

  /// Soft delete: the row stays as a tombstone so the deletion can sync.
  Future<void> deleteClip(ClipItem item) async {
    await _repo.delete(item);
    _clips = _clips.where((c) => c.id != item.id).toList();
    _changed();
  }

  /// Undo for [deleteClip].
  Future<void> restoreClip(ClipItem item) async {
    _upsert(await _repo.restore(item));
    _changed();
  }

  Future<void> clearTemp() async {
    await _repo.clearTemp();
    _clips = _clips.where((c) => !c.isTemp).toList();
    _changed();
  }

  /// Repaints, and queues the change for the next push.
  void _changed() {
    notifyListeners();
    requestSync();
  }

  // -------------------------------------------------------------- Back4App
  //
  // Back4App's free tier meters requests, so cycles run on demand: a local
  // change pushes after [pushDelay], coming back to the app pulls through
  // [onAppActive], and the timer is only a fallback for what other devices did
  // meanwhile. An idle cycle costs one request (see SyncService).

  /// Fallback cadence, counted from the end of the last cycle.
  static const Duration autoSyncInterval = Duration(hours: 2);

  /// Quiet time after a local change before it goes out, so a burst of edits
  /// travels in one cycle.
  static const Duration pushDelay = Duration(seconds: 30);

  /// Coming back to the app pulls only when the last cycle is older than this.
  static const Duration activeRefreshAfter = Duration(minutes: 10);

  bool get _autoSync => _config.isConfigured && _config.autoSync;

  Timer? _pushTimer;
  DateTime? _lastSyncStarted;

  /// A change or a request arrived while a cycle was running.
  bool _syncAgain = false;

  /// Arms the fallback timer, counted from the cycle that just ended.
  void _scheduleSync() {
    _syncTimer?.cancel();
    if (!_autoSync) return;
    _syncTimer = Timer(autoSyncInterval, () => unawaited(_autoTick()));
  }

  /// The fallback tick only runs a cycle when something here is still waiting
  /// to go out (a push that failed, say). Otherwise it costs nothing; what
  /// other devices did arrives on the next focus, start or manual sync.
  Future<void> _autoTick() async {
    if (await _sync.hasLocalChanges()) {
      await syncNow();
    } else {
      _scheduleSync();
    }
  }

  /// Pushes local changes shortly, coalescing a burst into one cycle. The
  /// todo and note stores call this too.
  void requestSync() {
    if (!_autoSync) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, () => unawaited(syncNow()));
  }

  /// The user is back: pull what other devices did, unless that just ran.
  void onAppActive() {
    if (!_autoSync || _syncStatus.isRunning) return;
    final last = _lastSyncStarted;
    if (last != null &&
        DateTime.now().difference(last) < activeRefreshAfter) {
      return;
    }
    unawaited(syncNow());
  }

  /// Runs a sync cycle and reloads whatever it brought in.
  ///
  /// [full] pulls every class whatever the change counters say — for the
  /// "Đồng bộ ngay" button, where the user expects a fresh look.
  Future<SyncStatus> syncNow({bool full = false}) async {
    // A focus event can beat init(); init() runs the first cycle itself.
    if (_loading) return _syncStatus;
    if (_syncStatus.isRunning) {
      _syncAgain = true;
      return _syncStatus;
    }
    // This cycle pushes everything pending; nothing left for those timers.
    _pushTimer?.cancel();
    _syncTimer?.cancel();
    _lastSyncStarted = DateTime.now();
    _syncStatus = SyncStatus(
      state: SyncState.running,
      lastSyncAt: _syncStatus.lastSyncAt,
      monthRequests: _syncStatus.monthRequests,
    );
    notifyListeners();

    final result = await _sync.sync(full: full);
    _syncStatus = result.state == SyncState.ok
        ? result
        : SyncStatus(
            state: result.state,
            message: result.message,
            lastSyncAt: _syncStatus.lastSyncAt,
            monthRequests:
                result.monthRequests ?? _syncStatus.monthRequests,
          );
    await _reload();
    notifyListeners();

    _scheduleSync();
    if (_syncAgain) {
      _syncAgain = false;
      requestSync();
    }
    return _syncStatus;
  }

  // --------------------------------------------------------- multi-selection

  final Set<String> _selected = <String>{};

  bool get isSelecting => _selected.isNotEmpty;
  int get selectedCount => _selected.length;
  bool isSelected(String id) => _selected.contains(id);

  List<ClipItem> get selectedClips =>
      _clips.where((c) => _selected.contains(c.id)).toList();

  void toggleSelection(String id) {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<ClipItem> items) {
    _selected.addAll(items.map((c) => c.id));
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Copies every selected clip as one block, oldest first, one per line.
  Future<int> copySelected() async {
    final items = selectedClips
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (items.isEmpty) return 0;
    final text = items.map((c) => c.content).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _watcher.acknowledge(text);
    for (final item in items) {
      _upsert(await _repo.markCopied(item));
    }
    clearSelection();
    return items.length;
  }

  Future<int> saveSelected({String? groupId}) async {
    final items = selectedClips;
    for (final item in items) {
      _upsert(await _repo.save(item, groupId: groupId));
    }
    clearSelection();
    requestSync();
    return items.length;
  }

  Future<int> unsaveSelected() async {
    final items = selectedClips.where((c) => c.isSaved).toList();
    for (final item in items) {
      _upsert(await _repo.unsave(item));
    }
    clearSelection();
    requestSync();
    return items.length;
  }

  /// Pins every selection, or unpins it when all of them are already pinned.
  Future<(int, bool)> togglePinSelected() async {
    final items = selectedClips;
    if (items.isEmpty) return (0, false);
    final pin = !items.every((c) => c.isPinned);
    for (final item in items) {
      _upsert(await _repo.setPinned(item, pin));
    }
    clearSelection();
    requestSync();
    return (items.length, pin);
  }

  Future<int> assignGroupSelected(String? groupId) async {
    final items = selectedClips;
    for (final item in items) {
      _upsert(await _repo.assignGroup(item, groupId));
    }
    clearSelection();
    requestSync();
    return items.length;
  }

  /// Deletes the selection and returns it, so the caller can offer an undo.
  Future<List<ClipItem>> deleteSelected() async {
    final items = selectedClips;
    for (final item in items) {
      await _repo.delete(item);
    }
    final gone = items.map((c) => c.id).toSet();
    _clips = _clips.where((c) => !gone.contains(c.id)).toList();
    clearSelection();
    requestSync();
    return items;
  }

  Future<void> restoreClips(List<ClipItem> items) async {
    for (final item in items) {
      _upsert(await _repo.restore(item));
    }
    _changed();
  }

  // ------------------------------------------------------------------ groups

  Future<ClipGroup> createGroup(String name, int color) async {
    final group = await _repo.createGroup(name, color, _groups.length);
    _groups = [..._groups, group];
    _changed();
    return group;
  }

  Future<void> renameGroup(ClipGroup group, String name, int color) async {
    final updated =
        await _repo.updateGroup(group.copyWith(name: name, color: color));
    _groups = [
      for (final g in _groups) g.id == updated.id ? updated : g,
    ];
    _changed();
  }

  /// Deleting a group keeps its clips — they fall back to "chưa phân nhóm".
  Future<void> deleteGroup(ClipGroup group) async {
    await _repo.deleteGroup(group);
    _groups = _groups.where((g) => g.id != group.id).toList();
    _clips = [
      for (final c in _clips)
        c.groupId == group.id ? c.copyWith(clearGroup: true) : c,
    ];
    _changed();
  }

  ClipGroup? groupById(String? id) {
    if (id == null) return null;
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }
}
