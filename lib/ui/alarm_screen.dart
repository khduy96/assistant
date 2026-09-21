import 'dart:io';

import 'package:flutter/material.dart';

import '../services/reminder_store.dart';
import 'format.dart';

/// Full-window alert shown on top of everything else when a reminder fires.
///
/// The window it lives in is shrunk, centred and pinned always-on-top by the
/// app shell, so this reads as a popup with a live clock.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key, required this.alert, required this.store});

  final PendingAlert alert;
  final ReminderStore store;

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final r = alert.reminder;
    final theme = Theme.of(context);
    final accent = alert.isLead
        ? const Color(0xFF38BDF8)
        : const Color(0xFFFB7185);
    final now = DateTime.now(); // rebuilt every second by the store's ticker

    return Material(
      color: const Color(0xFF0B1020),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 38,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: Tween(begin: 0.5, end: 1.0).animate(_pulse),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          alert.isLead
                              ? Icons.notifications_active
                              : Icons.alarm_on,
                          color: accent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          alert.isLead
                              ? 'SẮP TỚI GIỜ — CÒN ${r.leadMinutes} PHÚT'
                              : 'ĐẾN GIỜ RỒI!',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // The live clock: the point of the window at a glance.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Text(
                    formatDate(now),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    r.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sự kiện lúc ${two(alert.eventAt.hour)}:${two(alert.eventAt.minute)}'
                    ' · ${formatDate(alert.eventAt)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: accent),
                  ),
                  if (r.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      r.note,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.store.snoozeCurrent,
                        icon: const Icon(Icons.snooze),
                        label: Text('Báo lại ${r.snoozeMinutes} phút'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: widget.store.dismissCurrent,
                        icon: const Icon(Icons.check),
                        label: const Text('Tắt chuông'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: const Color(0xFF0B1020),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    Platform.isAndroid
                        ? 'Tắt chuông bằng nút trên màn hình, phím âm lượng '
                              'hoặc phím nguồn'
                        : 'Đóng cửa sổ (X) cũng tắt chuông',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
