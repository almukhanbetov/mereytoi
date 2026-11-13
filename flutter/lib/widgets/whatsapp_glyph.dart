import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A WhatsApp-style glyph — a speech-bubble ring with a tail and a handset
/// inside — drawn in [color]. Material Icons has no WhatsApp icon and the app
/// bundles no SVG renderer, so it's painted rather than added as a
/// dependency.
class WhatsAppGlyph extends StatelessWidget {
  const WhatsAppGlyph({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _BubblePainter(color),
          child: Center(
            child: Icon(Icons.call_rounded, size: size * 0.46, color: color),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(s / 2, s / 2);
    final r = s * 0.40;
    final stroke = s * 0.09;
    // The ring leaves a gap at the bottom-left, where the tail sits.
    const gapFrom = 115 * math.pi / 180;
    const gapTo = 155 * math.pi / 180;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      gapTo,
      2 * math.pi - (gapTo - gapFrom),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    Offset onRing(double a) =>
        center + Offset(math.cos(a) * r, math.sin(a) * r);
    final tail = Path()
      ..moveTo(onRing(gapFrom).dx, onRing(gapFrom).dy)
      ..lineTo(s * 0.05, s * 0.95)
      ..lineTo(onRing(gapTo).dx, onRing(gapTo).dy)
      ..close();
    canvas.drawPath(
      tail,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.color != color;
}
