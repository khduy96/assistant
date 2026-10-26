import 'package:flutter/material.dart';

import '../../../../core/presentation/format.dart';
import '../../domain/entities/reminder.dart';
import '../reminder_labels.dart';
import '../time_of_day_convert.dart';

/// One reminder in the reminders tab: its time, title and schedule, a status
/// chip counting down to the next ring, and a switch.
class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.now,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Reminder reminder;

  /// The moment the status chip is worked out for; the card is rebuilt every
  /// second.
  final DateTime now;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimmed = !reminder.enabled;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatTime(reminder.time.toFlutter()),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        describeSchedule(reminder),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Tag(
                            text: reminderStatus(reminder, now),
                            highlight: reminder.enabled,
                          ),
                          if (reminder.leadMinutes > 0)
                            _Tag(
                              text: 'Nhắc trước ${reminder.leadMinutes} phút',
                            ),
                          if (reminder.note.trim().isNotEmpty)
                            _Tag(text: reminder.note.trim()),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(value: reminder.enabled, onChanged: onToggle),
                PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Sửa')),
                    PopupMenuItem(value: 'delete', child: Text('Xoá')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: highlight
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
