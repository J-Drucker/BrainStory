import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/dataset.dart';
import '../model/dataset_state.dart';
import '../model/node.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/debug_output_node.dart';
import '../nodes/import_node.dart';
import '../nodes/node_type.dart';
import '../nodes/psd_node.dart';
import '../nodes/visualization_node.dart';
import 'connection_painter.dart';
import 'node_card.dart';

class CanvasLogic {
  CanvasLogic();

  /// Registry of available node types in the sidebar.
  final List<NodeType> availableNodes = <NodeType>[
    ImportNodeType(),
    BandpassNodeType(),
    PSDNodeType(),
    VisualizationNodeType(),
    DebugOutputNodeType(),
  ];

  final List<NodeModel> nodes = <NodeModel>[];
  final Map<String, Dataset> datasets = <String, Dataset>{};

  /// Connection schema:
  /// {
  ///   fromNode: String,
  ///   fromPort: int,
  ///   toNode: String,
  ///   toPort: int,
  /// }
  final List<Map<String, dynamic>> connections = <Map<String, dynamic>>[];

  String? selectedNodeId;

  String? _pendingFromNodeId;
  int? _pendingFromPortIndex;
  PortType? _pendingFromPortType;

  static const double _cardWidth = 160;
  static const double _cardHeight = 80;

  void addNode(NodeType type) {
    nodes.add(
      NodeModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
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

  Future<void> pickFiles() async {
    final List<XFile> files = await openFiles();

    for (final XFile file in files) {
      final Dataset dataset = datasets.putIfAbsent(
        file.path,
        () => Dataset(
          DateTime.now().microsecondsSinceEpoch.toString(),
          label: file.name,
          path: file.path,
        ),
      );
      dataset.label = file.name;
      dataset.path = file.path;
      _markAllNodes(dataset.id, DatasetState.notReady);
    }
  }

  void deleteSelected() {
    final targetId = selectedNodeId;
    if (targetId == null) return;

    nodes.removeWhere((node) => node.id == targetId);
    connections.removeWhere(
          (connection) =>
      connection['fromNode'] == targetId || connection['toNode'] == targetId,
    );

    selectedNodeId = null;
    _clearPendingConnection();
  }

  void clearConnectionDraft() {
    _clearPendingConnection();
  }

  void _clearPendingConnection() {
    _pendingFromNodeId = null;
    _pendingFromPortIndex = null;
    _pendingFromPortType = null;
  }

  void export(BuildContext context) {
    final Map<String, dynamic> jsonMap = <String, dynamic>{
      'nodes': nodes
          .map(
            (node) => <String, dynamic>{
          'id': node.id,
          'type': node.type.title,
          'x': node.position.dx,
          'y': node.position.dy,
          'params': node.params,
          'inputs': node.inputPorts
              .map(
                (port) => <String, dynamic>{
              'name': port.name,
              'type': port.type.name,
            },
          )
              .toList(),
          'outputs': node.outputPorts
              .map(
                (port) => <String, dynamic>{
              'name': port.name,
              'type': port.type.name,
            },
          )
              .toList(),
        },
      )
          .toList(),
      'connections': connections,
    };

    final String output = const JsonEncoder.withIndent('  ').convert(jsonMap);

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exported JSON'),
        content: SingleChildScrollView(
          child: SelectableText(output),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget sidebar({
    required VoidCallback export,
    required VoidCallback clear,
    required VoidCallback update,
  }) {
    return Container(
      width: 220,
      color: Colors.grey[900],
      child: Column(
        children: <Widget>[
          const SizedBox(height: 20),
          const Text(
            'Nodes',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 10),
          for (final NodeType type in availableNodes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    addNode(type);
                    update();
                  },
                  child: Text('+ ${type.title}'),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: export,
                child: const Text('Export JSON'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: clear,
                child: const Text('Clear All'),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<Widget> connectionWidgets() {
    return connections.map((Map<String, dynamic> connection) {
      final NodeModel? fromNode = _findNode(connection['fromNode'] as String);
      final NodeModel? toNode = _findNode(connection['toNode'] as String);

      if (fromNode == null || toNode == null) {
        return const SizedBox.shrink();
      }

      final int fromPort = connection['fromPort'] as int;
      final int toPort = connection['toPort'] as int;

      final Offset start = _outputPortPosition(fromNode, fromPort);
      final Offset end = _inputPortPosition(toNode, toPort);

      return CustomPaint(
        painter: ConnectionPainter(start: start, end: end),
        size: Size.infinite,
      );
    }).toList();
  }

  List<Widget> nodeWidgets({
    required BuildContext context,
    required VoidCallback update,
    required Offset Function(Offset globalOffset) translateDropOffset,
  }) {
    return nodes.map((NodeModel node) {
      return NodeCard(
        title: node.title,
        position: node.position,
        inputPorts: node.inputPorts,
        outputPorts: node.outputPorts,
        color: _nodeColor(node),
        statusLabel: _statusLabel(node),
        onDragEnd: (Offset globalOffset) {
          node.position = translateDropOffset(globalOffset);
          update();
        },
        onTap: () {
          selectedNodeId = node.id;
          update();
        },
        onDelete: () {
          selectedNodeId = node.id;
          deleteSelected();
          update();
        },
        onEditParams: () {
          showDialog<void>(
            context: context,
            builder: (_) => node.type.buildConfigWidget(node.params, (params) {
              node.params = params;
              for (final Dataset dataset in datasets.values) {
                node.datasetStates[dataset.id] = DatasetState.stale;
                _markDescendantsStale(node.id, dataset.id);
              }
              update();
            },
              datasets: _datasetsById(),
              availableDatasetIds: _availableDatasetIdsForNode(node),
              processedDatasetStates: _processedDatasetStatesForNode(node),
            ),
          );
        },
        onRunThis: () async {
          try {
            await runThisStep(node.id);
            update();
            if (context.mounted) {
              _showStatusSnackBar(
                context,
                _lastRunDatasetCount == 0
                    ? 'No datasets matched ${node.title}.'
                    : 'Ran ${node.title} for $_lastRunDatasetCount dataset(s).',
              );
            }
          } catch (error) {
            if (context.mounted) {
              _showStatusSnackBar(context, 'Run failed: $error');
            }
          }
        },
        onRunFromStart: () async {
          try {
            await runFromStart(node.id);
            update();
            if (context.mounted) {
              _showStatusSnackBar(
                context,
                _lastRunDatasetCount == 0
                    ? 'No datasets matched ${node.title}.'
                    : 'Ran pipeline to ${node.title} for $_lastRunDatasetCount dataset(s).',
              );
            }
          } catch (error) {
            if (context.mounted) {
              _showStatusSnackBar(context, 'Run failed: $error');
            }
          }
        },
        onRunToEnd: () async {
          try {
            await runToEnd(node.id);
            update();
            if (context.mounted) {
              _showStatusSnackBar(
                context,
                _lastRunDatasetCount == 0
                    ? 'No datasets matched ${node.title}.'
                    : 'Ran ${node.title} to pipeline end for $_lastRunDatasetCount dataset(s).',
              );
            }
          } catch (error) {
            if (context.mounted) {
              _showStatusSnackBar(context, 'Run failed: $error');
            }
          }
        },
        onInputPortTap: (int portIndex) {
          _tryCompleteConnection(
            toNode: node,
            toPortIndex: portIndex,
            onChanged: update,
          );
        },
        onOutputPortTap: (int portIndex) {
          _startConnectionFrom(
            node: node,
            outputPortIndex: portIndex,
          );
          update();
        },
      );
    }).toList();
  }

  void _startConnectionFrom({
    required NodeModel node,
    required int outputPortIndex,
  }) {
    if (outputPortIndex < 0 || outputPortIndex >= node.outputPorts.length) {
      _clearPendingConnection();
      return;
    }

    _pendingFromNodeId = node.id;
    _pendingFromPortIndex = outputPortIndex;
    _pendingFromPortType = node.outputPorts[outputPortIndex].type;
  }

  void _tryCompleteConnection({
    required NodeModel toNode,
    required int toPortIndex,
    required VoidCallback onChanged,
  }) {
    if (_pendingFromNodeId == null ||
        _pendingFromPortIndex == null ||
        _pendingFromPortType == null) {
      return;
    }

    if (toPortIndex < 0 || toPortIndex >= toNode.inputPorts.length) {
      _clearPendingConnection();
      return;
    }

    if (_pendingFromNodeId == toNode.id) {
      _clearPendingConnection();
      return;
    }

    final PortSpec targetPort = toNode.inputPorts[toPortIndex];
    if (targetPort.type != _pendingFromPortType) {
      _clearPendingConnection();
      return;
    }

    final Map<String, dynamic> nextConnection = <String, dynamic>{
      'fromNode': _pendingFromNodeId!,
      'fromPort': _pendingFromPortIndex!,
      'toNode': toNode.id,
      'toPort': toPortIndex,
    };

    final bool duplicate = connections.any(
          (connection) =>
      connection['fromNode'] == nextConnection['fromNode'] &&
          connection['fromPort'] == nextConnection['fromPort'] &&
          connection['toNode'] == nextConnection['toNode'] &&
          connection['toPort'] == nextConnection['toPort'],
    );

    if (!duplicate) {
      connections.add(nextConnection);
      onChanged();
    }

    _clearPendingConnection();
  }

  NodeModel? _findNode(String id) {
    for (final NodeModel node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  NodeModel? get selectedNode =>
      selectedNodeId == null ? null : _findNode(selectedNodeId!);

  NodeModel? get selectedVisualizationNode {
    final NodeModel? node = selectedNode;
    if (node == null || node.type is! VisualizationNodeType) {
      return null;
    }
    return node;
  }

  List<Dataset> get datasetsForSelectedVisualizationNode {
    final NodeModel? node = selectedVisualizationNode;
    if (node == null) {
      return <Dataset>[];
    }

    final Set<String> datasetIds = _datasetsForNode(node);
    return datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
  }

  int _lastRunDatasetCount = 0;

  Future<void> runThisStep(String nodeId) async {
    await _runNodeSet(<String>{nodeId});
  }

  Future<void> runFromStart(String nodeId) async {
    await _runNodeSet(_collectAncestorsInclusive(nodeId));
  }

  Future<void> runToEnd(String nodeId) async {
    await _runNodeSet(_collectDescendantsInclusive(nodeId));
  }

  Future<void> _runNodeSet(Set<String> nodeIds) async {
    final List<NodeModel> orderedNodes = _orderedNodes(nodeIds);
    if (orderedNodes.isEmpty) {
      _lastRunDatasetCount = 0;
      return;
    }

    final Set<String> datasetIds = <String>{};
    for (final NodeModel node in orderedNodes) {
      datasetIds.addAll(_datasetsForNode(node));
    }

    final List<Dataset> targetDatasets = datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList();

    _lastRunDatasetCount = targetDatasets.length;
    if (targetDatasets.isEmpty) {
      return;
    }

    for (final Dataset dataset in targetDatasets) {
      for (final NodeModel node in orderedNodes) {
        if (!_datasetsForNode(node).contains(dataset.id)) {
          continue;
        }

        node.datasetStates[dataset.id] = DatasetState.ready;
        try {
          await node.type.run(dataset, node.params);
          node.datasetStates[dataset.id] = DatasetState.done;
        } catch (_) {
          node.datasetStates[dataset.id] = DatasetState.stale;
          rethrow;
        }
      }
    }
  }

  Set<String> _datasetsForNode(NodeModel node) {
    if (datasets.isEmpty) {
      return <String>{};
    }

    if (node.type is ImportNodeType) {
      final Set<String> availableDatasetIds = datasets.values
          .map((Dataset dataset) => dataset.id)
          .toSet();
      return _selectedDatasetIdsForNode(node, availableDatasetIds);
    }

    final Set<String> upstreamImports = <String>{};
    final Set<String> visited = <String>{};
    _collectUpstreamImports(node.id, upstreamImports, visited);

    if (upstreamImports.isEmpty) {
      return <String>{};
    }

    final Set<String> datasetIds = <String>{};
    for (final String importNodeId in upstreamImports) {
      final NodeModel? importNode = _findNode(importNodeId);
      if (importNode == null) continue;
      final List<dynamic> selectedDatasetIds =
          (importNode.params['selectedDatasetIds'] as List<dynamic>? ??
              <dynamic>[]);
      for (final Dataset dataset in datasets.values) {
        if (selectedDatasetIds.contains(dataset.id) ||
            selectedDatasetIds.contains(dataset.path)) {
          datasetIds.add(dataset.id);
        }
      }
    }
    return _selectedDatasetIdsForNode(node, datasetIds);
  }

  Map<String, Dataset> _datasetsById() {
    return <String, Dataset>{
      for (final Dataset dataset in datasets.values) dataset.id: dataset,
    };
  }

  Set<String> _availableDatasetIdsForNode(NodeModel node) {
    if (node.type is ImportNodeType) {
      return datasets.values.map((Dataset dataset) => dataset.id).toSet();
    }

    final List<NodeModel> parents = _immediateParents(node.id);
    if (parents.isEmpty) {
      return <String>{};
    }

    return datasets.values
        .where((Dataset dataset) {
          return parents.every(
            (NodeModel parent) => parent.datasetStates[dataset.id] == DatasetState.done,
          );
        })
        .map((Dataset dataset) => dataset.id)
        .toSet();
  }

  Map<String, DatasetState> _processedDatasetStatesForNode(NodeModel node) {
    return <String, DatasetState>{
      for (final Dataset dataset in datasets.values)
        dataset.id: node.datasetStates[dataset.id] ?? DatasetState.notReady,
    };
  }

  Set<String> _selectedDatasetIdsForNode(
    NodeModel node,
    Set<String> availableDatasetIds,
  ) {
    final List<dynamic> selectedDatasetIds =
        (node.params['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[]);
    if (selectedDatasetIds.isEmpty) {
      return Set<String>.from(availableDatasetIds);
    }

    final Set<String> resolvedSelection = <String>{};
    for (final Dataset dataset in datasets.values) {
      if (selectedDatasetIds.contains(dataset.id) ||
          selectedDatasetIds.contains(dataset.path)) {
        resolvedSelection.add(dataset.id);
      }
    }
    return resolvedSelection.intersection(availableDatasetIds);
  }

  List<NodeModel> _immediateParents(String nodeId) {
    final List<NodeModel> parents = <NodeModel>[];
    for (final Map<String, dynamic> connection in connections) {
      if (connection['toNode'] != nodeId) continue;
      final NodeModel? parent = _findNode(connection['fromNode'] as String);
      if (parent != null) {
        parents.add(parent);
      }
    }
    return parents;
  }

  List<NodeModel> _orderedNodes(Set<String> nodeIds) {
    final Map<String, int> inDegree = <String, int>{
      for (final String id in nodeIds) id: 0,
    };

    for (final Map<String, dynamic> connection in connections) {
      final String fromNode = connection['fromNode'] as String;
      final String toNode = connection['toNode'] as String;
      if (nodeIds.contains(fromNode) && nodeIds.contains(toNode)) {
        inDegree[toNode] = (inDegree[toNode] ?? 0) + 1;
      }
    }

    final List<String> queue = nodes
        .map((NodeModel node) => node.id)
        .where((String id) => nodeIds.contains(id) && inDegree[id] == 0)
        .toList();
    final List<String> orderedIds = <String>[];

    while (queue.isNotEmpty) {
      final String current = queue.removeAt(0);
      orderedIds.add(current);

      for (final Map<String, dynamic> connection in connections) {
        if (connection['fromNode'] != current) continue;
        final String target = connection['toNode'] as String;
        if (!nodeIds.contains(target)) continue;

        inDegree[target] = (inDegree[target] ?? 1) - 1;
        if (inDegree[target] == 0) {
          queue.add(target);
        }
      }
    }

    for (final NodeModel node in nodes) {
      if (nodeIds.contains(node.id) && !orderedIds.contains(node.id)) {
        orderedIds.add(node.id);
      }
    }

    return orderedIds
        .map(_findNode)
        .whereType<NodeModel>()
        .toList(growable: false);
  }

  Set<String> _collectAncestorsInclusive(String nodeId) {
    final Set<String> result = <String>{nodeId};
    final List<String> stack = <String>[nodeId];

    while (stack.isNotEmpty) {
      final String current = stack.removeLast();
      for (final Map<String, dynamic> connection in connections) {
        if (connection['toNode'] != current) continue;
        final String parentId = connection['fromNode'] as String;
        if (result.add(parentId)) {
          stack.add(parentId);
        }
      }
    }

    return result;
  }

  Set<String> _collectDescendantsInclusive(String nodeId) {
    final Set<String> result = <String>{nodeId};
    final List<String> stack = <String>[nodeId];

    while (stack.isNotEmpty) {
      final String current = stack.removeLast();
      for (final Map<String, dynamic> connection in connections) {
        if (connection['fromNode'] != current) continue;
        final String childId = connection['toNode'] as String;
        if (result.add(childId)) {
          stack.add(childId);
        }
      }
    }

    return result;
  }

  void _collectUpstreamImports(
    String nodeId,
    Set<String> imports,
    Set<String> visited,
  ) {
    if (!visited.add(nodeId)) {
      return;
    }

    final NodeModel? node = _findNode(nodeId);
    if (node?.type is ImportNodeType) {
      imports.add(nodeId);
    }

    for (final Map<String, dynamic> connection in connections) {
      if (connection['toNode'] != nodeId) continue;
      _collectUpstreamImports(connection['fromNode'] as String, imports, visited);
    }
  }

  void _markAllNodes(String datasetId, DatasetState state) {
    for (final NodeModel node in nodes) {
      node.datasetStates[datasetId] = state;
    }
  }

  void _markDescendantsStale(String nodeId, String datasetId) {
    for (final String descendantId in _collectDescendantsInclusive(nodeId)) {
      _findNode(descendantId)?.datasetStates[datasetId] = DatasetState.stale;
    }
  }

  void _showStatusSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Color _nodeColor(NodeModel node) {
    if (node.id == selectedNodeId) {
      return Colors.blueGrey.shade600;
    }

    switch (node.type.title) {
      case 'Import':
        return Colors.teal.shade700;
      case 'Bandpass Filter':
        return Colors.indigo.shade700;
      case 'PSD':
        return Colors.deepPurple.shade700;
      case 'EEG Visualization':
        return Colors.orange.shade700;
      case 'Debug Output':
        return Colors.brown.shade700;
      default:
        return Colors.grey.shade800;
    }
  }

  String? _statusLabel(NodeModel node) {
    switch (node.visualState) {
      case DatasetState.notReady:
        return null;
      case DatasetState.ready:
        return 'Ready';
      case DatasetState.done:
        return 'Done';
      case DatasetState.stale:
        return 'Stale';
    }
  }

  Offset _outputPortPosition(NodeModel node, int portIndex) {
    final int count = node.outputPorts.length;
    final double step = _cardWidth / (count + 1);
    final double x = node.position.dx + step * (portIndex + 1);
    final double y = node.position.dy + _cardHeight + 4;
    return Offset(x, y);
  }

  Offset _inputPortPosition(NodeModel node, int portIndex) {
    final int count = node.inputPorts.length;
    final double step = _cardWidth / (count + 1);
    final double x = node.position.dx + step * (portIndex + 1);
    final double y = node.position.dy - 4;
    return Offset(x, y);
  }
}
