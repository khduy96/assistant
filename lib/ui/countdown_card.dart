import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';

/// Đồng hồ đếm ngược tuỳ chỉnh: nhập giờ/phút/giây hoặc chọn nhanh.
class CountdownCard extends StatefulWidget {
  const CountdownCard({super.key});

  @override
  State<CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<CountdownCard> {
  static const _presets = [1, 5, 10, 15, 30, 60];

  final _h = TextEditingController(text: '0');
  final _m = TextEditingController(text: '5');
  final _s = TextEditingController(text: '0');

  Duration _total = const Duration(minutes: 5);
  Duration _remaining = const Duration(minutes: 5);
  DateTime? _endsAt;
  Timer? _timer;
  bool _finished = false;

  bool get _running => _endsAt != null;

  @override
  void dispose() {
    _timer?.cancel();
    _h.dispose();
    _m.dispose();
    _s.dispose();
    super.dispose();
  }

  Duration? _readInput() {
    int v(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    final d = Duration(hours: v(_h), minutes: v(_m), seconds: v(_s));
    return d > Duration.zero ? d : null;
  }

  void _setInput(Duration d) {
    _h.text = '${d.inHours}';
    _m.text = '${d.inMinutes % 60}';
    _s.text = '${d.inSeconds % 60}';
  }

  void _preset(int minutes) {
    _timer?.cancel();
    _endsAt = null;
    final d = Duration(minutes: minutes);
    _setInput(d);
    setState(() {
      _total = _remaining = d;
      _finished = false;
    });
  }

  void _start() {
    if (!_running && _remaining == _total || _finished) {
      // Lấy lại giá trị đang nhập khi bắt đầu từ đầu.
      final d = _readInput();
      if (d == null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
              const SnackBar(content: Text('Hãy nhập thời gian lớn hơn 0.')));
        return;
      }
      _total = _remaining = d;
    }
    _finished = false;
    _endsAt = DateTime.now().add(_remaining);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
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
    setState(() {
      _remaining = _total;
      _finished = false;
    });
  }

  void _tick() {
    final left = _endsAt!.difference(DateTime.now());
    if (left > Duration.zero) {
      setState(() => _remaining = left);
      return;
    }
    _timer?.cancel();
    _endsAt = null;
    SystemSound.play(SystemSoundType.alert);
    setState(() {
      _remaining = Duration.zero;
      _finished = true;
    });
  }

  String _clock(Duration d) {
    final secs = d.inSeconds < 0 ? 0 : (d.inMilliseconds / 1000).ceil();
    final h = secs ~/ 3600;
    final ms = '${two(secs % 3600 ~/ 60)}:${two(secs % 60)}';
    return h > 0 ? '${two(h)}:$ms' : ms;
  }

  Widget _field(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          enabled: !_running,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _finished ? scheme.error : scheme.primary;
    final totalMs = _total.inMilliseconds;
    final progress = totalMs == 0 ? 0.0 : 1 - _remaining.inMilliseconds / totalMs;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_bottom, color: color),
                const SizedBox(width: 8),
                Text(_finished ? 'Đã hết giờ!' : 'Đếm ngược',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _clock(_remaining),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: _finished ? scheme.error : null,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0), color: color),
            const SizedBox(height: 12),
            Row(children: [
              _field(_h, 'Giờ'),
              const SizedBox(width: 8),
              _field(_m, 'Phút'),
              const SizedBox(width: 8),
              _field(_s, 'Giây'),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final p in _presets)
                  ActionChip(
                    label: Text(p == 60 ? '1 giờ' : '$p phút'),
                    onPressed: _running ? null : () => _preset(p),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _running ? _pause : _start,
                  icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                  label: Text(_running
                      ? 'Tạm dừng'
                      : _finished
                          ? 'Chạy lại'
                          : 'Bắt đầu'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Đặt lại',
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
