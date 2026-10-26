import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/repositories/clipboard_repository.dart';
import 'package:event_notice/features/clipboard/domain/usecases/add_manual_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/assign_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/assign_clips_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/capture_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/clear_temp_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/copy_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/copy_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/create_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/get_capture_enabled.dart';
import 'package:event_notice/features/clipboard/domain/usecases/get_clip_groups.dart';
import 'package:event_notice/features/clipboard/domain/usecases/get_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/purge_expired_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/restore_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/restore_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/save_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/save_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/set_capture_enabled.dart';
import 'package:event_notice/features/clipboard/domain/usecases/toggle_clip_pin.dart';
import 'package:event_notice/features/clipboard/domain/usecases/toggle_clips_pin.dart';
import 'package:event_notice/features/clipboard/domain/usecases/unsave_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/unsave_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/update_clip_content.dart';
import 'package:event_notice/features/clipboard/domain/usecases/update_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/watch_captured_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/watch_remote_clip_changes.dart';
import 'package:event_notice/features/clipboard/presentation/clipboard_controller.dart';

import '../domain/fakes.dart';

/// Thursday 22/10/2026 09:00.
final t0 = DateTime(2026, 10, 22, 9);

/// [t0] plus [m] minutes.
DateTime at(int m) => t0.add(Duration(minutes: m));

ClipItem clip(
  String id, {
  String? content,
  ClipType type = ClipType.text,
  int createdMin = 0,
  int? updatedMin,
  bool saved = false,
  bool pinned = false,
  String? groupId,
  String? note,
  int copyCount = 0,
}) => ClipItem(
  id: id,
  content: content ?? 'nội dung $id',
  type: type,
  createdAt: at(createdMin),
  updatedAt: at(updatedMin ?? createdMin),
  isSaved: saved,
  isPinned: pinned,
  groupId: groupId,
  note: note,
  copyCount: copyCount,
);

ClipGroup clipGroup(String id, {String? name, int order = 0, int? color}) =>
    ClipGroup(
      id: id,
      name: name ?? 'Nhóm $id',
      color: color ?? ClipGroup.palette.first,
      createdAt: t0,
      updatedAt: t0,
      sortOrder: order,
    );

/// A controller wired to [repo] and [source] through the real use cases, with
/// the time taken from [clock] and new ids from [ids].
ClipboardController controllerFor(
  ClipboardRepository repo,
  FakeClipboardSource source, {
  required Clock clock,
  IdGenerator? ids,
}) {
  final idGen = ids ?? SequentialIdGenerator();
  return ClipboardController(
    getClips: GetClips(repo),
    getClipGroups: GetClipGroups(repo),
    watchRemoteClipChanges: WatchRemoteClipChanges(repo),
    watchCapturedClips: WatchCapturedClips(
      source,
      CaptureClip(repo, idGen, clock),
    ),
    getCaptureEnabled: GetCaptureEnabled(source),
    setCaptureEnabled: SetCaptureEnabled(source),
    purgeExpiredClips: PurgeExpiredClips(repo, clock),
    copyClip: CopyClip(source, repo, clock),
    copyClips: CopyClips(source, repo, clock),
    saveClip: SaveClip(repo, clock),
    saveClips: SaveClips(repo, clock),
    unsaveClip: UnsaveClip(repo, clock),
    unsaveClips: UnsaveClips(repo, clock),
    toggleClipPin: ToggleClipPin(repo, clock),
    toggleClipsPin: ToggleClipsPin(repo, clock),
    assignClipGroup: AssignClipGroup(repo, clock),
    assignClipsGroup: AssignClipsGroup(repo, clock),
    updateClipContent: UpdateClipContent(repo, clock),
    addManualClip: AddManualClip(repo, idGen, clock),
    deleteClip: DeleteClip(repo),
    deleteClips: DeleteClips(repo),
    restoreClip: RestoreClip(repo, clock),
    restoreClips: RestoreClips(repo, clock),
    clearTempClips: ClearTempClips(repo),
    createClipGroup: CreateClipGroup(repo, idGen, clock),
    updateClipGroup: UpdateClipGroup(repo, clock),
    deleteClipGroup: DeleteClipGroup(repo, clock),
    clock: clock,
  );
}

/// [InMemoryClipboardRepository] whose [getClips] waits for [gate] while it
/// is set, so a test can hold a load open and change things meanwhile.
class GatedClipboardRepository extends InMemoryClipboardRepository {
  GatedClipboardRepository({super.clips, super.groups});

  Completer<void>? gate;

  @override
  Future<Result<List<ClipItem>>> getClips() async {
    // Read first, then wait: the answer is what the store held at the start.
    final result = await super.getClips();
    final wait = gate;
    if (wait != null) await wait.future;
    return result;
  }
}
