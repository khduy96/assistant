import '../../../../core/domain/result.dart';
import '../entities/clip_group.dart';
import '../entities/clip_item.dart';

/// Where clips and groups are kept. Implemented in the data layer, which also
/// keeps what the sync needs: each row's server id, whether it holds edits the
/// server has not seen, and the server deletes still waiting to go out.
///
/// Every write here is a change made on this device. Writes that store an
/// edit ([saveClip], [restoreClip], [saveGroup]) mark the row as ahead of the
/// server. Whether a clip actually travels is the data layer's rule: temp
/// clips never leave the device.
///
/// No method throws: IO errors come back as an `Err`.
abstract interface class ClipboardRepository {
  /// Every stored clip, in no particular order.
  Future<Result<List<ClipItem>>> getClips();

  /// The stored clip whose content is exactly [content], or null.
  Future<Result<ClipItem?>> findClipByContent(String content);

  /// Adds [clip], or replaces the stored clip with the same id, as an edit the
  /// server has not seen.
  ///
  /// When [share] is false the edit is recorded all the same but does not ask
  /// for a push by itself: capturing a temp clip is nobody else's business,
  /// and a clip saved later goes out with that later edit.
  Future<Result<void>> saveClip(ClipItem clip, {bool share = true});

  /// Stores [clip]'s [ClipItem.copiedAt] and [ClipItem.copyCount] and nothing
  /// else. Neither travels on its own, so the clip's standing with the server
  /// is left as it is and no push is asked for. An unknown id is not an error.
  Future<Result<void>> recordCopy(ClipItem clip);

  /// Takes the clip with [id] off the server: if it was ever pushed, its
  /// server object is queued for deletion and the link to it is forgotten, so
  /// saving the clip again pushes a new object. The clip itself stays.
  ///
  /// Asks for no push by itself; the edit that follows does. An unknown id or
  /// a clip that never reached the server is not an error.
  Future<Result<void>> detachFromServer(String id);

  /// Removes the clips with [ids] in one write. Those that ever reached the
  /// server have their server object queued for deletion, so a delete made
  /// offline still goes out later. Unknown ids are skipped.
  ///
  /// When [share] is false the deletes are queued but no push is asked for:
  /// the hourly purge of expired temp clips is housekeeping, not news.
  Future<Result<void>> deleteClips(Iterable<String> ids, {bool share = true});

  /// Puts back [clip], removed earlier by [deleteClips], as an edit the server
  /// has not seen. If its server delete has not gone out yet it is cancelled,
  /// and the next push updates the same server object instead of creating a
  /// second one.
  Future<Result<void>> restoreClip(ClipItem clip);

  /// Every stored group, in no particular order.
  Future<Result<List<ClipGroup>>> getGroups();

  /// Adds [group], or replaces the stored group with the same id, as an edit
  /// the server has not seen.
  Future<Result<void>> saveGroup(ClipGroup group);

  /// Removes the group with [id], queueing a server delete if it ever reached
  /// the server. Clips still pointing at it lose the link; callers that want
  /// those clips to stay saved and to travel move them out first. An unknown
  /// id is not an error.
  Future<Result<void>> deleteGroup(String id);

  /// Fires after a sync wrote clips or groups, so a listener can reload them.
  /// Writes made through the methods above do not fire it: their caller
  /// already holds the result.
  Stream<void> get remoteChanges;
}
