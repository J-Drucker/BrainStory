// Updated canvas_logic.dart with NodeType registry integration
import 'package:flutter/material.dart';
import '../model/node.dart';
import '../nodes/node_type.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/psd_node.dart';
import 'node_card.dart';
import 'connection_painter.dart';
import 'node_config.dart';
import 'dart:convert';

class CanvasLogic {
  // 1. Node type registry
  final List<NodeType> availableNodes = [
    BandpassNodeType(),
    PSDNodeType(),
  ];

  final List<NodeModel> nodes = [];
  final List<Map<String, String>> connections = [];
  String? startConnectionId;
  String? selectedNodeId;

  // 2. Add node using NodeType
  void addNode(NodeType type) {
      nodes.add(NodeModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        position: const Offset(100, 100),
        params: Map<String, dynamic>.from(type.defaultParams),
      ));
    }


  void clearAll() {
    nodes.clear();
    connections.clear();
    selectedNodeId = null;
    startConnectionId = null;
  }

  void deleteSelected() {
    if (selectedNodeId == null) return;
    nodes.removeWhere((n) => n.id == selectedNodeId);
    connections.removeWhere((c) => c['from'] == selectedNodeId || c['to'] == selectedNodeId);
    startConnectionId = null;
    selectedNodeId = null;
  }

  void clearConnection() => startConnectionId = null;

  // 3. JSON export now includes type and params
  void export(BuildContext context) {
    final jsonMap = {
      'nodes': nodes.map((n) => {
            'id': n.id,
            'type': n.type.title,
            'x': n.position.dx,
            'y': n.position.dy,
            'params': n.params,
          }).toList(),
      'connections': connections,
    };

    final output = const JsonEncoder.withIndent('  ').convert(jsonMap);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exported JSON'),
        content: SingleChildScrollView(child: SelectableText(output)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  // 4. Sidebar auto-builds from registry
  Widget sidebar({required VoidCallback export, required VoidCallback clear, required VoidCallback update}) {
    return Container(
      width: 200,
      color: Colors.grey[900],
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Text('Nodes', style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 10),
          for (var type in availableNodes)
            ElevatedButton(
              onPressed: () {
                addNode(type);
                update();
              },
              child: Text('+ ${type.title}'),
            ),
          const Spacer(),
          ElevatedButton(onPressed: export, child: const Text('Export JSON')),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: clear, child: const Text('Clear All')),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<Widget> connectionWidgets() {
    return connections.map((c) {
      final from = nodes.firstWhere((n) => n.id == c['from']).position;
      final to = nodes.firstWhere((n) => n.id == c['to']).position;
      return CustomPaint(
        painter: ConnectionPainter(
          start: Offset(from.dx + 60, from.dy + 80),
          end: Offset(to.dx + 60, to.dy - 8),
        ),
        size: Size.infinite,
      );
    }).toList();
  }

  List<Widget> nodeWidgets({required BuildContext context, required VoidCallback update}) {
    return nodes.map((node) {
      return NodeCard(
        title: node.title,
        position: node.position,
        showPorts: true,
        onDragEnd: (offset) {
          node.position = offset;
          update();
        },
        onTap: () {
          if (startConnectionId == null) {
            startConnectionId = node.id;
          } else if (startConnectionId != node.id) {
            connections.add({'from': startConnectionId!, 'to': node.id});
            startConnectionId = null;
          }
          selectedNodeId = node.id;
          update();
        },
        onLongPress: () {
          selectedNodeId = node.id;
          deleteSelected();
          update();
        },
        // 5. NodeType handles its own config
        onDoubleTap: () {
          showDialog(
            context: context,
            builder: (_) => node.type.buildConfigWidget(node.params, (p) {
              node.params = p;
              update();
            }),
          );
        },
      );
    }).toList();
  }
}