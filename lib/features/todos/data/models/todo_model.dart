import '../../domain/entities/todo.dart';

/// A todo as it is stored: the entity's fields plus the sync state.
///
/// The only place that knows the `todos.json` layout and the `TodoItem`
/// body on Back4App. Neither format may change: old files and other devices
/// running an older build still read and write them.
class TodoModel {
  const TodoModel({
    required this.id,
    this.title = '',
    this.note = '',
    this.done = false,
    this.priority = TodoPriority.normal,
    this.dueDate,
    this.completedAt,
    this.reminderId,
    required this.createdAt,
    required this.updatedAt,
    this.remoteId,
    this.dirty = true,
  });

  final String id;
  final String title;
  final String note;
  final bool done;
  final TodoPriority priority;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? reminderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Parse's `objectId`, null until this item has been pushed once.
  final String? remoteId;

  /// True while the local copy is ahead of the server.
  final bool dirty;

  /// A copy with the given fields replaced. Only the sync state ever changes
  /// on a stored model; edits come in as a new model from the mapper.
  TodoModel copyWith({String? remoteId, bool? dirty}) => TodoModel(
    id: id,
    title: title,
    note: note,
    done: done,
    priority: priority,
    dueDate: dueDate,
    completedAt: completedAt,
    reminderId: reminderId,
    createdAt: createdAt,
    updatedAt: updatedAt,
    remoteId: remoteId ?? this.remoteId,
    dirty: dirty ?? this.dirty,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'done': done,
    'priority': priority.name,
    'dueDate': dueDate?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'reminderId': reminderId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'remoteId': remoteId,
    'dirty': dirty,
  };

  /// Reads one entry of `todos.json`. [now] stands in for a missing or
  /// unreadable `createdAt`; a missing `updatedAt` falls back to `createdAt`.
  factory TodoModel.fromJson(Map<String, dynamic> j, {required DateTime now}) {
    DateTime? at(String key) =>
        j[key] == null ? null : DateTime.tryParse(j[key] as String);

    final createdAt = at('createdAt');
    return TodoModel(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      note: j['note'] as String? ?? '',
      done: j['done'] as bool? ?? false,
      priority: _priority(j['priority']),
      dueDate: at('dueDate'),
      completedAt: at('completedAt'),
      reminderId: j['reminderId'] as String?,
      createdAt: createdAt ?? now,
      updatedAt: at('updatedAt') ?? createdAt ?? now,
      remoteId: j['remoteId'] as String?,
      // A file written before sync existed has no flag: treat those items as
      // unpushed so the first sync uploads them.
      dirty: j['dirty'] as bool? ?? true,
    );
  }

  /// The Back4App body. `space` is added by the sync service, and Parse owns
  /// the names `createdAt`/`updatedAt`, hence the `todo` prefix here.
  Map<String, Object?> toParse() => {
    'localId': id,
    'title': title,
    'note': note,
    'done': done,
    'priority': priority.name,
    'dueDate': dueDate?.millisecondsSinceEpoch,
    'completedAt': completedAt?.millisecondsSinceEpoch,
    'reminderId': reminderId,
    'todoCreatedAt': createdAt.millisecondsSinceEpoch,
    'todoUpdatedAt': updatedAt.millisecondsSinceEpoch,
  };

  /// Reads one `TodoItem` object from the server. It is clean by definition:
  /// it is what the server already has. [now] stands in for a missing time.
  factory TodoModel.fromParse(
    Map<String, Object?> json, {
    required DateTime now,
  }) {
    DateTime? at(String key) {
      final value = json[key];
      return value is num
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : null;
    }

    return TodoModel(
      id: json['localId'] as String,
      title: (json['title'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      done: json['done'] as bool? ?? false,
      priority: _priority(json['priority']),
      dueDate: at('dueDate'),
      completedAt: at('completedAt'),
      reminderId: json['reminderId'] as String?,
      createdAt: at('todoCreatedAt') ?? now,
      updatedAt: at('todoUpdatedAt') ?? now,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }

  /// Priorities are stored by name; a missing or unknown one reads as normal.
  static TodoPriority _priority(Object? name) => TodoPriority.values.firstWhere(
    (p) => p.name == name,
    orElse: () => TodoPriority.normal,
  );
}
