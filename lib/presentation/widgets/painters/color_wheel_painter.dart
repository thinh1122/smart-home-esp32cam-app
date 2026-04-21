import 'dart:math';
import 'package:flutter/material.dart';

class ColorWheelPainter extends CustomPainter {
  final double thumbAngle;

  const ColorWheelPainter({this.thumbAngle = pi * 0.75});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius - 14;

    const gradient = SweepGradient(
      colors: [
        Colors.blue, Colors.purple, Colors.red,
        Colors.orange, Colors.yellow, Colors.green,
        Colors.cyan, Colors.blue,
      ],
      stops: [0.0, 0.14, 0.28, 0.42, 0.57, 0.71, 0.85, 1.0],
    );

    final rect = Rect.fromCircle(center: center, radius: outerRadius);
    final shader = gradient.createShader(rect);

    // Outer ring
    canvas.drawCircle(
      center,
      outerRadius - 2,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    // Inner filled wheel
    canvas.drawCircle(center, innerRadius, Paint()..shader = shader..style = PaintingStyle.fill);

    // White radial overlay for saturation
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.6), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: innerRadius)),
    );

    // Thumb
    final thumbCenter = Offset(
      center.dx + (innerRadius - 18) * cos(thumbAngle),
      center.dy + (innerRadius - 18) * sin(thumbAngle),
    );

    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: thumbCenter, radius: 13)),
      Colors.black,
      6,
      true,
    );
    canvas.drawCircle(thumbCenter, 13, Paint()..color = Colors.white);
    canvas.drawCircle(
      thumbCenter,
      9,
      Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(ColorWheelPainter oldDelegate) => oldDelegate.thumbAngle != thumbAngle;
}
