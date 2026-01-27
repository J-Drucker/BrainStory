import 'dart:convert';
import 'package:flutter/material.dart';
import '../model/node.dart';
import '../nodes/node_type.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/psd_node.dart';
import 'node_card.dart';
import 'connection_painter.dart';
import 'node_config.dart'; // if still used anywhere

class CanvasLogic {
  // Registry of available node types
  final List<NodeType> availableNodes = [
    BandpassNodeType(),
    PSDNodeType(),
  ];

  final List<NodeModel> nodes = [];

  /// Each connection tracks node + port indices
  final List<Map<String, dynamic>> connections = [];

  String? selectedNodeId;

  // Pending connection (from output port)
  String? _pendingFromNodeId;
  int? _pendingFromPortIndex;
  PortType? _pendingFromPortType;

  // --- Node management ---

  void addNode(NodeType type) {
    nodes.add(
      NodeModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        position: const Offset(100, 100),
        params: Map<String, dynamic>.from(type.defaultParams),
      ),
    );
  }

  void clearAll() {
    nodes.clear();
    connections.clear();
    selectedNodeId = null;
    _clearPendingConnection();
  }

  void deleteSelected() {
    if (selectedNodeId == null) return;
    nodes.removeWhere((n) => n.id == selectedNodeId);
    connections.removeWhere((c) =>
    c['fromNode'] == selectedNodeId || c['toNode'] == selectedNodeId);
    selectedNodeId = null;
    _clearPendingConnection();
  }

  void _clearPendingConnection() {
    _pendingFromNodeId = null;
    _pendingFromPortIndex = null;
    _pendingFromPortType = null;
  }

  void clearConnection() => _clearPendingConnection();

  // --- Export ---

  void export(BuildContext context) {
    final jsonMap = {
      'nodes': nodes
          .map(
            (n) => {
          'id': n.id,
          'type': n.type.title,
          'x': n.position.dx,
          'y': n.position.dy,
          'params': n.params,
          'inputs': n.inputPorts
              .map((p) => {'name': p.name, 'type': p.type.toString()})
              .toList(),
          'outputs': n.outputPorts
              .map((p) => {'name': p.name, 'type': p.type.toString()})
              .toList(),
        },
      )
          .toList(),
      'connections': connections,
    };

    final output = const JsonEncoder.withIndent('  ').convert(jsonMap);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exported JSON'),
        content: SingleChildScrollView(child: SelectableText(output)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // --- Sidebar ---

  Widget sidebar({
    required VoidCallback export,
    required VoidCallback clear,
    required VoidCallback update,
  }) {
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

  // --- Connection rendering ---

  static const double _cardWidth = 160;
  static const double _cardHeight = 80;

  Offset _outputPortPosition(NodeModel node, int portIndex) {
    final n = node.outputPorts.length;
    final step = _cardWidth / (n + 1);
    final x = node.position.dx + step * (portIndex + 1);
    final y = node.position.dy + _cardHeight + 4;
    return Offset(x, y);
  }

  Offset _inputPortPosition(NodeModel node, int portIndex) {
    final n = node.inputPorts.length;
    final step = _cardWidth / (n + 1);
    final x = node.position.dx + step * (portIndex + 1);
    final y = node.position.dy - 4;
    return Offset(x, y);
  }

  List<Widget> connectionWidgets() {
    return connections.map((c) {
      final fromNodeId = c['fromNode'] as String;
      final toNodeId = c['toNode'] as String;
      final fromPort = c['fromPort'] as int;
      final toPort = c['toPort'] as int;

      final fromNode = nodes.firstWhere((n) => n.id == fromNodeId);
      final toNode = nodes.firstWhere((n) => n.id == toNodeId);

      final start = _outputPortPosition(fromNode, fromPort);
      final end = _inputPortPosition(toNode, toPort);

      return CustomPaint(
        painter: ConnectionPainter(start: start, end: end),
        size: Size.infinite,
      );
    }).toList();
  }

  // --- Node widgets ---

  List<Widget> nodeWidgets({
    required BuildContext context,
    required VoidCallback update,
  }) {
    return nodes.map((node) {
      return NodeCard(
        title: node.title,
        position: node.position,
        inputPorts: node.inputPorts,
        outputPorts: node.outputPorts,
        onDragEnd: (offset) {
          node.position = offset;
          update();
        },
        onTap: () {
          selectedNodeId = node.id;
          update();
        },
        onLongPress: () {
          selectedNodeId = node.id;
          deleteSelected();
          update();
        },
        onDoubleTap: () {
          showDialog(
            context: context,
            builder: (_) => node.type.buildConfigWidget(
              node.params,
                  (p) {
                node.params = p;
                update();
              },
            ),
          );
        },
        onInputPortTap: (portIndex) {
          // Only complete a connection if we have a pending output
          if (_pendingFromNodeId == null ||
              _pendingFromPortIndex == null ||
              _pendingFromPortType == null) {
            return;
          }

          if (_pendingFromNodeId == node.id) {
            // no self-connections for now
            _clearPendingConnection();
            return;
          }

          final targetPort = node.inputPorts[portIndex];
          if (targetPort.type != _pendingFromPortType) {
            // type mismatch -> cancel pending
            _clearPendingConnection();
            return;
          }

          // Add connection
          connections.add({
            'fromNode': _pendingFromNodeId!,
            'fromPort': _pendingFromPortIndex!,
            'toNode': node.id,
            'toPort': portIndex,
          });

          _clearPendingConnection();
          update();
        },
        onOutputPortTap: (portIndex) {
          // Start or change pending connection from this output
          _pendingFromNodeId = node.id;
          _pendingFromPortIndex = portIndex;
          _pendingFromPortType = node.outputPorts[portIndex].type;
          update();
        },
      );
    }).toList();
  }
}
