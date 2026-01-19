import 'package:flutter/material.dart';
import '../model/node.dart';
import '../model/connection.dart';
import 'node_card.dart';
import 'connection_painter.dart';

class BrainStoryCanvas extends StatefulWidget {
  const BrainStoryCanvas({super.key});

  @override
  State<BrainStoryCanvas> createState() => _BrainStoryCanvasState();
}

class _BrainStoryCanvasState extends State<BrainStoryCanvas> {
  final List<NodeModel> nodes = [
    NodeModel(id: '1', title: 'Bandpass Filter', position: const Offset(100, 100)),
    NodeModel(id: '2', title: 'PSD', position: const Offset(300, 200)),
  ];

  final List<Connection> connections = [
    Connection(fromNodeId: '1', toNodeId: '2'),
  ];

  void _updateNodePosition(String id, Offset newOffset) {
    setState(() {
      final node = nodes.firstWhere((n) => n.id == id);
      node.position = newOffset;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Draw wires first
        ...connections.map((conn) {
          final from = nodes.firstWhere((n) => n.id == conn.fromNodeId).position;
          final to = nodes.firstWhere((n) => n.id == conn.toNodeId).position;
          final start = Offset(from.dx + 180, from.dy + 50); // output
          final end = Offset(to.dx, to.dy + 50); // input

          return CustomPaint(
            painter: ConnectionPainter(start: start, end: end),
          );
        }),

        // Then draw node cards
        ...nodes.map((node) => NodeCard(
              title: node.title,
              position: node.position,
              onDragEnd: (offset) => _updateNodePosition(node.id, offset),
              onOutputTap: () => print('Tapped output on ${node.id}'),
              onInputTap: () => print('Tapped input on ${node.id}'),
            )),
      ],
    );
  }
}
