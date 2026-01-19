import 'package:flutter/material.dart';

class ConnectionPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  ConnectionPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + 60, start.dy,
        end.dx - 60, end.dy,
        end.dx, end.dy,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
