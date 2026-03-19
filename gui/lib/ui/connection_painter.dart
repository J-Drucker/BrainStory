import 'package:flutter/material.dart';

class ConnectionPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final bool selected;

  ConnectionPainter({
    required this.start,
    required this.end,
    this.selected = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = selected ? Colors.redAccent : Colors.orangeAccent
      ..strokeWidth = selected ? 4 : 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final cp1 = Offset(start.dx + 100, start.dy);
    final cp2 = Offset(end.dx - 100, end.dy);
    path.moveTo(start.dx, start.dy);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
