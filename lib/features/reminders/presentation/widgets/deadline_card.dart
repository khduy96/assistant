import 'package:flutter/material.dart';

import '../../../../core/presentation/format.dart';
import '../../domain/entities/reminder.dart';
import '../../domain/services/schedule_calculator.dart';
import '../reminder_labels.dart';

/// A deadline shown as a live countdown: the number is the point, so it gets
/// the size, and the colour escalates as the remaining time shrinks.
class DeadlineCard extends StatelessWidget {
  const DeadlineCard({
    super.key,
    required this.reminder,
    required this.now,
    required this.onEdit,
    required this.onDone,
  });

  final Reminder reminder;

  /// The moment the countdown is shown for; the card is rebuilt every second.
  final DateTime now;
  final VoidCallback onEdit;

  /// The user picked "Đã thực hiện"; the deadline is then taken off the list.
  final VoidCallback onDone;

  static const _overdue = Color(0xFFEF4444);
  static const _urgent = Color(0xFFF59E0B);
  static const _calm = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = ScheduleCalculator.timeLeft(reminder, now);
    final passed = left.isNegative;
    final color = passed
        ? _overdue
        : left.inHours < 24
        ? _urgent
        : _calm;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reminder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? onEdit() : onDone(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Sửa')),
                      PopupMenuItem(value: 'done', child: Text('Đã thực hiện')),
                    ],
                  ),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  deadlineHeadline(left),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ScheduleCalculator.elapsedFraction(reminder, now),
                  minHeight: 6,
                  color: color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.flag_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Hạn chót ${formatDateTime(reminder.deadlineAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  if (reminder.leadMinutes > 0)
                    Text(
                      'Báo trước ${formatEvery(reminder.leadMinutes)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              if (reminder.note.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  reminder.note.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
