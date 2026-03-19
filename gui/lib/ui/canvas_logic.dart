import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/dataset.dart';
import '../model/dataset_state.dart';
import '../model/node.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/debug_output_node.dart';
import '../nodes/export_edf_node.dart';
import '../nodes/import_node.dart';
import '../nodes/node_type.dart';
import '../nodes/psd_node.dart';
import '../nodes/resample_node.dart';
import '../nodes/visualization_node.dart';
import 'connection_painter.dart';
import 'node_card.dart';

class CanvasLogic {
  CanvasLogic();

  /// Registry of available node types in the sidebar.
  final List<NodeType> availableNodes = <NodeType>[
    ImportNodeType(),
    ResampleNodeType(),
    BandpassNodeType(),
    PSDNodeType(),
    VisualizationNodeType(),
    DebugOutputNodeType(),
    ExportEdfNodeType(),
  ];

  final List<NodeModel> nodes = <NodeModel>[];
  final Map<String, Dataset> datasets = <String, Dataset>{};

  /// Connection schema:
  /// {
  ///   fromNode: String,
  ///   toNode: String,
  ///   fromPort: int,
  ///   toPort: int,
  /// }
  final List<Map<String, dynamic>> connections = <Map<String, dynamic>>[];

  String? selectedNodeId;
  int? selectedConnectionIndex;

  String? _pendingFromNodeId;
  final Map<NodeCategory, bool> _collapsedCategories = <NodeCategory, bool>{};

  static const double _cardWidth = 160;
  static const double _cardHeight = 72;
  static const double _spawnGap = 48;
  static const double _canvasPadding = 120;
  static const double _gridSize = 24;

  void addNode(NodeType type) {
    final Offset spawnPosition = _nextSpawnPosition();
    nodes.add(
      NodeModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        position: spawnPosition,
        params: Map<String, dynamic>.from(type.defaultParams),
      ),
    );
  }

  Offset snapToGrid(Offset offset) {
    return Offset(
      _snapCoordinate(offset.dx),
      _snapCoordinate(offset.dy),
    );
  }

  Size canvasSizeForViewport(Size viewport) {
    double width = viewport.width;
    double height = viewport.height;

    for (final NodeModel node in nodes) {
      width = width < node.position.dx + _cardWidth + _canvasPadding
          ? node.position.dx + _cardWidth + _canvasPadding
          : width;
      height = height < node.position.dy + _cardHeight + _canvasPadding
          ? node.position.dy + _cardHeight + _canvasPadding
          : height;
    }

    return Size(width, height);
  }

  void clearAll() {
    nodes.clear();
    connections.clear();
    selectedNodeId = null;
    selectedConnectionIndex = null;
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
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  void deleteSelectedConnection() {
    final int? index = selectedConnectionIndex;
    if (index == null || index < 0 || index >= connections.length) {
      return;
    }
    connections.removeAt(index);
    selectedConnectionIndex = null;
  }

  bool selectConnectionAt(Offset canvasOffset) {
    final int? index = _connectionIndexAt(canvasOffset);
    if (index == null) {
      return false;
    }
    selectedNodeId = null;
    selectedConnectionIndex = index;
    _clearPendingConnection();
    return true;
  }

  bool deleteConnectionAt(Offset canvasOffset) {
    final int? index = _connectionIndexAt(canvasOffset);
    if (index == null) {
      return false;
    }
    connections.removeAt(index);
    selectedConnectionIndex = null;
    return true;
  }

  void clearConnectionDraft() {
    _clearPendingConnection();
  }

  void _clearPendingConnection() {
    _pendingFromNodeId = null;
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
    required double width,
    required VoidCallback export,
    required VoidCallback clear,
    required VoidCallback update,
  }) {
    final List<NodeCategory> categoryOrder = <NodeCategory>[
      NodeCategory.import,
      NodeCategory.transform,
      NodeCategory.markerFunctions,
      NodeCategory.visualize,
      NodeCategory.export,
    ];

    return Container(
      width: width,
      color: Colors.grey[900],
      child: Column(
        children: <Widget>[
          const SizedBox(height: 20),
          const Text(
            'Nodes',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                for (final NodeCategory category in categoryOrder)
                  ..._sidebarCategorySection(
                    category: category,
                    update: update,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
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

  List<Widget> _sidebarCategorySection({
    required NodeCategory category,
    required VoidCallback update,
  }) {
    final List<NodeType> categoryNodes = availableNodes
        .where((NodeType node) => node.category == category)
        .toList(growable: false);
    final bool collapsed = _collapsedCategories[category] ?? false;

    return <Widget>[
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          _collapsedCategories[category] = !collapsed;
          update();
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: <Widget>[
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                color: category.color,
                size: 20,
              ),
              const SizedBox(width: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: category.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.label,
                  style: TextStyle(
                    color: category.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (!collapsed && categoryNodes.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 32, right: 4, bottom: 6),
          child: Text(
            'No nodes yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
        ),
      if (!collapsed)
        for (final NodeType type in categoryNodes)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 6),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: category.color.withValues(alpha: 0.18),
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: category.color.withValues(alpha: 0.35),
                  ),
                ),
                onPressed: () {
                  addNode(type);
                  update();
                },
                child: Text('+ ${type.title}'),
              ),
            ),
          ),
    ];
  }

  List<Widget> connectionWidgets() {
    return connections.map((Map<String, dynamic> connection) {
      final NodeModel? fromNode = _findNode(connection['fromNode'] as String);
      final NodeModel? toNode = _findNode(connection['toNode'] as String);

      if (fromNode == null || toNode == null) {
        return const SizedBox.shrink();
      }

      final Offset start = _outputAnchor(fromNode, toNode);
      final Offset end = _inputAnchor(fromNode, toNode);

      return CustomPaint(
        painter: ConnectionPainter(
          start: start,
          end: end,
          selected: selectedConnectionIndex == connections.indexOf(connection),
        ),
        size: Size.infinite,
      );
    }).toList();
  }

  List<Widget> nodeWidgets({
    required BuildContext context,
    required VoidCallback update,
    required Offset Function(Offset globalOffset) translateDropOffset,
    required void Function(NodeModel node) openVisualizationWindow,
  }) {
    return nodes.map((NodeModel node) {
      return NodeCard(
        title: node.title,
        position: node.position,
        color: _nodeColor(node),
        statusLabel: _statusLabel(node),
        onDragEnd: (Offset globalOffset) {
          node.position = translateDropOffset(globalOffset);
          update();
        },
        onTap: () {
          _handleNodeTap(node);
          update();
        },
        onDoubleTap: () {
          selectedNodeId = node.id;
          _openNodeEditor(
            context: context,
            node: node,
            update: update,
          );
        },
        onDelete: () {
          selectedNodeId = node.id;
          deleteSelected();
          update();
        },
        onEditParams: () {
          _openNodeEditor(
            context: context,
            node: node,
            update: update,
          );
        },
        onRunThis: () async {
          try {
            await runThisStep(node.id);
            update();
            if (node.type is VisualizationNodeType &&
                visualizationDisplayMode(node) == 'window') {
              openVisualizationWindow(node);
            }
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
            if (node.type is VisualizationNodeType &&
                visualizationDisplayMode(node) == 'window') {
              openVisualizationWindow(node);
            }
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
            if (node.type is VisualizationNodeType &&
                visualizationDisplayMode(node) == 'window') {
              openVisualizationWindow(node);
            }
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
      );
    }).toList();
  }

  void _handleNodeTap(NodeModel node) {
    if (_pendingFromNodeId == null) {
      selectedNodeId = node.id;
      selectedConnectionIndex = null;
      if (node.outputPorts.isNotEmpty) {
        _pendingFromNodeId = node.id;
      }
      return;
    }

    if (_pendingFromNodeId == node.id) {
      selectedNodeId = node.id;
      selectedConnectionIndex = null;
      _clearPendingConnection();
      return;
    }

    final NodeModel? fromNode = _findNode(_pendingFromNodeId!);
    if (fromNode == null) {
      selectedNodeId = node.id;
      selectedConnectionIndex = null;
      _clearPendingConnection();
      return;
    }

    final Map<String, int>? portPair = _matchingPortPair(fromNode, node);
    final bool validDirection = _isValidDownstreamPlacement(fromNode, node);
    final bool introducesCycle =
        _collectDescendantsInclusive(node.id).contains(fromNode.id);

    if (portPair == null || !validDirection || introducesCycle) {
      selectedNodeId = node.id;
      selectedConnectionIndex = null;
      if (node.outputPorts.isNotEmpty) {
        _pendingFromNodeId = node.id;
      } else {
        _clearPendingConnection();
      }
      return;
    }

    final Map<String, dynamic> nextConnection = <String, dynamic>{
      'fromNode': fromNode.id,
      'fromPort': portPair['fromPort']!,
      'toNode': node.id,
      'toPort': portPair['toPort']!,
    };

    final bool duplicate = connections.any(
      (Map<String, dynamic> connection) =>
          connection['fromNode'] == nextConnection['fromNode'] &&
          connection['fromPort'] == nextConnection['fromPort'] &&
          connection['toNode'] == nextConnection['toNode'] &&
          connection['toPort'] == nextConnection['toPort'],
    );

    if (!duplicate) {
      connections.add(nextConnection);
    }

    selectedNodeId = node.id;
    selectedConnectionIndex = null;
    if (node.outputPorts.isNotEmpty) {
      _pendingFromNodeId = node.id;
    } else {
      _clearPendingConnection();
    }
  }

  NodeModel? _findNode(String id) {
    for (final NodeModel node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  void _openNodeEditor({
    required BuildContext context,
    required NodeModel node,
    required VoidCallback update,
  }) {
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
        processingSteps: processingStepsForNode(node.id),
      ),
    );
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

    return datasetsForVisualizationNode(node.id);
  }

  List<Dataset> datasetsForVisualizationNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null || node.type is! VisualizationNodeType) {
      return <Dataset>[];
    }

    final Set<String> datasetIds = _datasetsForNode(node);
    return datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
  }

  List<String> processingStepsForNode(String nodeId) {
    final Set<String> ancestorIds = _collectAncestorsInclusive(nodeId);
    final List<NodeModel> orderedNodes = _orderedNodes(ancestorIds);
    return orderedNodes
        .map((NodeModel node) => '${node.type.category.label}: ${node.title}')
        .toList(growable: false);
  }

  String visualizationDisplayMode(NodeModel? node) {
    if (node == null || node.type is! VisualizationNodeType) {
      return 'panel';
    }
    return (node.params['display_mode'] ?? 'panel').toString();
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
      default:
        break;
    }

    switch (node.type.category) {
      case NodeCategory.import:
        return Colors.teal.shade700;
      case NodeCategory.transform:
        return Colors.indigo.shade700;
      case NodeCategory.markerFunctions:
        return Colors.pink.shade700;
      case NodeCategory.visualize:
        return Colors.orange.shade700;
      case NodeCategory.export:
        return Colors.green.shade700;
      case NodeCategory.other:
        return Colors.grey.shade800;
    }
  }

  String? _statusLabel(NodeModel node) {
    if (_pendingFromNodeId == node.id) {
      return 'Connecting...';
    }

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

  Offset _nextSpawnPosition() {
    if (nodes.isEmpty) {
      return snapToGrid(const Offset(100, 100));
    }

    NodeModel lowestNode = nodes.first;
    for (final NodeModel node in nodes.skip(1)) {
      if (node.position.dy > lowestNode.position.dy) {
        lowestNode = node;
      }
    }

    return snapToGrid(
      Offset(
        lowestNode.position.dx,
        lowestNode.position.dy + _cardHeight + _spawnGap,
      ),
    );
  }

  double _snapCoordinate(double value) {
    return math.max(
      0,
      (value / _gridSize).roundToDouble() * _gridSize,
    ).toDouble();
  }

  Map<String, int>? _matchingPortPair(NodeModel fromNode, NodeModel toNode) {
    for (int fromPortIndex = 0;
        fromPortIndex < fromNode.outputPorts.length;
        fromPortIndex++) {
      final PortType outputType = fromNode.outputPorts[fromPortIndex].type;
      for (int toPortIndex = 0;
          toPortIndex < toNode.inputPorts.length;
          toPortIndex++) {
        if (toNode.inputPorts[toPortIndex].type == outputType) {
          return <String, int>{
            'fromPort': fromPortIndex,
            'toPort': toPortIndex,
          };
        }
      }
    }
    return null;
  }

  bool _isValidDownstreamPlacement(NodeModel fromNode, NodeModel toNode) {
    final double dx = toNode.position.dx - fromNode.position.dx;
    final double dy = toNode.position.dy - fromNode.position.dy;
    return dx >= 24 || dy >= 24;
  }

  Offset _outputAnchor(NodeModel fromNode, NodeModel toNode) {
    final bool preferVertical = _shouldUseVerticalAnchors(fromNode, toNode);
    if (preferVertical) {
      return Offset(
        fromNode.position.dx + (_cardWidth / 2),
        fromNode.position.dy + _cardHeight,
      );
    }

    return Offset(
      fromNode.position.dx + _cardWidth,
      fromNode.position.dy + (_cardHeight / 2),
    );
  }

  Offset _inputAnchor(NodeModel fromNode, NodeModel toNode) {
    final bool preferVertical = _shouldUseVerticalAnchors(fromNode, toNode);
    if (preferVertical) {
      return Offset(
        toNode.position.dx + (_cardWidth / 2),
        toNode.position.dy,
      );
    }

    return Offset(
      toNode.position.dx,
      toNode.position.dy + (_cardHeight / 2),
    );
  }

  bool _shouldUseVerticalAnchors(NodeModel fromNode, NodeModel toNode) {
    final double dx = (toNode.position.dx - fromNode.position.dx).abs();
    final double dy = toNode.position.dy - fromNode.position.dy;
    return dy > 0 && dy >= dx;
  }

  int? _connectionIndexAt(Offset point) {
    for (int index = connections.length - 1; index >= 0; index--) {
      final Map<String, dynamic> connection = connections[index];
      final NodeModel? fromNode = _findNode(connection['fromNode'] as String);
      final NodeModel? toNode = _findNode(connection['toNode'] as String);
      if (fromNode == null || toNode == null) {
        continue;
      }

      final Offset start = _outputAnchor(fromNode, toNode);
      final Offset end = _inputAnchor(fromNode, toNode);
      if (_isPointNearConnection(point, start, end)) {
        return index;
      }
    }
    return null;
  }

  bool _isPointNearConnection(Offset point, Offset start, Offset end) {
    final Offset cp1 = Offset(start.dx + 100, start.dy);
    final Offset cp2 = Offset(end.dx - 100, end.dy);
    const double threshold = 12.0;
    const int steps = 32;

    Offset previous = start;
    for (int step = 1; step <= steps; step++) {
      final double t = step / steps;
      final Offset current = _sampleCubic(start, cp1, cp2, end, t);
      if (_distanceToSegment(point, previous, current) <= threshold) {
        return true;
      }
      previous = current;
    }
    return false;
  }

  Offset _sampleCubic(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double t,
  ) {
    final double mt = 1 - t;
    final double x = (mt * mt * mt * p0.dx) +
        (3 * mt * mt * t * p1.dx) +
        (3 * mt * t * t * p2.dx) +
        (t * t * t * p3.dx);
    final double y = (mt * mt * mt * p0.dy) +
        (3 * mt * mt * t * p1.dy) +
        (3 * mt * t * t * p2.dy) +
        (t * t * t * p3.dy);
    return Offset(x, y);
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) {
      return (point - a).distance;
    }

    final double t = (((point.dx - a.dx) * dx) + ((point.dy - a.dy) * dy)) /
        ((dx * dx) + (dy * dy));
    final double clampedT = t.clamp(0.0, 1.0);
    final Offset projection = Offset(
      a.dx + (dx * clampedT),
      a.dy + (dy * clampedT),
    );
    return (point - projection).distance;
  }
}
