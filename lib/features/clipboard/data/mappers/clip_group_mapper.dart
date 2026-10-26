import '../../domain/entities/clip_group.dart';
import '../models/clip_group_model.dart';

/// Converts between the stored [ClipGroupModel] and the domain [ClipGroup].
abstract final class ClipGroupMapper {
  /// The entity view of [model]. The sync state stays behind in the model.
  static ClipGroup toEntity(ClipGroupModel model) => ClipGroup(
    id: model.id,
    name: model.name,
    color: model.color,
    createdAt: model.createdAt,
    updatedAt: model.updatedAt,
    sortOrder: model.sortOrder,
  );

  /// The model to store for an edited [group], marked dirty so the next push
  /// sends it. [remoteId] is the server object the group already has, if
  /// any.
  static ClipGroupModel toModel(ClipGroup group, {String? remoteId}) =>
      ClipGroupModel(
        id: group.id,
        name: group.name,
        color: group.color,
        createdAt: group.createdAt,
        updatedAt: group.updatedAt,
        sortOrder: group.sortOrder,
        remoteId: remoteId,
        dirty: true,
      );
}
