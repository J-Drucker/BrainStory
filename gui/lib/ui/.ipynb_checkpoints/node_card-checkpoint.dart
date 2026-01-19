import 'package:flutter/material.dart';

class NodeCard extends StatelessWidget {
  final String title;
  final Offset position;
  final void Function(Offset) onDragEnd;
  final void Function()? onTap;
  final void Function()? onLongPress;
  final bool showPorts;

  const NodeCard({
    super.key,
    required this.title,
    required this.position,
    required this.onDragEnd,
    this.onTap,
    this.onLongPress,
    this.showPorts = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTap: onLongPress,
        child: Draggable(
          feedback: _buildCard(),
          childWhenDragging: Opacity(opacity: 0.5, child: _buildCard()),
          onDragEnd: (details) => onDragEnd(details.offset),
          child: _buildCard(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Stack(
      children: [
        Card(
          elevation: 6,
          color: Colors.blueGrey[800],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Text(title, style: const TextStyle(color: Colors.white)),
          ),
        ),
        if (showPorts) ...[
          const Positioned(
            top: -8,
            left: 60,
            child: _PortDot(),
          ),
          const Positioned(
            bottom: -8,
            left: 60,
            child: _PortDot(),
          ),
        ],
      ],
    );
  }
}

class _PortDot extends StatelessWidget {
  const _PortDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1),
      ),
    );
  }
}
