// Step 6: Ports top & bottom + wires target port centers

import 'dart:convert';
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

  String? startConnectionId;
  final List<Map<String, String>> connections = [];
  String? selectedNodeId;

  void addNode(String title) {
    final newNode = NodeModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      position: const Offset(100, 100),
    );
    setState(() => nodes.add(newNode));
  }

  void exportNodesAsJson() {
    final nodeList = nodes.map((node) => {
      'id': node.id,
      'title': node.title,
      'x': node.position.dx,
      'y': node.position.dy,
    }).toList();

    final connectionList = connections.map((c) => {
      'from': c['from'],
      'to': c['to'],
    }).toList();

    final output = {
      'nodes': nodeList,
      'connections': connectionList,
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(output);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Exported JSON"),
        content: SingleChildScrollView(child: SelectableText(jsonStr)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  void clearAll() {
    setState(() {
      nodes.clear();
      connections.clear();
      selectedNodeId = null;
      startConnectionId = null;
    });
  }

  void deleteNode(String nodeId) {
    setState(() {
      nodes.removeWhere((n) => n.id == nodeId);
      connections.removeWhere((c) => c['from'] == nodeId || c['to'] == nodeId);
      if (selectedNodeId == nodeId) selectedNodeId = null;
      if (startConnectionId == nodeId) startConnectionId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (event) {
        if (event.logicalKey.keyLabel == 'Delete' && selectedNodeId != null) {
          deleteNode(selectedNodeId!);
        }
      },
      child: Row(
        children: [
          Container(
            width: 200,
            color: Colors.grey[900],
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Add Node', style: TextStyle(color: Colors.white, fontSize: 18)),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: () => addNode("Bandpass Filter"), child: const Text("+ Bandpass")),
                ElevatedButton(onPressed: () => addNode("PSD"), child: const Text("+ PSD")),
                const Spacer(),
                ElevatedButton(onPressed: exportNodesAsJson, child: const Text("Export JSON")),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: clearAll, child: const Text("Clear All")),
                const SizedBox(height: 20),
              ],
            ),
          ),

          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => startConnectionId = null),
              child: Stack(
                children: [
                  ...connections.map((c) {
                    final startNode = nodes.firstWhere((n) => n.id == c['from']);
                    final endNode = nodes.firstWhere((n) => n.id == c['to']);

                    final start = Offset(
                      startNode.position.dx + 60, // center-ish horizontally
                      startNode.position.dy - 8,   // top port
                    );

                    final end = Offset(
                      endNode.position.dx + 60,
                      endNode.position.dy + 80, // bottom port (card ~64 tall)
                    );

                    return CustomPaint(
                      painter: ConnectionPainter(start: start, end: end),
                      size: Size.infinite,
                    );
                  }),
                  ...nodes.map((node) => NodeCard(
                        title: node.title,
                        position: node.position,
                        onDragEnd: (offset) {
                          setState(() => node.position = offset);
                        },
                        onTap: () {
                          if (startConnectionId == null) {
                            setState(() => startConnectionId = node.id);
                          } else if (startConnectionId != node.id) {
                            setState(() {
                              connections.add({'from': startConnectionId!, 'to': node.id});
                              startConnectionId = null;
                            });
                          }
                          setState(() => selectedNodeId = node.id);
                        },
                        onLongPress: () => deleteNode(node.id),
                        showPorts: true,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}