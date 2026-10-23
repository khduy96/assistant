import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// "45s", "4p 30s", "1g 05p" — thời lượng một lượt chạy chữ.
String formatRunDuration(int seconds) {
  final d = Duration(seconds: seconds);
  final s = d.inSeconds % 60, m = d.inMinutes % 60;
  if (d.inHours > 0) {
    return s == 0
        ? '${d.inHours}g ${m.toString().padLeft(2, '0')}p'
        : '${d.inHours}g ${m.toString().padLeft(2, '0')}p '
            '${s.toString().padLeft(2, '0')}s';
  }
  if (d.inMinutes > 0) return s == 0 ? '${m}p' : '${m}p ${s}s';
  return '${s}s';
}

/// Bảng LED: một dòng chữ chạy từ phải sang trái, phủ kín màn hình.
///
/// Phím tắt: Space tạm dừng / chạy tiếp, R chạy lại, T đổi nền sáng/tối,
/// Esc thoát.
class RunningTextPage extends StatefulWidget {
  const RunningTextPage({
    super.key,
    required this.text,
    required this.fontSize,
    required this.durationSeconds,
    this.initialLightMode = false,
  });

  final String text;
  final double fontSize;
  final int durationSeconds;
  final bool initialLightMode;

  @override
  State<RunningTextPage> createState() => _RunningTextPageState();
}

class _RunningTextPageState extends State<RunningTextPage>
    with SingleTickerProviderStateMixin {
  static final _desktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.durationSeconds),
  )..forward();

  final _focusNode = FocusNode();

  bool _paused = false;
  late bool _light = widget.initialLightMode;

  /// Desktop: cửa sổ giữ kích thước và resize tự do; toàn màn hình chỉ bật
  /// khi người dùng chọn (nút hoặc phím F).
  bool _fullScreen = false;

  /// Cửa sổ đã toàn màn hình từ trước khi mở trang thì lúc thoát giữ nguyên.
  bool _wasFullScreen = false;

  Color get _background => _light ? Colors.white : Colors.black;
  Color get _foreground => _light ? Colors.black : Colors.white;
  Color get _overlay => _foreground.withValues(alpha: _light ? 0.08 : 0.12);
  Color get _pausedColor => _light ? Colors.amber.shade800 : Colors.amber;

  TextStyle get _textStyle => TextStyle(
        color: _foreground,
        fontSize: widget.fontSize,
        fontWeight: FontWeight.bold,
      );

  @override
  void initState() {
    super.initState();
    _initScreenMode();

    // Nhận bàn phím sau khi route chuyển xong, nếu không Space vẫn rơi vào
    // widget đang giữ focus trước đó.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _restoreScreenMode();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initScreenMode() async {
    if (_desktop) {
      _wasFullScreen = await windowManager.isFullScreen();
      if (mounted) setState(() => _fullScreen = _wasFullScreen);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _restoreScreenMode() async {
    if (_desktop) {
      if (_fullScreen != _wasFullScreen) {
        await windowManager.setFullScreen(_wasFullScreen);
      }
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _toggleFullScreen() async {
    _focusNode.requestFocus();
    final next = !_fullScreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _fullScreen = next);
  }

  double _measureTextWidth() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: _textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  void _togglePause() {
    // Bấm chuột có thể lấy mất focus; giành lại để Space vẫn hoạt động.
    _focusNode.requestFocus();
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _controller.stop();
      } else if (_controller.value >= 1.0) {
        // Đã chạy hết: phát lại từ đầu.
        _controller.forward(from: 0);
      } else {
        _controller.forward();
      }
    });
  }

  void _restart() {
    _focusNode.requestFocus();
    setState(() {
      _paused = false;
      _controller.forward(from: 0);
    });
  }

  void _toggleTheme() {
    _focusNode.requestFocus();
    setState(() => _light = !_light);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePause();
    } else if (key == LogicalKeyboardKey.keyR) {
      _restart();
    } else if (key == LogicalKeyboardKey.keyT) {
      _toggleTheme();
    } else if (_desktop &&
        (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11)) {
      _toggleFullScreen();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _overlay,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: _foreground, size: 26),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textWidth = _measureTextWidth();

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: _background,
        body: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final startX = constraints.maxWidth;
              final x = startX + (-textWidth - startX) * _controller.value;

              return Stack(
                children: [
                  Positioned(
                    left: x,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Text(
                        widget.text,
                        maxLines: 1,
                        softWrap: false,
                        style: _textStyle,
                      ),
                    ),
                  ),

                  // Chạm bất kỳ đâu để tạm dừng / chạy tiếp.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _togglePause,
                    ),
                  ),

                  // ExcludeFocus giữ bàn phím ở trang, để sau khi bấm nút thì
                  // Space không kích hoạt lại nút đó.
                  Positioned(
                    top: 20,
                    right: 20,
                    child: SafeArea(
                      child: ExcludeFocus(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _controlButton(
                              icon: _light
                                  ? Icons.dark_mode_outlined
                                  : Icons.light_mode_outlined,
                              tooltip: _light ? 'Nền tối (T)' : 'Nền sáng (T)',
                              onTap: _toggleTheme,
                            ),
                            const SizedBox(width: 12),
                            if (_desktop) ...[
                              _controlButton(
                                icon: _fullScreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                                tooltip: _fullScreen
                                    ? 'Thoát toàn màn hình (F)'
                                    : 'Toàn màn hình (F)',
                                onTap: _toggleFullScreen,
                              ),
                              const SizedBox(width: 12),
                            ],
                            _controlButton(
                              icon: Icons.refresh,
                              tooltip: 'Chạy lại (R)',
                              onTap: _restart,
                            ),
                            const SizedBox(width: 12),
                            _controlButton(
                              icon: _paused ? Icons.play_arrow : Icons.pause,
                              tooltip: _paused
                                  ? 'Chạy tiếp (Space)'
                                  : 'Tạm dừng (Space)',
                              onTap: _togglePause,
                            ),
                            const SizedBox(width: 12),
                            _controlButton(
                              icon: Icons.close,
                              tooltip: 'Thoát (Esc)',
                              onTap: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Thời lượng + trạng thái tạm dừng.
                  Positioned(
                    left: 20,
                    top: 20,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _overlay,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: _foreground.withValues(alpha: 0.7),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formatRunDuration(widget.durationSeconds),
                              style:
                                  TextStyle(color: _foreground, fontSize: 13),
                            ),
                            if (_paused) ...[
                              const SizedBox(width: 10),
                              Container(
                                width: 1,
                                height: 14,
                                color: _foreground.withValues(alpha: 0.24),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.pause, color: _pausedColor, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'TẠM DỪNG',
                                style: TextStyle(
                                  color: _pausedColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
