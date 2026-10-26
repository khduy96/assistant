import 'package:flutter/widgets.dart';

import '../../../features/reminders/domain/entities/reminder.dart';
import '../../../features/reminders/presentation/pages/reminder_editor.dart';
import '../../../features/reminders/presentation/reminders_controller.dart';
import '../../../features/todos/domain/entities/linked_reminder.dart';
import '../../../features/todos/domain/entities/reminder_draft.dart';
import '../../../features/todos/presentation/todo_reminder_editor.dart';
import 'linked_reminder_bridge.dart';

/// The todo list's [TodoReminderEditor]: opens the reminders' form
/// ([showReminderEditor]) and stores the result through the app's
/// [RemindersController].
class TodoReminderEditorBridge implements TodoReminderEditor {
  TodoReminderEditorBridge(this._reminders);

  final RemindersController _reminders;

  @override
  Future<LinkedReminder?> createFromDraft(
    BuildContext context,
    ReminderDraft draft,
  ) async {
    final newId = await _reminders.newId();
    if (newId == null || !context.mounted) return null;
    final created = await showReminderEditor(
      context,
      draft: Reminder(
        id: newId, // unused: the editor stamps its own id on the result
        title: draft.title,
        note: draft.note,
        repeat: RepeatRule.once,
        date: draft.date,
        time: draft.time,
        leadMinutes: draft.leadMinutes,
        isDeadline: draft.isDeadline,
        createdAt: _reminders.now(),
      ),
      newId: newId,
      asDeadline: draft.isDeadline,
      now: _reminders.now,
    );
    if (created == null) return null;
    final saved = await _reminders.save(created);
    return saved == null ? null : toLinkedReminder(saved, _reminders.now());
  }

  @override
  Future<void> open(BuildContext context, String reminderId) async {
    final linked = _reminders.reminderById(reminderId);
    if (linked == null) return;
    final edited = await showReminderEditor(
      context,
      existing: linked,
      newId: linked.id,
      now: _reminders.now,
    );
    if (edited != null) await _reminders.save(edited);
  }
}
