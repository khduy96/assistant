import '../../domain/entities/clip_item.dart';
import '../models/clip_model.dart';

/// Converts between the stored [ClipModel] and the domain [ClipItem].
abstract final class ClipMapper {
  /// The entity view of [model]. The sync state stays behind in the model.
  static ClipItem toEntity(ClipModel model) => ClipItem(
    id: model.id,
    content: model.content,
    type: model.type,
    createdAt: model.createdAt,
    updatedAt: model.updatedAt,
    copiedAt: model.copiedAt,
    isSaved: model.isSaved,
    isPinned: model.isPinned,
    groupId: model.groupId,
    note: model.note,
    copyCount: model.copyCount,
  );

  /// The model to store for an edited [clip], marked dirty so the next push
  /// sends it. [remoteId] is the server object the clip already has, if any:
  /// keeping it makes that push update the object instead of creating a
  /// second one.
  static ClipModel toModel(ClipItem clip, {String? remoteId}) => ClipModel(
    id: clip.id,
    content: clip.content,
    type: clip.type,
    createdAt: clip.createdAt,
    updatedAt: clip.updatedAt,
    copiedAt: clip.copiedAt,
    isSaved: clip.isSaved,
    isPinned: clip.isPinned,
    groupId: clip.groupId,
    note: clip.note,
    copyCount: clip.copyCount,
    remoteId: remoteId,
    dirty: true,
  );
}
