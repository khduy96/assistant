import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';

enum _Phase { work, shortBreak, longBreak }

/// Đồng hồ Pomodoro: 25 phút tập trung, 5 phút nghỉ, nghỉ dài 15 phút sau
/// mỗi 4 phiên. Nằm trong [PomodoroPage].
class PomodoroCard extends StatefulWidget {
  const PomodoroCard({super.key});

  @override
  State<PomodoroCard> createState() => _PomodoroCardState();
}

class _PomodoroCardState extends State<PomodoroCard> {
  static const _durations = {
    _Phase.work: Duration(minutes: 25),
    _Phase.shortBreak: Duration(minutes: 5),
    _Phase.longBreak: Duration(minutes: 15),
  };
  static const _sessionsPerCycle = 4;

  _Phase _phase = _Phase.work;
  int _completed = 0;
  Duration _remaining = _durations[_Phase.work]!;
  DateTime? _endsAt;
  Timer? _timer;

  bool get _running => _endsAt != null;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _endsAt = DateTime.now().add(_remaining);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    setState(() {});
  }

  void _pause() {
    _timer?.cancel();
    if (_endsAt != null) _remaining = _endsAt!.difference(DateTime.now());
    _endsAt = null;
    setState(() {});
  }

  void _reset() {
    _timer?.cancel();
    _endsAt = null;
    _remaining = _durations[_phase]!;
    setState(() {});
  }

  void _tick() {
    final left = _endsAt!.difference(DateTime.now());
    if (left > Duration.zero) {
      setState(() => _remaining = left);
      return;
    }
    _timer?.cancel();
    _endsAt = null;
    if (_phase == _Phase.work) _completed++;
    final finished = _phase;
    SystemSound.play(SystemSoundType.alert);
    _goTo(_next(finished));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(finished == _Phase.work
            ? 'Hết phiên tập trung! Nghỉ thôi.'
            : 'Hết giờ nghỉ, quay lại làm việc!'),
      ));
    }
  }

  _Phase _next(_Phase from) {
    if (from != _Phase.work) return _Phase.work;
    return _completed % _sessionsPerCycle == 0
        ? _Phase.longBreak
        : _Phase.shortBreak;
  }

  void _goTo(_Phase phase) {
    _timer?.cancel();
    _endsAt = null;
    setState(() {
      _phase = phase;
      _remaining = _durations[phase]!;
    });
  }

  String get _label => switch (_phase) {
        _Phase.work => 'Tập trung',
        _Phase.shortBreak => 'Nghỉ ngắn',
        _Phase.longBreak => 'Nghỉ dài',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _durations[_phase]!.inSeconds;
    final progress = 1 - _remaining.inSeconds / total;
    final secs = _remaining.inSeconds.clamp(0, total);
    final color = _phase == _Phase.work ? scheme.primary : scheme.tertiary;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: color),
                const SizedBox(width: 8),
                Text('Pomodoro · $_label',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                for (var i = 0; i < _sessionsPerCycle; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      i < _completed % _sessionsPerCycle ||
                              (_completed > 0 &&
                                  _completed % _sessionsPerCycle == 0 &&
                                  _phase == _Phase.longBreak)
                          ? Icons.circle
                          : Icons.circle_outlined,
                      size: 12,
                      color: color,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${two(secs ~/ 60)}:${two(secs % 60)}',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, color: color),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _running ? _pause : _start,
                  icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                  label: Text(_running ? 'Tạm dừng' : 'Bắt đầu'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Đặt lại',
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt),
                ),
                IconButton(
                  tooltip: 'Bỏ qua',
                  onPressed: () => _goTo(_next(_phase)),
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
