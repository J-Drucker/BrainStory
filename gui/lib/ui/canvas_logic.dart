import 'dart:convert';
import 'package:flutter/material.dart';

import '../model/node.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';

import '../nodes/node_registry.dart';
import '../nodes/node_type.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/psd_node.dart';
import '../nodes/import_node.dart';
import '../nodes/debug_output_node.dart';

import 'node_card.dart';
import 'connection_painter.dart';

import 'package:file_selector/file_selector.dart';

class CanvasLogic {
  // ---- UI callback ----
  final void Function()? onUpdate;

  CanvasLogic({this.onUpdate});

  void update() => onUpdate?.call();

  // ---- Datasets ----

  /// All known datasets in the workspace, keyed by datasetId
  final Map<String, Dataset> datasets = {};

  /// Add EDF (and later other) files to the dataset catalog
  Future<void> pickFiles() async {
    final typeGroup = XTypeGroup(label: 'EDF', extensions: ['edf', 'EDF']);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);

    // existing filenames (case-insensitive)
    final existing = datasets.values
        .map((d) => d.label.toLowerCase())
        .toSet();

    for (final f in files) {
      final name = f.name;
      if (existing.contains(name.toLowerCase())) continue;

      final id = 'ds_${DateTime.now().microsecondsSinceEpoch}';
      datasets[id] = Dataset(
        id,
        label: name,
        path: f.path,
      );

      existing.add(name.toLowerCase());
    }

    update();
  }

  List<String> get datasetIds => datasets.keys.toList();

  // ---- Graph data ----

  final List<NodeModel> nodes = [];
  final List<Map<String, dynamic>> connections = [];

  String? selectedNodeId;

  // Pending connection (click-to-connect)
  String? _pendingFromNodeId;
  int? _pendingFromPortIndex;
  PortType? _pendingFromPortType;

  // ---- Node Management ----

  void addNode(NodeType type) {
    nodes.add(
      NodeModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        position: const Offset(100, 100),
        params: Map<String, dynamic>.from(type.defaultParams),
      ),
    );
    update();
  }

  void addNodeOfType(NodeType type) => addNode(type);

  void clearAll() {
    nodes.clear();
    connections.clear();
    selectedNodeId = null;
    _clearPendingConnection();
    update();
  }

  void clearSelection() {
    selectedNodeId = null;
    update();
  }

  void deleteSelected() {
    if (selectedNodeId == null) return;

    final id = selectedNodeId;
    nodes.removeWhere((n) => n.id == id);
    connections.removeWhere((c) => c['fromNode'] == id || c['toNode'] == id);

    for (var n in nodes) {
      n.parentNodeIds.remove(id);
      n.childNodeIds.remove(id);
    }

    selectedNodeId = null;
    _clearPendingConnection();
    update();
  }

  void _clearPendingConnection() {
    _pendingFromNodeId = null;
    _pendingFromPortIndex = null;
    _pendingFromPortType = null;
  }

  // ---- Graph Topology ----

  void addConnection({
    required String fromNode,
    required int fromPort,
    required String toNode,
    required int toPort,
  }) {
    connections.add({
      'fromNode': fromNode,
      'fromPort': fromPort,
      'toNode': toNode,
      'toPort': toPort,
    });

    final parent = nodes.firstWhere((n) => n.id == fromNode);
    final child = nodes.firstWhere((n) => n.id == toNode);

    parent.childNodeIds.add(child.id);
    child.parentNodeIds.add(parent.id);

    update();
  }

  // ---- Dataset State Machine ----

  /// A dataset appears at a node (usually from Import)
  void onDatasetArrive(String datasetId, NodeModel node) {
    node.datasetStates[datasetId] = DatasetState.ready;
    _notifyChildren(datasetId, node.id);
    update();
  }

  /// A node has finished processing datasetId
  void onNodeComplete(String datasetId, NodeModel node) {
    node.datasetStates[datasetId] = DatasetState.done;
    _notifyChildren(datasetId, node.id);
    update();
  }

  /// Parent → child propagation: READY/STAALE logic
  void _notifyChildren(String datasetId, String parentId) {
    final parent = nodes.firstWhere((n) => n.id == parentId);

    for (var childId in parent.childNodeIds) {
      final child = nodes.firstWhere((n) => n.id == childId);

      child.datasetStates.putIfAbsent(datasetId, () => DatasetState.notReady);

      final allParentsDone = child.parentNodeIds.every((pId) {
        final p = nodes.firstWhere((n) => n.id == pId);
        return p.datasetStates[datasetId] == DatasetState.done;
      });

      if (allParentsDone) {
        if (child.datasetStates[datasetId] == DatasetState.done) {
          child.datasetStates[datasetId] = DatasetState.stale;
        } else {
          child.datasetStates[datasetId] = DatasetState.ready;
        }
      }
    }
  }

  /// Params on a node changed → mark its datasets stale and propagate
  void onParamsChanged(NodeModel node) {
    node.datasetStates.updateAll((_, __) => DatasetState.stale);
    _propagateStale(node);
    update();
  }

  void _propagateStale(NodeModel node) {
    for (var childId in node.childNodeIds) {
      final child = nodes.firstWhere((n) => n.id == childId);

      child.datasetStates.updateAll((_, state) {
        return state == DatasetState.done ? DatasetState.stale : state;
      });

      _propagateStale(child);
    }
  }

  // ---- Manual Dataset Injection (for testing) ----

  int _manualDatasetCounter = 0;

  void addManualDataset() {
    final datasetId = 'ds_${_manualDatasetCounter++}';
    final ds = Dataset(
      datasetId,
      label: datasetId,
    );
    datasets[datasetId] = ds;

    for (var node in nodes) {
      if (node.parentNodeIds.isEmpty) {
        onDatasetArrive(datasetId, node);
      }
    }
  }

  // ---- Execution Hooks ----

  Future<void> runThis(NodeModel node) async {
    // Special case: Import node introduces datasets
    if (node.type.title == 'Import') {
      final selected =
      Set<String>.from(node.params['selectedDatasetIds'] ?? const []);

      for (final dsId in selected) {
        final ds = datasets[dsId];
        if (ds == null) continue;

        // Load dataset (stubbed)
        await node.type.run(ds, node.params);

        // Mark as done on this node
        node.datasetStates[dsId] = DatasetState.done;

        // Notify immediate children
        _notifyChildren(dsId, node.id);
      }

      update();
      return;
    }

    // ---- All other nodes ----

    for (final dsId in node.datasetStates.keys.toList()) {
      final state = node.datasetStates[dsId];

      if (state == DatasetState.ready || state == DatasetState.stale) {
        final ds = datasets[dsId];
        if (ds == null) continue;

        await node.type.run(ds, node.params);
        node.datasetStates[dsId] = DatasetState.done;

        _notifyChildren(dsId, node.id);
      }
    }

    update();
  }


  void runFromStart(NodeModel node) {
    // TODO: execute from pipeline start to this node
    debugPrint('runFromStart: ${node.title}');
  }

  void runToEnd(NodeModel node) {
    // TODO: execute from this node to end
    debugPrint('runToEnd: ${node.title}');
  }

  // ---- Export ----

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
          'datasets': n.datasetStates.map(
                (k, v) => MapEntry(k.toString(), v.toString()),
          ),
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



  // ---- Port Geometry Helpers ----

  static const double _cardWidth = 160;
  static const double _cardHeight = 80;

  Offset _outputPortPosition(NodeModel node, int portIndex) {
    final n = node.outputPorts.length;
    if (n == 0) {
      return Offset(node.position.dx + _cardWidth / 2, node.position.dy + _cardHeight + 4);
    }
    final step = _cardWidth / (n + 1);
    final x = node.position.dx + step * (portIndex + 1);
    final y = node.position.dy + _cardHeight + 4;
    return Offset(x, y);
  }

  Offset _inputPortPosition(NodeModel node, int portIndex) {
    final n = node.inputPorts.length;
    if (n == 0) {
      return Offset(node.position.dx + _cardWidth / 2, node.position.dy - 4);
    }
    final step = _cardWidth / (n + 1);
    final x = node.position.dx + step * (portIndex + 1);
    final y = node.position.dy - 4;
    return Offset(x, y);
  }

  // ---- Connection UI ----

  List<Widget> connectionWidgets() {
    return connections.map<Widget>((c) {
      final fromNode = nodes.firstWhere((n) => n.id == c['fromNode']);
      final toNode = nodes.firstWhere((n) => n.id == c['toNode']);
      final start = _outputPortPosition(fromNode, c['fromPort']);
      final end = _inputPortPosition(toNode, c['toPort']);

      return CustomPaint(
        painter: ConnectionPainter(start: start, end: end),
        size: Size.infinite,
      );
    }).toList();
  }

  // ---- Node Color Mapping ----

  Color _colorFor(NodeModel n) {
    switch (n.visualState) {
      case DatasetState.notReady:
        return Colors.grey[700]!;
      case DatasetState.ready:
        return Colors.blue[700]!;
      case DatasetState.done:
        return Colors.green[700]!;
      case DatasetState.stale:
        return Colors.orange[700]!;
    }
  }

  // ---- Node Widgets ----

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
        color: _colorFor(node),
        onDragEnd: (offset) {
          node.position = offset;
          update();
        },
        onTap: () {
          selectedNodeId = node.id;
          update();
        },
        onDoubleTap: () {
          showDialog(
            context: context,
            builder: (_) => node.type.buildConfigWidget(
              node.params,
                  (p) {
                node.params = p;
                onParamsChanged(node);
                update();
              },
              datasets: datasets,
            ),
          );
        },
        onRunThis: () async {
          await runThis(node);
        },
        onRunFromStart: () {
          runFromStart(node);
        },
        onRunToEnd: () {
          runToEnd(node);
        },
        onEditParams: () {
          showDialog(
            context: context,
            builder: (_) => node.type.buildConfigWidget(
              node.params,
                  (p) {
                node.params = p;
                onParamsChanged(node);
                update();
              },
              datasets: datasets,
            ),
          );
        },
        onDelete: () {
          selectedNodeId = node.id;
          deleteSelected();
        },
        onInputPortTap: (portIndex) {
          if (_pendingFromNodeId == null) return;

          if (_pendingFromNodeId == node.id) {
            _clearPendingConnection();
            update();
            return;
          }

          final fromNode = nodes.firstWhere((n) => n.id == _pendingFromNodeId);

          final outType =
              fromNode.outputPorts[_pendingFromPortIndex!].type;
          final inType = node.inputPorts[portIndex].type;

          if (outType != inType) {
            _clearPendingConnection();
            update();
            return;
          }

          addConnection(
            fromNode: fromNode.id,
            fromPort: _pendingFromPortIndex!,
            toNode: node.id,
            toPort: portIndex,
          );

          _clearPendingConnection();
        },
        onOutputPortTap: (portIndex) {
          _pendingFromNodeId = node.id;
          _pendingFromPortIndex = portIndex;
          _pendingFromPortType = node.outputPorts[portIndex].type;
          update();
        },
      );
    }).toList();
  }

  List<NodeRegistryEntry> entriesForGroup(NodeGroup group) {
    return NodeRegistry.entries.where((e) => e.group == group).toList();
  }
}
