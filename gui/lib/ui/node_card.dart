import 'package:flutter/material.dart';

class NodeCard extends StatelessWidget {
  final String title;
  final Offset position;
  final void Function(Offset) onDragEnd;

  const NodeCard({
    super.key,
    required this.title,
    required this.position,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Draggable(
        feedback: _buildCard(),
        childWhenDragging: Opacity(opacity: 0.5, child: _buildCard()),
        onDragEnd: (details) => onDragEnd(details.offset),
        child: _buildCard(),
      ),
    );
  }

  Widget _buildCard() {
    return Card(
      elevation: 6,
      color: Colors.blueGrey[800],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(title, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}