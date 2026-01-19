import 'package:flutter/material.dart';

class NodeCard extends StatelessWidget {
  final String title;
  final Offset position;
  final void Function(Offset) onDragEnd;
  final void Function()? onOutputTap;
  final void Function()? onInputTap;

  const NodeCard({
    super.key,
    required this.title,
    required this.position,
    required this.onDragEnd,
    this.onOutputTap,
    this.onInputTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: position.dy,
      left: position.dx,
      child: Draggable(
        feedback: _buildCard(0.6),
        childWhenDragging: _buildCard(0.2),
        onDragEnd: (details) => onDragEnd(details.offset),
        child: _buildCard(1.0),
      ),
    );
  }

  Widget _buildCard(double opacity) {
    return Opacity(
      opacity: opacity,
      child: Stack(
        children: [
          Card(
            color: Colors.blueGrey.shade800,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 180,
              height: 100,
              child: Center(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: -8,
            child: GestureDetector(
              onTap: onInputTap,
              child: _portDot(Colors.orange),
            ),
          ),
          Positioned(
            top: 40,
            right: -8,
            child: GestureDetector(
              onTap: onOutputTap,
              child: _portDot(Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _portDot(Color color) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white),
      ),
    );
  }
}
