import 'package:flutter/widgets.dart';

import '../domain/entities/linked_reminder.dart';
import '../domain/entities/reminder_draft.dart';

/// The todo list's way into the reminder editor, which belongs to the
/// reminders feature. Implemented by an adapter in `lib/app/di/bridges/`, so
/// this feature never imports reminders.
///
/// Both methods open a form on top of [BuildContext] and store what the user
/// saves; nothing is stored when the form is cancelled.
abstract interface class TodoReminderEditor {
  /// Opens a new reminder form prefilled from [draft] — a deadline form when
  /// [ReminderDraft.isDeadline] is set — and stores the reminder the user
  /// saves. Returns it, or null when the form was cancelled.
  Future<LinkedReminder?> createFromDraft(
    BuildContext context,
    ReminderDraft draft,
  );

  /// Opens the form of the reminder with [reminderId] and stores the user's
  /// edits. Does nothing when there is no such reminder.
  Future<void> open(BuildContext context, String reminderId);
}
