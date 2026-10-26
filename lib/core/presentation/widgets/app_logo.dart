import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app mark: a stack of clipboard cards with a history clock badge.
///
/// Drawn with a painter rather than a bitmap so it stays sharp at every size
/// and doubles as the source used to generate the launcher icons
/// (`tool/generate_app_icon.dart`).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96, this.withBackground = true});

  final double size;

  /// False renders only the mark, for an adaptive-icon foreground layer.
  final bool withBackground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: AppLogoPainter(withBackground: withBackground),
      ),
    );
  }
}

class AppLogoPainter extends CustomPainter {
  const AppLogoPainter({this.withBackground = true, this.markScale = 1.0});

  final bool withBackground;

  /// Shrinks the mark inside the canvas; adaptive icons need ~0.62 of safe area.
  final double markScale;

  // Palette, kept in sync with the seed color of the app theme.
  static const Color _bgTop = Color(0xFF7BA9FF);
  static const Color _bgBottom = Color(0xFF3358C8);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _clip = Color(0xFF2A4FB5);
  static const Color _line = Color(0xFFB6CBF2);
  static const Color _badge = Color(0xFF14C08D);

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is authored on a 1024x1024 grid, then scaled.
    final scale = size.shortestSide / 1024;
    canvas.save();
    canvas.scale(scale);

    if (withBackground) _paintBackground(canvas);

    canvas.translate(512, 512);
    canvas.scale(markScale);
    canvas.translate(-512, -512);

    _paintBackCard(canvas);
    _paintFrontCard(canvas);
    _paintBadge(canvas);

    canvas.restore();
  }

  void _paintBackground(Canvas canvas) {
    final rect = const Rect.fromLTWH(0, 0, 1024, 1024);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(232)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bgTop, _bgBottom],
        ).createShader(rect),
    );
  }

  /// The second, tilted card behind — "there is more than one clip".
  void _paintBackCard(Canvas canvas) {
    canvas.save();
    canvas.translate(512, 512);
    canvas.rotate(-11 * math.pi / 180);
    canvas.translate(-512, -512);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(262, 262, 460, 560),
        const Radius.circular(58),
      ),
      Paint()..color = _card.withValues(alpha: 0.42),
    );
    canvas.restore();
  }

  void _paintFrontCard(Canvas canvas) {
    const cardRect = Rect.fromLTWH(292, 252, 460, 560);
    final cardRRect =
        RRect.fromRectAndRadius(cardRect, const Radius.circular(58));
    canvas.drawRRect(
      cardRRect.shift(const Offset(0, 14)),
      Paint()
        ..color = const Color(0x33101C3A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    canvas.drawRRect(cardRRect, Paint()..color = _card);

    // Clip head sitting on the top edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(427, 186, 190, 112),
        const Radius.circular(42),
      ),
      Paint()..color = _clip,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(482, 216, 80, 30),
        const Radius.circular(15),
      ),
      Paint()..color = _card,
    );

    // Text lines.
    final linePaint = Paint()..color = _line;
    const lineWidths = [320.0, 320.0, 228.0];
    for (var i = 0; i < lineWidths.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(360, 392 + i * 92, lineWidths[i], 44),
          const Radius.circular(22),
        ),
        linePaint,
      );
    }
  }

  /// History badge: a clock face overlapping the bottom-right corner.
  void _paintBadge(Canvas canvas) {
    const center = Offset(760, 762);
    canvas.drawCircle(center, 152, Paint()..color = _card);
    canvas.drawCircle(center, 130, Paint()..color = _badge);

    final hand = Paint()
      ..color = _card
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(
      center,
      72,
      Paint()
        ..color = _card
        ..strokeWidth = 20
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(center, center.translate(0, -44), hand);
    canvas.drawLine(center, center.translate(40, 8), hand);
  }

  @override
  bool shouldRepaint(AppLogoPainter oldDelegate) =>
      oldDelegate.withBackground != withBackground ||
      oldDelegate.markScale != markScale;
}
