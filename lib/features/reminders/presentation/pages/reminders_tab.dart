import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/reminder.dart';
import '../reminders_controller.dart';
import '../widgets/deadline_card.dart';
import '../widgets/reminder_card.dart';
import 'reminder_editor.dart';

/// Opens the form for a new reminder, or a deadline when [deadline] is set,
/// and stores what the user saves. [draft] prefills the form (a todo being
/// turned into a reminder). Returns the stored reminder, or null when the
/// form was cancelled or nothing could be stored.
///
/// Lives outside the tabs so the home page's buttons can use it without
/// reaching into their state. Reads the [RemindersController] from [context].
Future<Reminder?> addReminder(
  BuildContext context, {
  required bool deadline,
  Reminder? draft,
}) async {
  final reminders = context.read<RemindersController>();
  final newId = await reminders.newId();
  if (newId == null || !context.mounted) return null;
  final created = await showReminderEditor(
    context,
    draft: draft,
    newId: newId,
    asDeadline: deadline,
    now: reminders.now,
  );
  if (created == null) return null;
  return reminders.save(created);
}

/// Opens the form of [reminder] and stores the user's edits. Reads the
/// [RemindersController] from [context].
Future<void> editReminder(BuildContext context, Reminder reminder) async {
  final reminders = context.read<RemindersController>();
  final edited = await showReminderEditor(
    context,
    existing: reminder,
    newId: reminder.id,
    now: reminders.now,
  );
  if (edited != null) await reminders.save(edited);
}

/// Asks before deleting [reminder], then deletes it.
Future<void> _confirmDelete(BuildContext context, Reminder reminder) async {
  final reminders = context.read<RemindersController>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Xoá nhắc nhở?'),
      content: Text('"${reminder.title}" sẽ bị xoá khỏi danh sách.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Xoá'),
        ),
      ],
    ),
  );
  if (ok == true) await reminders.remove(reminder.id);
}

/// Asks before marking [deadline] as done, naming the open todo items that
/// get ticked off with it, then marks it done. Tells the user when the
/// deadline had to stay because those items could not be ticked off, or when
/// they were ticked off but deleting the deadline could not be stored.
Future<void> _confirmDone(BuildContext context, Reminder deadline) async {
  final reminders = context.read<RemindersController>();
  final messenger = ScaffoldMessenger.of(context);
  final todos = await reminders.openLinkedTodoTitles(deadline.id);
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      // Many linked items make the text taller than a small window.
      scrollable: true,
      title: const Text('Đánh dấu đã thực hiện?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"${deadline.title}" sẽ được gỡ khỏi danh sách deadline.'),
          for (final todo in todos) ...[
            const SizedBox(height: 8),
            Text('Việc "$todo" sẽ được đánh dấu đã xong.'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Đã thực hiện'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final message = switch (await reminders.markDone(deadline.id)) {
    MarkDoneResult.done => null,
    MarkDoneResult.todosNotTicked =>
      'Không đánh dấu xong được việc liên kết nên deadline vẫn được giữ.',
    MarkDoneResult.deadlineNotRemoved when todos.isNotEmpty =>
      'Đã đánh dấu xong việc liên kết nhưng không lưu được việc gỡ deadline.',
    MarkDoneResult.deadlineNotRemoved => 'Không lưu được việc gỡ deadline.',
  };
  if (message == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The reminders tab: every reminder that is not a deadline, in display
/// order. Reads the [RemindersController] from the widget tree.
class RemindersTab extends StatelessWidget {
  const RemindersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemindersController>();
    final reminders = controller.plainReminders;
    if (reminders.isEmpty) {
      return const _EmptyState(
        icon: Icons.alarm,
        title: 'Chưa có nhắc nhở nào',
        hint: 'Bấm "Thêm nhắc nhở" để tạo lịch báo cho cuộc họp sắp tới.',
      );
    }
    final now = controller.now();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: reminders.length,
      itemBuilder: (context, i) {
        final r = reminders[i];
        return ReminderCard(
          key: ValueKey(r.id),
          reminder: r,
          now: now,
          onToggle: (on) => controller.setEnabled(r.id, on),
          onEdit: () => editReminder(context, r),
          onDelete: () => _confirmDelete(context, r),
        );
      },
    );
  }
}

/// The deadlines tab: nearest first, the ones already past at the bottom.
/// Reads the [RemindersController] from the widget tree.
class DeadlinesTab extends StatelessWidget {
  const DeadlinesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemindersController>();
    final deadlines = controller.deadlines;
    if (deadlines.isEmpty) {
      return const _EmptyState(
        icon: Icons.hourglass_empty,
        title: 'Chưa có deadline nào',
        hint: 'Bấm "Thêm deadline" để đếm ngược tới hạn chót của một việc.',
      );
    }
    final now = controller.now();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: deadlines.length,
      itemBuilder: (context, i) {
        final r = deadlines[i];
        return DeadlineCard(
          key: ValueKey(r.id),
          reminder: r,
          now: now,
          onEdit: () => editReminder(context, r),
          onDone: () => _confirmDone(context, r),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
