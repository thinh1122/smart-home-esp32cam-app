import 'dart:math';
import 'package:flutter/material.dart';

class BrightnessRingPainter extends CustomPainter {
  final double percentage;
  final Color accentColor;

  const BrightnessRingPainter({required this.percentage, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    // Track background
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22,
    );

    // Active arc with gradient
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepAngle = 2 * pi * percentage;
    const startAngle = pi / 2;

    final gradientPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [accentColor.withOpacity(0.6), accentColor],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, gradientPaint);

    // Thumb dot
    final thumbAngle = startAngle + sweepAngle;
    final thumbCenter = Offset(
      center.dx + radius * cos(thumbAngle),
      center.dy + radius * sin(thumbAngle),
    );

    // Glow
    canvas.drawCircle(
      thumbCenter,
      18,
      Paint()..color = accentColor.withOpacity(0.25)..style = PaintingStyle.fill,
    );
    // White dot
    canvas.drawCircle(thumbCenter, 11, Paint()..color = Colors.white);
    // Inner accent
    canvas.drawCircle(thumbCenter, 6, Paint()..color = accentColor.withOpacity(0.7));
  }

  @override
  bool shouldRepaint(BrightnessRingPainter oldDelegate) =>
      oldDelegate.percentage != percentage || oldDelegate.accentColor != accentColor;
}
