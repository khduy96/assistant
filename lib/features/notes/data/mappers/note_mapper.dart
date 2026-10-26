import '../../domain/entities/note.dart';
import '../models/note_model.dart';

/// Converts between the stored [NoteModel] and the domain [Note].
abstract final class NoteMapper {
  /// The entity view of [model]. The sync state stays behind in the model.
  static Note toEntity(NoteModel model) => Note(
    id: model.id,
    title: model.title,
    body: model.body,
    pinned: model.pinned,
    markdown: model.markdown,
    color: model.color,
    createdAt: model.createdAt,
    updatedAt: model.updatedAt,
  );

  /// The model to store for an edited [note]. Keeps the `remoteId` of
  /// [stored], the copy saved so far (null for a new note), so the next push
  /// updates the existing server object instead of creating a second one, and
  /// marks the result dirty so that push happens.
  static NoteModel toModel(Note note, {NoteModel? stored}) => NoteModel(
    id: note.id,
    title: note.title,
    body: note.body,
    pinned: note.pinned,
    markdown: note.markdown,
    color: note.color,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    remoteId: stored?.remoteId,
    dirty: true,
  );
}
