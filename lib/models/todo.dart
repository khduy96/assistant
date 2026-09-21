/// How urgent a todo is; drives the sort order and the colour of its tag.
enum TodoPriority { low, normal, high }

extension TodoPriorityLabel on TodoPriority {
  String get label => switch (this) {
        TodoPriority.low => 'Thấp',
        TodoPriority.normal => 'Bình thường',
        TodoPriority.high => 'Quan trọng',
      };
}

/// One item on the todo list. Unlike a [Reminder] it never rings — it is just
/// a thing to tick off, optionally with a day it should be done by.
class Todo {
  Todo({
    required this.id,
    required this.title,
    this.note = '',
    this.done = false,
    this.priority = TodoPriority.normal,
    this.dueDate,
    this.completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.remoteId,
    this.dirty = true,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  String title;
  String note;
  bool done;
  TodoPriority priority;

  /// When the item is due. A time of exactly 00:00 means "sometime that day"
  /// — see [hasDueTime] — so items saved before the clock existed still read
  /// the same way.
  DateTime? dueDate;

  /// When the item was ticked off, so finished work can be shown in order.
  DateTime? completedAt;

  final DateTime createdAt;

  /// Bumped on every edit; what the sync uses to settle conflicts.
  DateTime updatedAt;

  /// Parse's `objectId`, null until this item has been pushed once.
  String? remoteId;

  /// True while the local copy is ahead of the server.
  bool dirty;

  /// Marks the item as edited now, so the next sync pushes it.
  void touch() {
    updatedAt = DateTime.now();
    dirty = true;
  }

  /// True when the deadline carries an explicit clock time rather than just a
  /// day. Midnight is the marker for "no time picked".
  bool get hasDueTime {
    final due = dueDate;
    return due != null && (due.hour != 0 || due.minute != 0);
  }

  /// True when an unfinished item is past its deadline: past that minute when
  /// a time was picked, otherwise past the whole day.
  bool get isOverdue {
    final due = dueDate;
    if (done || due == null) return false;
    final now = DateTime.now();
    if (hasDueTime) return due.isBefore(now);
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  /// True when an unfinished item is due today.
  bool get isDueToday {
    final due = dueDate;
    if (done || due == null) return false;
    final now = DateTime.now();
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }

  Todo copy() => Todo.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'done': done,
        'priority': priority.name,
        'dueDate': dueDate?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'remoteId': remoteId,
        'dirty': dirty,
      };

  factory Todo.fromJson(Map<String, dynamic> j) => Todo(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        note: j['note'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        priority: TodoPriority.values.firstWhere(
          (p) => p.name == j['priority'],
          orElse: () => TodoPriority.normal,
        ),
        dueDate: j['dueDate'] == null
            ? null
            : DateTime.tryParse(j['dueDate'] as String),
        completedAt: j['completedAt'] == null
            ? null
            : DateTime.tryParse(j['completedAt'] as String),
        createdAt: j['createdAt'] == null
            ? null
            : DateTime.tryParse(j['createdAt'] as String),
        updatedAt: j['updatedAt'] == null
            ? null
            : DateTime.tryParse(j['updatedAt'] as String),
        remoteId: j['remoteId'] as String?,
        // A file written before sync existed has no flag: treat those items as
        // unpushed so the first sync uploads them.
        dirty: j['dirty'] as bool? ?? true,
      );

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
        'todoCreatedAt': createdAt.millisecondsSinceEpoch,
        'todoUpdatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory Todo.fromParse(Map<String, Object?> json) {
    DateTime? at(String key) {
      final value = json[key];
      return value is num
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : null;
    }

    final now = DateTime.now();
    return Todo(
      id: json['localId'] as String,
      title: (json['title'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      done: json['done'] as bool? ?? false,
      priority: TodoPriority.values.firstWhere(
        (p) => p.name == json['priority'],
        orElse: () => TodoPriority.normal,
      ),
      dueDate: at('dueDate'),
      completedAt: at('completedAt'),
      createdAt: at('todoCreatedAt') ?? now,
      updatedAt: at('todoUpdatedAt') ?? now,
      remoteId: json['objectId'] as String?,
      dirty: false,
    );
  }
}
