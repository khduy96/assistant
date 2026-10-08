import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'running_text_page.dart';

/// Tab "Chạy chữ": nhập nội dung, chỉnh thời lượng / cỡ chữ / nền rồi mở
/// bảng LED toàn màn hình.
class RunningTextTab extends StatefulWidget {
  const RunningTextTab({super.key});

  @override
  State<RunningTextTab> createState() => _RunningTextTabState();
}

class _RunningTextTabState extends State<RunningTextTab>
    with AutomaticKeepAliveClientMixin {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  double _durationSeconds = 60;
  double _fontSize = 72;
  bool _light = false;

  // Giữ nội dung đang gõ khi chuyển sang tab khác rồi quay lại.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  // Bảng LED chỉ có một dòng, nên xuống dòng (và khoảng trắng quanh nó) được
  // gộp thành một dấu cách.
  String get _singleLine =>
      _text.text.trim().replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');

  static String _formatDuration(double seconds) =>
      formatRunDuration(seconds.round());

  /// Thanh trượt chỉ phủ 10s–5p cho nhanh; thời lượng dài hơn thì nhập tay.
  static const _sliderMaxSeconds = 300.0;
  static const _minSeconds = 10;
  static const _maxSeconds = 24 * 60 * 60;

  Future<void> _editDuration() async {
    final seconds = await showDialog<int>(
      context: context,
      builder: (_) => _DurationDialog(
        initialSeconds: _durationSeconds.round(),
        minSeconds: _minSeconds,
        maxSeconds: _maxSeconds,
      ),
    );
    if (seconds != null) {
      setState(() => _durationSeconds = seconds.toDouble());
    }
  }

  void _start() {
    final text = _singleLine;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            const SnackBar(content: Text('Hãy nhập nội dung cần chạy chữ.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RunningTextPage(
        text: text,
        fontSize: _fontSize,
        durationSeconds: _durationSeconds.round(),
        initialLightMode: _light,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(builder: (context, constraints) {
      // Màn rộng: cấu hình bên trái, xem trước bên phải. Màn hẹp: xếp dọc
      // và cuộn.
      if (constraints.maxWidth >= 760) {
        // Thấp hơn mức này thì bố cục ngừng co lại và cuộn dọc, để ô nhập
        // và các thanh trượt không bị ép tràn.
        const minHeight = 620.0;
        final height = math.max(constraints.maxHeight, minHeight);
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: height > constraints.maxHeight,
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: height,
              child: _wideLayout(),
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Panel(
            title: 'Cấu hình',
            icon: Icons.tune,
            child: _settings(expandText: false),
          ),
          const SizedBox(height: 16),
          _Panel(
            title: 'Xem trước',
            icon: Icons.preview_outlined,
            child: SizedBox(height: 220, child: _preview()),
          ),
        ],
      );
    });
  }

  Widget _wideLayout() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: _Panel(
              title: 'Cấu hình',
              icon: Icons.tune,
              fill: true,
              child: _settings(expandText: true),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: _Panel(
              title: 'Xem trước',
              icon: Icons.preview_outlined,
              fill: true,
              child: _preview(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settings({required bool expandText}) {
    final field = TextField(
      controller: _text,
      expands: expandText,
      minLines: expandText ? null : 3,
      maxLines: expandText ? null : 6,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        hintText: 'Nhập nội dung muốn hiển thị...',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: expandText ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const _Label('Nội dung'),
        const SizedBox(height: 8),
        expandText ? Expanded(child: field) : field,
        const SizedBox(height: 20),
        _slider(
          title: 'Thời lượng',
          valueText: _formatDuration(_durationSeconds),
          // Giá trị nhập tay có thể vượt quá thanh trượt; khi đó con trượt
          // nằm ở cuối, kéo lại thì quay về khoảng 10s–5p.
          value: math.min(_durationSeconds, _sliderMaxSeconds),
          min: _minSeconds.toDouble(),
          max: _sliderMaxSeconds,
          divisions: 58,
          onChanged: (v) => setState(() => _durationSeconds = v),
          onEditValue: _editDuration,
        ),
        const SizedBox(height: 8),
        _slider(
          title: 'Cỡ chữ',
          valueText: '${_fontSize.round()} px',
          value: _fontSize,
          min: 20,
          max: 200,
          divisions: 180,
          onChanged: (v) => setState(() => _fontSize = v),
        ),
        const SizedBox(height: 8),
        const _Label('Nền'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Tối'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Sáng'),
              ),
            ],
            selected: {_light},
            onSelectionChanged: (s) => setState(() => _light = s.first),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('BẮT ĐẦU CHẠY CHỮ',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _slider({
    required String title,
    required String valueText,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    VoidCallback? onEditValue,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(valueText,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (onEditValue != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, size: 14, color: scheme.primary),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Label(title),
            const Spacer(),
            Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              child: onEditValue == null
                  ? chip
                  : Tooltip(
                      message: 'Nhập thời lượng tuỳ ý',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: onEditValue,
                        child: chip,
                      ),
                    ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _preview() {
    final outline = Theme.of(context).colorScheme.outline;
    final text = _singleLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _light ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: outline.withValues(alpha: 0.3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    text.isEmpty ? 'Nội dung sẽ hiện ở đây' : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _light ? Colors.black : Colors.white,
                      fontSize: _fontSize
                          .clamp(20, constraints.maxHeight * 0.55)
                          .toDouble(),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Chữ chạy từ phải sang trái trong '
                '${_formatDuration(_durationSeconds)}. '
                'Phím tắt: Space dừng, R chạy lại, T đổi nền, '
                'F toàn màn hình, Esc thoát.',
                style: TextStyle(fontSize: 12, color: outline),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Nhập thời lượng bằng phút + giây, không bị giới hạn bởi thanh trượt.
class _DurationDialog extends StatefulWidget {
  const _DurationDialog({
    required this.initialSeconds,
    required this.minSeconds,
    required this.maxSeconds,
  });

  final int initialSeconds;
  final int minSeconds;
  final int maxSeconds;

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final _minutes =
      TextEditingController(text: '${widget.initialSeconds ~/ 60}');
  late final _seconds =
      TextEditingController(text: '${widget.initialSeconds % 60}');
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _submit() {
    final m = int.tryParse(_minutes.text.trim().isEmpty ? '0' : _minutes.text);
    final s = int.tryParse(_seconds.text.trim().isEmpty ? '0' : _seconds.text);
    if (m == null || s == null || m < 0 || s < 0) {
      setState(() => _error = 'Chỉ nhập số nguyên không âm.');
      return;
    }
    final total = m * 60 + s;
    if (total < widget.minSeconds || total > widget.maxSeconds) {
      setState(() => _error = 'Thời lượng phải từ '
          '${formatRunDuration(widget.minSeconds)} đến '
          '${formatRunDuration(widget.maxSeconds)}.');
      return;
    }
    Navigator.of(context).pop(total);
  }

  Widget _field(TextEditingController c, String label, {bool last = false}) {
    return Expanded(
      child: TextField(
        controller: c,
        autofocus: !last,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onSubmitted: last ? (_) => _submit() : null,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thời lượng chạy chữ'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _field(_minutes, 'Phút'),
                const SizedBox(width: 12),
                _field(_seconds, 'Giây', last: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _error ??
                  'Tối đa ${formatRunDuration(widget.maxSeconds)}. '
                      'Giây có thể nhập quá 59, sẽ được quy đổi.',
              style: TextStyle(
                fontSize: 12,
                color: _error != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Đặt')),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600));
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
    this.fill = false,
  });

  final String title;
  final IconData icon;
  final Widget child;

  /// Nội dung giãn hết chiều cao còn lại; chỉ dùng khi chiều cao có giới hạn.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            fill ? Expanded(child: child) : child,
          ],
        ),
      ),
    );
  }
}
