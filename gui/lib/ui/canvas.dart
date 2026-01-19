import 'package:flutter/material.dart';
import '../model/node.dart';
import 'node_card.dart';
import 'connection_painter.dart';

class BrainStoryCanvas extends StatefulWidget {
  const BrainStoryCanvas({super.key});

  @override
  State<BrainStoryCanvas> createState() => _BrainStoryCanvasState();
}

class _BrainStoryCanvasState extends State<BrainStoryCanvas> {
  final List<NodeModel> nodes = [
    NodeModel(id: '1', title: 'Bandpass Filter', position: const Offset(100, 150)),
    NodeModel(id: '2', title: 'PSD', position: const Offset(400, 250)),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          painter: ConnectionPainter(start: nodes[0].position, end: nodes[1].position),
          size: Size.infinite,
        ),
        ...nodes.map((node) => NodeCard(
              title: node.title,
              position: node.position,
              onDragEnd: (offset) {
                setState(() {
                  node.position = offset;
                });
              },
            )),
      ],
    );
  }
}