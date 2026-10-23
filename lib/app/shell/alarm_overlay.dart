import 'package:flutter/material.dart';

import '../../features/reminders/presentation/pages/alarm_screen.dart';
import '../../features/reminders/presentation/reminders_controller.dart';

/// Lays the alert that is ringing, if any, over [child].
class AlarmOverlay extends StatelessWidget {
  const AlarmOverlay({
    super.key,
    required this.reminders,
    required this.child,
  });

  /// Whose current alert covers the window.
  final RemindersController reminders;

  /// What the window shows when nothing rings.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reminders,
      builder: (context, child) {
        final alert = reminders.currentAlert;
        return Stack(
          children: [
            child!,
            if (alert != null)
              AlarmScreen(alert: alert, controller: reminders),
          ],
        );
      },
      child: child,
    );
  }
}
