import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset_artifact_snapshot.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';
import '../model/node.dart';
import '../nodes/add_remove_markers_node.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/debug_output_node.dart';
import '../nodes/export_edf_node.dart';
import '../nodes/import_node.dart';
import '../nodes/matrix_transform_nodes.dart';
import '../nodes/node_type.dart';
import '../nodes/psd_node.dart';
import '../nodes/realign_node.dart';
import '../nodes/resample_node.dart';
import '../nodes/segmentation_node.dart';
import '../nodes/visualization_node.dart';
import '../platform/node_snapshot_store.dart';
import '../platform/project_file_save.dart';
import 'connection_painter.dart';
import 'node_card.dart';

class RunActivity {
  const RunActivity({
    required this.label,
    this.detail = '',
  });

  final String label;
  final String detail;

  RunActivity copyWith({
    String? label,
    String? detail,
  }) {
    return RunActivity(
      label: label ?? this.label,
      detail: detail ?? this.detail,
    );
  }
}

class CanvasLogic {
  CanvasLogic();

  /// Registry of available node types in the sidebar.
  final List<NodeType> availableNodes = <NodeType>[
    ImportNodeType(),
    ResampleNodeType(),
    BandpassNodeType(),
    PSDNodeType(),
    MicrostatesNodeType(),
    PCANodeType(),
    ICANodeType(),
    EigenvalueDecompositionNodeType(),
    AddRemoveMarkersNodeType(),
    SegmentationNodeType(),
    RealignNodeType(),
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
  final ValueNotifier<RunActivity?> runActivity = ValueNotifier<RunActivity?>(null);
  final Map<String, Map<String, DatasetArtifactSnapshot>> _nodeRamSnapshots =
      <String, Map<String, DatasetArtifactSnapshot>>{};

  String? selectedNodeId;
  int? selectedConnectionIndex;

  String? _pendingFromNodeId;
  final Map<NodeCategory, bool> _collapsedCategories = <NodeCategory, bool>{};

  static const double _cardWidth = 160;
  static const double _cardHeight = 72;
  static const double _spawnGap = 48;
  static const double _canvasPadding = 120;
  static const double _gridWidth = _cardWidth * 0.625;
  static const double _gridHeight = _cardHeight * 0.625;

  void addNode(NodeType type) {
    final Offset spawnPosition = _nearestAvailablePosition(_nextSpawnPosition());
    nodes.add(_buildNode(type: type, position: spawnPosition));
  }

  NodeModel _buildNode({
    required NodeType type,
    required Offset position,
    Map<String, dynamic>? params,
  }) {
    final Map<String, dynamic> initialParams = params == null
        ? Map<String, dynamic>.from(type.defaultParams)
        : Map<String, dynamic>.from(params);
    initialParams.putIfAbsent(
      'selectedDatasetIds',
      () => datasets.values
          .map((Dataset dataset) => dataset.id)
          .toList(growable: false),
    );

    return NodeModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type,
      position: position,
      params: initialParams,
    );
  }

  Offset snapToGrid(Offset offset) {
    return Offset(
      _snapCoordinate(offset.dx, _gridWidth),
      _snapCoordinate(offset.dy, _gridHeight),
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
      final Uint8List bytes = await file.readAsBytes();
      final Dataset dataset = datasets.putIfAbsent(
        file.path.isEmpty ? file.name : file.path,
        () => Dataset(
          DateTime.now().microsecondsSinceEpoch.toString(),
          label: file.name,
          path: file.path,
          sourceBytes: bytes,
        ),
      );
      dataset.label = file.name;
      dataset.path = file.path;
      dataset.sourceBytes = bytes;
      dataset.ram['source.filename'] = file.name;
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

  Future<void> exportBrainStory(BuildContext context) async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'brainstory_project.bst',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'BrainStory Project',
          extensions: <String>['bst'],
        ),
      ],
    );
    if (location == null) {
      return;
    }

    final String jsonPayload = const JsonEncoder.withIndent('  ').convert(
      exportProjectJson(),
    );
    final String? savedPath = await saveBrainStoryProject(
      suggestedName: 'brainstory_project',
      targetPath: location.path,
      jsonPayload: jsonPayload,
    );
    if (context.mounted) {
      _showStatusSnackBar(
        context,
        savedPath == null
            ? 'BrainStory export was canceled.'
            : 'Saved BrainStory project to $savedPath.',
      );
    }
  }

  Future<void> loadBrainStory(BuildContext context) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'BrainStory Project',
          extensions: <String>['bst'],
        ),
      ],
    );
    if (file == null) {
      return;
    }

    try {
      final String jsonPayload = await file.readAsString();
      final Map<String, dynamic> jsonMap =
          Map<String, dynamic>.from(jsonDecode(jsonPayload) as Map);
      importProjectJson(jsonMap);
      if (context.mounted) {
        _showStatusSnackBar(
          context,
          'Loaded BrainStory project from ${file.name}.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showStatusSnackBar(
          context,
          'Could not load BrainStory project: $error',
        );
      }
    }
  }

  Map<String, dynamic> exportProjectJson() {
    return <String, dynamic>{
      'format': 'brainstory_project',
      'version': 1,
      'datasets': datasets.values
          .map(
            (Dataset dataset) => <String, dynamic>{
              'id': dataset.id,
              'label': dataset.label,
              'path': dataset.path,
              'loaded': dataset.loaded,
              'sourceFilename': dataset.ram['source.filename'],
              'sourceBytesBase64': dataset.sourceBytes == null
                  ? null
                  : base64Encode(dataset.sourceBytes!),
            },
          )
          .toList(growable: false),
      'nodes': nodes
          .map(
            (NodeModel node) => <String, dynamic>{
              'id': node.id,
              'type': node.type.title,
              'x': node.position.dx,
              'y': node.position.dy,
              'params': node.params,
              'datasetStates': node.datasetStates.map(
                (dynamic key, DatasetState value) =>
                    MapEntry<String, dynamic>(key.toString(), value.name),
              ),
            },
          )
          .toList(growable: false),
      'connections': connections
          .map((Map<String, dynamic> connection) => Map<String, dynamic>.from(connection))
          .toList(growable: false),
    };
  }

  void importProjectJson(Map<String, dynamic> jsonMap) {
    clearAll();
    datasets.clear();
    _nodeRamSnapshots.clear();

    final List<dynamic> datasetEntries =
        jsonMap['datasets'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic entry in datasetEntries) {
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(entry as Map);
      final String path = data['path']?.toString() ?? '';
      final String label = data['label']?.toString() ?? 'Dataset';
      final String id = data['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final String? sourceBytesBase64 = data['sourceBytesBase64']?.toString();
      final Uint8List? sourceBytes = sourceBytesBase64 == null ||
              sourceBytesBase64.isEmpty
          ? null
          : Uint8List.fromList(base64Decode(sourceBytesBase64));
      final Dataset dataset = Dataset(
        id,
        label: label,
        path: path,
        sourceBytes: sourceBytes,
      );
      dataset.loaded = data['loaded'] as bool? ?? false;
      final String sourceFilename = data['sourceFilename']?.toString() ?? '';
      if (sourceFilename.isNotEmpty) {
        dataset.ram['source.filename'] = sourceFilename;
      }
      datasets[path.isEmpty ? id : path] = dataset;
    }

    final List<dynamic> nodeEntries =
        jsonMap['nodes'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic entry in nodeEntries) {
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(entry as Map);
      final NodeType? type = _nodeTypeByTitle(data['type']?.toString() ?? '');
      if (type == null) {
        continue;
      }
      final NodeModel node = NodeModel(
        id: data['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        position: Offset(
          (data['x'] as num?)?.toDouble() ?? 0,
          (data['y'] as num?)?.toDouble() ?? 0,
        ),
        params: Map<String, dynamic>.from(
          data['params'] as Map? ?? <String, dynamic>{},
        ),
      );
      final Map<String, dynamic> rawStates = Map<String, dynamic>.from(
        data['datasetStates'] as Map? ?? <String, dynamic>{},
      );
      for (final MapEntry<String, dynamic> stateEntry in rawStates.entries) {
        node.datasetStates[stateEntry.key] =
            _datasetStateFromName(stateEntry.value?.toString());
      }
      nodes.add(node);
    }

    final List<dynamic> connectionEntries =
        jsonMap['connections'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic entry in connectionEntries) {
      connections.add(Map<String, dynamic>.from(entry as Map));
    }
  }

  Widget sidebar({
    required double width,
    required VoidCallback export,
    required VoidCallback load,
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Divider(
              height: 20,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: load,
                child: const Text('Load BrainStory'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: export,
                child: const Text('Export BrainStory'),
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
    return nodes.asMap().entries.map((MapEntry<int, NodeModel> entry) {
      final int nodeNumber = entry.key + 1;
      final NodeModel node = entry.value;
      return NodeCard(
        width: _cardWidth,
        height: _cardHeight,
        title: node.title,
        nodeNumber: nodeNumber,
        position: node.position,
        color: _nodeColor(node),
        statusLabel: _statusLabel(node),
        highlighted: _isHighlighted(node),
        highlightColor: _nodeHighlightColor(node),
        done: node.visualState == DatasetState.done,
        onDragEnd: (Offset globalOffset) {
          node.position = _nearestAvailablePosition(
            translateDropOffset(globalOffset),
            movingNodeId: node.id,
          );
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
            await prepareRunUi('Running ${node.title}');
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
          } finally {
            finishRunUi();
          }
        },
        onRunFromStart: () async {
          try {
            await prepareRunUi('Running pipeline to ${node.title}');
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
          } finally {
            finishRunUi();
          }
        },
        onRunToEnd: () async {
          try {
            await prepareRunUi('Running ${node.title} to pipeline end');
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
          } finally {
            finishRunUi();
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
        _applyNodeParams(
          node: node,
          params: params,
          update: update,
        );
      },
        onSaveAndRun: (Map<String, dynamic> params) async {
          _applyNodeParams(
            node: node,
            params: params,
            update: update,
          );
          try {
            await prepareRunUi('Running ${node.title}');
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
          } finally {
            finishRunUi();
          }
        },
        datasetActions: _datasetActionsForNode(
          node: node,
          update: update,
        ),
        datasets: _datasetsById(),
        availableDatasetIds: _availableDatasetIdsForNode(node),
        datasetSourceLabels: _datasetSourceLabelsForNode(node),
        processedDatasetStates: _processedDatasetStatesForNode(node),
        processingSteps: processingStepsForNode(node.id),
      ),
    );
  }

  void _applyNodeParams({
    required NodeModel node,
    required Map<String, dynamic> params,
    required VoidCallback update,
  }) {
    node.params = params;
    if (node.type is ImportNodeType) {
      ImportNodeType.applyDatasetAliases(params, datasets.values);
    }
    for (final Dataset dataset in datasets.values) {
      node.datasetStates[dataset.id] = DatasetState.stale;
      _markDescendantsStale(node.id, dataset.id);
    }
    update();
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

  NodeModel? get selectedVisualizationTarget => selectedNode;

  List<Dataset> get datasetsForSelectedVisualizationNode {
    final NodeModel? node = selectedVisualizationNode;
    if (node == null) {
      return <Dataset>[];
    }

    return datasetsForVisualizationNode(node.id);
  }

  List<Dataset> datasetsForVisualizationNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return <Dataset>[];
    }

    final Set<String> datasetIds = _datasetsForNode(node);
    return datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .map((Dataset dataset) => materializedDatasetViewForNode(node.id, dataset))
        .toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
  }

  Dataset materializedDatasetViewForNode(String nodeId, Dataset source) {
    final Dataset view = Dataset(
      source.id,
      label: source.label,
      path: source.path,
      sourceBytes: source.sourceBytes,
    );
    view.loaded = source.loaded;
    view.ram.addAll(source.ram);
    final DatasetArtifactSnapshot? snapshot =
        _nodeRamSnapshots[nodeId]?[source.id];
    if (snapshot != null && !snapshot.isEmpty) {
      snapshot.applyToDataset(view);
    }
    return view;
  }

  bool isVisualizationNode(NodeModel? node) => node?.type is VisualizationNodeType;

  bool isMarkerEditNode(NodeModel? node) => node?.type is AddRemoveMarkersNodeType;

  bool canVisualizeNode(NodeModel? node) {
    if (node == null) {
      return false;
    }
    if (node.type is VisualizationNodeType) {
      return true;
    }
    if (node.type is PSDNodeType) {
      return true;
    }
    return node.outputPorts.any((PortSpec port) {
      return port.type == PortType.signal;
    });
  }

  String visualizationViewForNode(NodeModel node) {
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id);
      if (parents.any((NodeModel parent) => parent.type is PSDNodeType)) {
        return 'psd';
      }
      if (parents.any((NodeModel parent) => parent.type.title.contains('Time-Frequency'))) {
        return 'time_frequency';
      }
      return 'raw';
    }
    return node.type is PSDNodeType ? 'psd' : 'raw';
  }

  List<String> processingStepsForNode(String nodeId) {
    final Set<String> ancestorIds = _collectAncestorsInclusive(nodeId);
    final List<NodeModel> orderedNodes = _orderedNodes(ancestorIds);
    return orderedNodes
        .map((NodeModel node) => _nodeDescriptor(node))
        .toList(growable: false);
  }

  String visualizationDisplayMode(NodeModel? node) {
    if (node == null || node.type is! VisualizationNodeType) {
      return 'panel';
    }
    return (node.params['display_mode'] ?? 'panel').toString();
  }

  int _lastRunDatasetCount = 0;

  Future<void> prepareRunUi(String label) async {
    runActivity.value = RunActivity(
      label: label,
      detail: 'Preparing run state...',
    );
    await _yieldToUi();
    await setRunDetail('Settling the interface...');
    await _yieldToUi();
    await setRunDetail('Preparing data flow...');
    await _yieldToUi(extraDelayMs: 24);
  }

  void finishRunUi() {
    runActivity.value = null;
  }

  Future<void> setRunDetail(String detail) async {
    final RunActivity? current = runActivity.value;
    if (current == null) {
      return;
    }
    runActivity.value = current.copyWith(detail: detail);
    await _yieldToUi();
  }

  Future<void> runThisStep(
    String nodeId, {
    Set<String>? datasetIds,
  }) async {
    await _runNodeSet(<String>{nodeId}, datasetIds: datasetIds);
  }

  Future<void> runFromStart(
    String nodeId, {
    Set<String>? datasetIds,
  }) async {
    await _runNodeSet(
      _collectAncestorsInclusive(nodeId),
      datasetIds: datasetIds,
    );
  }

  Future<void> runToEnd(
    String nodeId, {
    Set<String>? datasetIds,
  }) async {
    await _runNodeSet(
      _collectDescendantsInclusive(nodeId),
      datasetIds: datasetIds,
    );
  }

  Future<void> _runNodeSet(
    Set<String> nodeIds, {
    Set<String>? datasetIds,
  }) async {
    final List<NodeModel> orderedNodes = _orderedNodes(nodeIds);
    if (orderedNodes.isEmpty) {
      _lastRunDatasetCount = 0;
      return;
    }

    await setRunDetail('Resolving datasets...');

    final Set<String> candidateDatasetIds = <String>{};
    for (final NodeModel node in orderedNodes) {
      candidateDatasetIds.addAll(_datasetsForNode(node));
    }

    if (datasetIds != null) {
      candidateDatasetIds.retainAll(datasetIds);
    }

    final List<Dataset> targetDatasets = datasets.values
        .where((Dataset dataset) => candidateDatasetIds.contains(dataset.id))
        .toList();

    _lastRunDatasetCount = targetDatasets.length;
    if (targetDatasets.isEmpty) {
      return;
    }

    for (final Dataset dataset in targetDatasets) {
      await setRunDetail('Preparing ${dataset.label}...');
      for (final NodeModel node in orderedNodes) {
        if (!_datasetsForNode(node).contains(dataset.id)) {
          continue;
        }

        if (node.datasetStates[dataset.id] == DatasetState.done) {
          await setRunDetail('Skipping ${node.title} for ${dataset.label} (already done)...');
          await _restoreMaterializedOutputIfNeeded(node, dataset);
          continue;
        }

        node.datasetStates[dataset.id] = DatasetState.ready;
        try {
          await _restoreUpstreamInputForRun(node, dataset);
          await setRunDetail('Running ${node.title} on ${dataset.label}...');
          await node.type.run(dataset, node.params);
          node.datasetStates[dataset.id] = DatasetState.done;
          await _materializeNodeOutput(node, dataset);
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
      final Set<String> importDatasetIds = _selectedDatasetIdsForNode(
        importNode,
        datasets.values.map((Dataset dataset) => dataset.id).toSet(),
      );
      datasetIds.addAll(importDatasetIds);
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

  Map<String, List<String>> _datasetSourceLabelsForNode(NodeModel node) {
    if (node.type is ImportNodeType) {
      return <String, List<String>>{
        for (final Dataset dataset in datasets.values) dataset.id: <String>['Source file'],
      };
    }

    final Map<String, List<String>> labelsByDataset = <String, List<String>>{};
    final List<NodeModel> parents = _immediateParents(node.id);
    for (final NodeModel parent in parents) {
      final String descriptor = _nodeDescriptor(parent);
      for (final Dataset dataset in datasets.values) {
        if (parent.datasetStates[dataset.id] == DatasetState.done) {
          labelsByDataset
              .putIfAbsent(dataset.id, () => <String>[])
              .add(descriptor);
        }
      }
    }

    for (final List<String> labels in labelsByDataset.values) {
      labels.sort();
    }
    return labelsByDataset;
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

  void applyMarkersFromVisualization({
    required String nodeId,
    required Dataset dataset,
    required List<dynamic> rawMarkers,
  }) {
    final NodeModel? sourceNode = _markerEditSourceNode(nodeId);
    if (sourceNode == null) {
      return;
    }

    final NodeModel markerNode = _ensureMarkerNode(sourceNode);
    markerNode.params['markers'] = rawMarkers;

    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      dataset.timeSeries = timeSeries.copyWith(
        markers: AddRemoveMarkersNodeType.markersForDataset(
          dataset.id,
          rawMarkers,
        ),
      );
    }

    markerNode.datasetStates[dataset.id] = DatasetState.done;
    _markDescendantsStale(markerNode.id, dataset.id);
    selectedNodeId = markerNode.id;
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  void _showStatusSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  NodeDatasetActions _datasetActionsForNode({
    required NodeModel node,
    required VoidCallback update,
  }) {
    return NodeDatasetActions(
      supportsDisk: supportsNodeSnapshotDiskStore,
      refresh: (Map<String, dynamic> params) =>
          _datasetStatusSnapshotForNode(node: node, params: params),
      runAllPrevious: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _runNodeDatasetAction(
        runLabel: 'Running pipeline to ${node.title}',
        action: () => runFromStart(node.id, datasetIds: datasetIds),
        node: node,
        update: update,
      ),
      runThisNode: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _runNodeDatasetAction(
        runLabel: 'Running ${node.title}',
        action: () => runThisStep(node.id, datasetIds: datasetIds),
        node: node,
        update: update,
      ),
      clearResults: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _clearNodeResults(
        node: node,
        params: params,
        datasetIds: datasetIds,
        update: update,
      ),
      loadFromDisk: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _loadNodeSnapshotsToRam(
        node: node,
        datasetIds: datasetIds,
        update: update,
      ),
      purgeActiveMemory:
          (Map<String, dynamic> params, Set<String> datasetIds) =>
              _releaseNodeSnapshotsFromRam(
        node: node,
        datasetIds: datasetIds,
        update: update,
      ),
      saveToDisk: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _saveNodeSnapshotsToDisk(
        node: node,
        datasetIds: datasetIds,
        update: update,
      ),
      purgeFromDisk: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _deleteNodeSnapshotsFromDisk(
        node: node,
        datasetIds: datasetIds,
        update: update,
      ),
    );
  }

  Future<void> _materializeNodeOutput(NodeModel node, Dataset dataset) async {
    await setRunDetail('Materializing ${node.title} for ${dataset.label}...');
    final DatasetArtifactSnapshot snapshot =
        DatasetArtifactSnapshot.fromDataset(dataset);
    if (snapshot.isEmpty) {
      _nodeRamSnapshots[node.id]?.remove(dataset.id);
      return;
    }

    final NodeStoragePolicy policy = _storagePolicyForNode(node);
    if (policy != NodeStoragePolicy.onDemand) {
      _nodeRamSnapshots.putIfAbsent(node.id, () => <String, DatasetArtifactSnapshot>{})[dataset.id] =
          snapshot;
    } else {
      _nodeRamSnapshots[node.id]?.remove(dataset.id);
    }

    if (supportsNodeSnapshotDiskStore &&
        (policy == NodeStoragePolicy.preferDisk ||
            policy == NodeStoragePolicy.ramAndDisk)) {
      await saveNodeSnapshotJson(
        nodeId: node.id,
        datasetId: dataset.id,
        jsonPayload: jsonEncode(snapshot.toJson()),
      );
      if (policy == NodeStoragePolicy.preferDisk) {
        _nodeRamSnapshots[node.id]?.remove(dataset.id);
      }
    }
  }

  Future<NodeDatasetStatusSnapshot> _datasetStatusSnapshotForNode({
    required NodeModel node,
    required Map<String, dynamic> params,
  }) async {
    final NodeModel configuredNode = _nodeWithParams(node, params);
    final Set<String> diskSavedDatasetIds = <String>{};
    if (supportsNodeSnapshotDiskStore) {
      final List<String> datasetIds =
          datasets.values.map((Dataset dataset) => dataset.id).toList(growable: false);
      final List<bool> diskFlags = await Future.wait(
        datasetIds.map((String datasetId) {
          return hasNodeSnapshotOnDisk(
            nodeId: node.id,
            datasetId: datasetId,
          );
        }),
      );
      for (int index = 0; index < datasetIds.length; index++) {
        if (diskFlags[index]) {
          diskSavedDatasetIds.add(datasetIds[index]);
        }
      }
    }

    return NodeDatasetStatusSnapshot(
      availableDatasetIds: _availableDatasetIdsForNode(configuredNode),
      processedDatasetStates: _processedDatasetStatesForNode(node),
      ramLoadedDatasetIds:
          _nodeRamSnapshots[node.id]?.keys.toSet() ?? const <String>{},
      diskSavedDatasetIds: diskSavedDatasetIds,
    );
  }

  Future<String> _runNodeDatasetAction({
    required String runLabel,
    required Future<void> Function() action,
    required NodeModel node,
    required VoidCallback update,
  }) async {
    try {
      await prepareRunUi(runLabel);
      await action();
      update();
      return _lastRunDatasetCount == 0
          ? 'No datasets matched ${node.title}.'
          : 'Ran ${node.title} for $_lastRunDatasetCount dataset(s).';
    } finally {
      finishRunUi();
    }
  }

  Future<String> _saveNodeSnapshotsToDisk({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    if (!supportsNodeSnapshotDiskStore) {
      return 'Disk cache is not available on this platform.';
    }

    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to save for ${node.title}.';
    }

    int savedCount = 0;
    String? lastPath;
    for (final Dataset dataset in selectedDatasets) {
      DatasetArtifactSnapshot? snapshot =
          _nodeRamSnapshots[node.id]?[dataset.id];
      if (snapshot == null || snapshot.isEmpty) {
        continue;
      }
      _nodeRamSnapshots.putIfAbsent(node.id, () => <String, DatasetArtifactSnapshot>{})[dataset.id] =
          snapshot;
      lastPath = await saveNodeSnapshotJson(
        nodeId: node.id,
        datasetId: dataset.id,
        jsonPayload: jsonEncode(snapshot.toJson()),
      );
      savedCount++;
    }

    if (savedCount == 0) {
      return 'Nothing is currently loaded in RAM for ${node.title}.';
    }

    update();
    return lastPath == null
        ? 'Saved $savedCount cached output(s) for ${node.title}.'
        : 'Saved $savedCount cached output(s) for ${node.title} to $lastPath.';
  }

  Future<String> _loadNodeSnapshotsToRam({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to load for ${node.title}.';
    }

    int loadedCount = 0;
    for (final Dataset dataset in selectedDatasets) {
      final String? jsonPayload = await loadNodeSnapshotJson(
        nodeId: node.id,
        datasetId: dataset.id,
      );
      if (jsonPayload == null || jsonPayload.trim().isEmpty) {
        continue;
      }
      final Map<String, dynamic> decoded =
          Map<String, dynamic>.from(jsonDecode(jsonPayload) as Map);
      final DatasetArtifactSnapshot snapshot =
          DatasetArtifactSnapshot.fromJson(decoded);
      if (snapshot.isEmpty) {
        continue;
      }
      _nodeRamSnapshots.putIfAbsent(node.id, () => <String, DatasetArtifactSnapshot>{})[dataset.id] =
          snapshot;
      snapshot.applyToDataset(dataset);
      node.datasetStates[dataset.id] = DatasetState.done;
      _markDescendantsStale(node.id, dataset.id);
      loadedCount++;
    }

    if (loadedCount == 0) {
      return 'No disk cache found yet for ${node.title}.';
    }

    update();
    return 'Loaded $loadedCount cached output(s) into RAM for ${node.title}.';
  }

  Future<String> _releaseNodeSnapshotsFromRam({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to release for ${node.title}.';
    }

    int releasedCount = 0;
    final Map<String, DatasetArtifactSnapshot>? snapshots = _nodeRamSnapshots[node.id];
    if (snapshots != null) {
      for (final Dataset dataset in selectedDatasets) {
        if (snapshots.remove(dataset.id) != null) {
          releasedCount++;
        }
      }
      if (snapshots.isEmpty) {
        _nodeRamSnapshots.remove(node.id);
      }
    }

    update();
    return releasedCount == 0
        ? 'No RAM cache was being held for ${node.title}.'
        : 'Released $releasedCount in-memory cached output(s) for ${node.title}.';
  }

  Future<String> _deleteNodeSnapshotsFromDisk({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    if (!supportsNodeSnapshotDiskStore) {
      return 'Disk cache is not available on this platform.';
    }

    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to purge for ${node.title}.';
    }

    int deletedCount = 0;
    for (final Dataset dataset in selectedDatasets) {
      final bool exists = await hasNodeSnapshotOnDisk(
        nodeId: node.id,
        datasetId: dataset.id,
      );
      if (!exists) {
        continue;
      }
      await deleteNodeSnapshotFromDisk(
        nodeId: node.id,
        datasetId: dataset.id,
      );
      deletedCount++;
    }

    update();
    return deletedCount == 0
        ? 'Nothing was saved to disk yet for ${node.title}.'
        : 'Purged $deletedCount disk cache file(s) for ${node.title}.';
  }

  Future<String> _clearNodeResults({
    required NodeModel node,
    required Map<String, dynamic> params,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to clear for ${node.title}.';
    }

    final NodeModel configuredNode = _nodeWithParams(node, params);
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(configuredNode);
    int clearedCount = 0;

    for (final Dataset dataset in selectedDatasets) {
      bool changed = false;
      final Map<String, DatasetArtifactSnapshot>? snapshots = _nodeRamSnapshots[node.id];
      if (snapshots?.remove(dataset.id) != null) {
        changed = true;
      }
      if (snapshots != null && snapshots.isEmpty) {
        _nodeRamSnapshots.remove(node.id);
      }
      if (supportsNodeSnapshotDiskStore) {
        final bool exists = await hasNodeSnapshotOnDisk(
          nodeId: node.id,
          datasetId: dataset.id,
        );
        if (exists) {
          await deleteNodeSnapshotFromDisk(
            nodeId: node.id,
            datasetId: dataset.id,
          );
          changed = true;
        }
      }

      final DatasetState nextState = availableDatasetIds.contains(dataset.id)
          ? DatasetState.ready
          : DatasetState.notReady;
      if (node.datasetStates[dataset.id] != nextState) {
        node.datasetStates[dataset.id] = nextState;
        changed = true;
      }
      _markDescendantsStale(node.id, dataset.id);
      if (changed) {
        clearedCount++;
      }
    }

    update();
    return clearedCount == 0
        ? 'There were no results to clear for ${node.title}.'
        : 'Cleared $clearedCount result set(s) for ${node.title}.';
  }

  Future<void> _restoreMaterializedOutputIfNeeded(
    NodeModel node,
    Dataset dataset,
  ) async {
    final DatasetArtifactSnapshot? snapshot =
        await _loadSnapshotForNodeDataset(node.id, dataset.id);
    if (snapshot == null || snapshot.isEmpty) {
      return;
    }
    snapshot.applyToDataset(dataset);
  }

  Future<void> _restoreUpstreamInputForRun(
    NodeModel node,
    Dataset dataset,
  ) async {
    if (node.type is ImportNodeType || node.type is VisualizationNodeType) {
      return;
    }

    final List<NodeModel> parents = _immediateParents(node.id);
    if (parents.isEmpty) {
      return;
    }

    for (final NodeModel parent in parents) {
      if (parent.datasetStates[dataset.id] != DatasetState.done) {
        continue;
      }
      final DatasetArtifactSnapshot? snapshot =
          await _loadSnapshotForNodeDataset(parent.id, dataset.id);
      if (snapshot == null || snapshot.isEmpty) {
        continue;
      }
      snapshot.applyToDataset(dataset);
      return;
    }
  }

  Future<DatasetArtifactSnapshot?> _loadSnapshotForNodeDataset(
    String nodeId,
    String datasetId,
  ) async {
    final DatasetArtifactSnapshot? ramSnapshot =
        _nodeRamSnapshots[nodeId]?[datasetId];
    if (ramSnapshot != null && !ramSnapshot.isEmpty) {
      return ramSnapshot;
    }

    final String? jsonPayload = await loadNodeSnapshotJson(
      nodeId: nodeId,
      datasetId: datasetId,
    );
    if (jsonPayload == null || jsonPayload.trim().isEmpty) {
      return null;
    }

    final Map<String, dynamic> decoded =
        Map<String, dynamic>.from(jsonDecode(jsonPayload) as Map);
    final DatasetArtifactSnapshot snapshot =
        DatasetArtifactSnapshot.fromJson(decoded);
    if (snapshot.isEmpty) {
      return null;
    }
    _nodeRamSnapshots
        .putIfAbsent(nodeId, () => <String, DatasetArtifactSnapshot>{})[datasetId] = snapshot;
    return snapshot;
  }

  NodeModel _nodeWithParams(
    NodeModel node,
    Map<String, dynamic> params,
  ) {
    return NodeModel(
      id: node.id,
      type: node.type,
      position: node.position,
      params: params,
    )..datasetStates.addAll(node.datasetStates);
  }

  List<Dataset> _datasetsForAction(Set<String> datasetIds) {
    return datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList(growable: false);
  }

  NodeStoragePolicy _storagePolicyForNode(NodeModel node) {
    return NodeStoragePolicyPresentation.fromWireValue(
      node.params['storagePolicy']?.toString(),
    );
  }

  NodeType? _nodeTypeByTitle(String title) {
    for (final NodeType type in availableNodes) {
      if (type.title == title) {
        return type;
      }
    }
    return null;
  }

  DatasetState _datasetStateFromName(String? stateName) {
    for (final DatasetState state in DatasetState.values) {
      if (state.name == stateName) {
        return state;
      }
    }
    return DatasetState.notReady;
  }

  Future<void> _yieldToUi({int extraDelayMs = 12}) async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration(milliseconds: extraDelayMs));
  }

  Color _nodeColor(NodeModel node) {
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

  bool _isHighlighted(NodeModel node) {
    return node.id == selectedNodeId || node.id == _pendingFromNodeId;
  }

  Color _nodeHighlightColor(NodeModel node) {
    if (node.id == _pendingFromNodeId) {
      return const Color(0xFFC4B35F);
    }
    return const Color(0xFF958A52);
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

  NodeModel? _markerEditSourceNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return null;
    }
    if (node.type is AddRemoveMarkersNodeType) {
      return node;
    }
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id)
          .where((NodeModel parent) => parent.outputPorts.isNotEmpty)
          .toList(growable: false);
      if (parents.isNotEmpty) {
        return parents.first;
      }
      return null;
    }
    return node;
  }

  NodeModel _ensureMarkerNode(NodeModel sourceNode) {
    if (sourceNode.type is AddRemoveMarkersNodeType) {
      return sourceNode;
    }

    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != sourceNode.id) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child?.type is AddRemoveMarkersNodeType) {
        return child!;
      }
    }

    final NodeType markerType = AddRemoveMarkersNodeType();
    final NodeModel markerNode = _buildNode(
      type: markerType,
      position: snapToGrid(
        Offset(
          sourceNode.position.dx,
          sourceNode.position.dy + _cardHeight + _spawnGap,
        ),
      ),
      params: <String, dynamic>{
        ...markerType.defaultParams,
        if (sourceNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            sourceNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(markerNode);

    final Map<String, int>? portPair = _matchingPortPair(sourceNode, markerNode);
    if (portPair != null) {
      connections.add(<String, dynamic>{
        'fromNode': sourceNode.id,
        'fromPort': portPair['fromPort']!,
        'toNode': markerNode.id,
        'toPort': portPair['toPort']!,
      });
    }

    return markerNode;
  }

  double _snapCoordinate(double value, double gridSize) {
    return math.max(
      0,
      (value / gridSize).roundToDouble() * gridSize,
    ).toDouble();
  }

  Offset _nearestAvailablePosition(
    Offset desired, {
    String? movingNodeId,
  }) {
    Offset candidate = snapToGrid(desired);
    if (!_positionOverlapsAnyNode(candidate, movingNodeId: movingNodeId)) {
      return candidate;
    }

    final int baseColumn = (candidate.dx / _gridWidth).round();
    final int baseRow = (candidate.dy / _gridHeight).round();

    for (int radius = 1; radius <= 24; radius++) {
      for (int rowOffset = -radius; rowOffset <= radius; rowOffset++) {
        for (int columnOffset = -radius; columnOffset <= radius; columnOffset++) {
          if (rowOffset.abs() != radius && columnOffset.abs() != radius) {
            continue;
          }
          final Offset probe = Offset(
            math.max(0, (baseColumn + columnOffset) * _gridWidth).toDouble(),
            math.max(0, (baseRow + rowOffset) * _gridHeight).toDouble(),
          );
          if (!_positionOverlapsAnyNode(probe, movingNodeId: movingNodeId)) {
            return probe;
          }
        }
      }
    }

    return candidate;
  }

  bool _positionOverlapsAnyNode(
    Offset position, {
    String? movingNodeId,
  }) {
    final Rect probe = Rect.fromLTWH(
      position.dx,
      position.dy,
      _cardWidth,
      _cardHeight,
    );

    for (final NodeModel node in nodes) {
      if (node.id == movingNodeId) {
        continue;
      }
      final Rect occupied = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        _cardWidth,
        _cardHeight,
      );
      if (probe.overlaps(occupied)) {
        return true;
      }
    }
    return false;
  }

  String _nodeDescriptor(NodeModel node) {
    return '#${nodes.indexOf(node) + 1} ${node.title}';
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
