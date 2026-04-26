import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset_artifact_snapshot.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';
import '../model/node.dart';
import '../nodes/add_remove_markers_node.dart';
import '../nodes/amplitude_features_node.dart';
import '../nodes/average_node.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/bridge_detector_node.dart';
import '../nodes/channel_coordinates_node.dart';
import '../nodes/debug_output_node.dart';
import '../nodes/edit_channels_node.dart';
import '../nodes/eye_blinks_node.dart';
import '../nodes/export_edf_node.dart';
import '../nodes/fooof_node.dart';
import '../nodes/impedances_node.dart';
import '../nodes/import_node.dart';
import '../nodes/interactive_artifact_detection_node.dart';
import '../nodes/matrix_transform_nodes.dart';
import '../nodes/machine_learning_nodes.dart';
import '../nodes/multimodal_nodes.dart';
import '../nodes/node_type.dart';
import '../nodes/psd_node.dart';
import '../nodes/publish_node.dart';
import '../nodes/recode_markers_node.dart';
import '../nodes/realign_node.dart';
import '../nodes/resample_node.dart';
import '../nodes/segmentation_node.dart';
import '../nodes/sleep_staging_node.dart';
import '../nodes/spectral_features_node.dart';
import '../nodes/topomap_node.dart';
import '../nodes/visualization_node.dart';
import '../platform/background_node_runner.dart';
import '../platform/node_snapshot_store.dart';
import '../platform/project_file_save.dart';
import 'connection_painter.dart';
import 'node_card.dart';

enum _OutputHandleKind {
  timeSeries,
  spectrum,
  timeFrequency,
  markers,
  segments,
  table,
  matrix,
  other,
}

class RunActivity {
  const RunActivity({
    required this.label,
    this.detail = '',
    this.jobId,
  });

  final String label;
  final String detail;
  final String? jobId;

  RunActivity copyWith({
    String? label,
    String? detail,
    String? jobId,
  }) {
    return RunActivity(
      label: label ?? this.label,
      detail: detail ?? this.detail,
      jobId: jobId ?? this.jobId,
    );
  }
}

enum BrainStoryJobStatus {
  queued,
  running,
  completed,
  failed,
  canceled,
}

class BrainStoryRunCanceled implements Exception {
  const BrainStoryRunCanceled([this.message = 'Run canceled.']);

  final String message;

  @override
  String toString() => message;
}

enum NodeProcessStatus {
  waiting,
  running,
  done,
  canceling,
  canceled,
  failed,
}

class NodeProcessIndicator {
  const NodeProcessIndicator({
    required this.status,
  });

  final NodeProcessStatus status;

  String get label {
    switch (status) {
      case NodeProcessStatus.waiting:
        return 'Waiting';
      case NodeProcessStatus.running:
        return 'Running';
      case NodeProcessStatus.done:
        return 'Done';
      case NodeProcessStatus.canceling:
        return 'Canceling';
      case NodeProcessStatus.canceled:
        return 'Canceled';
      case NodeProcessStatus.failed:
        return 'Failed';
    }
  }

  bool get active =>
      status == NodeProcessStatus.running ||
      status == NodeProcessStatus.canceling;

  Color get color {
    switch (status) {
      case NodeProcessStatus.waiting:
        return const Color(0xFFB9C0CC);
      case NodeProcessStatus.running:
        return const Color(0xFF66D9FF);
      case NodeProcessStatus.done:
        return const Color(0xFF62E391);
      case NodeProcessStatus.canceling:
        return const Color(0xFFFFC857);
      case NodeProcessStatus.canceled:
        return const Color(0xFFFFA24D);
      case NodeProcessStatus.failed:
        return const Color(0xFFFF6B6B);
    }
  }
}

class MemoryArtifactSummary {
  const MemoryArtifactSummary({
    required this.nodeId,
    required this.nodeDescriptor,
    required this.datasetId,
    required this.datasetLabel,
    required this.artifactLabel,
    required this.processingState,
    required this.inRam,
    required this.onDisk,
    required this.precisionLabel,
    required this.approxRamBytes,
    required this.approxDiskBytes,
  });

  final String nodeId;
  final String nodeDescriptor;
  final String datasetId;
  final String datasetLabel;
  final String artifactLabel;
  final DatasetState processingState;
  final bool inRam;
  final bool onDisk;
  final String precisionLabel;
  final int approxRamBytes;
  final int? approxDiskBytes;

  String get key => '$nodeId|$datasetId';
}

class VisualizationSourceRef {
  const VisualizationSourceRef({
    required this.key,
    required this.datasetId,
    required this.datasetLabel,
    required this.materializeFromNodeId,
    required this.sourceDescriptor,
  });

  final String key;
  final String datasetId;
  final String datasetLabel;
  final String materializeFromNodeId;
  final String sourceDescriptor;

  String get displayLabel => '$datasetLabel [$sourceDescriptor]';
}

class BrainStoryJob {
  const BrainStoryJob({
    required this.id,
    required this.label,
    this.detail = '',
    this.status = BrainStoryJobStatus.queued,
    this.progress,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.error,
    this.nodeId,
    this.datasetIds = const <String>{},
    this.cancellable = false,
    this.cancelRequested = false,
  });

  final String id;
  final String label;
  final String detail;
  final BrainStoryJobStatus status;
  final double? progress;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;
  final String? nodeId;
  final Set<String> datasetIds;
  final bool cancellable;
  final bool cancelRequested;

  bool get isActive =>
      status == BrainStoryJobStatus.queued ||
      status == BrainStoryJobStatus.running;

  BrainStoryJob copyWith({
    String? label,
    String? detail,
    BrainStoryJobStatus? status,
    double? progress,
    bool clearProgress = false,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
    bool clearError = false,
    String? nodeId,
    Set<String>? datasetIds,
    bool? cancellable,
    bool? cancelRequested,
  }) {
    return BrainStoryJob(
      id: id,
      label: label ?? this.label,
      detail: detail ?? this.detail,
      status: status ?? this.status,
      progress: clearProgress ? null : (progress ?? this.progress),
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      error: clearError ? null : (error ?? this.error),
      nodeId: nodeId ?? this.nodeId,
      datasetIds: datasetIds ?? this.datasetIds,
      cancellable: cancellable ?? this.cancellable,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}

class _DatasetUndoSnapshot {
  const _DatasetUndoSnapshot({
    required this.mapKey,
    required this.id,
    required this.label,
    required this.path,
    required this.sourceBytes,
    required this.loaded,
    required this.sourceFilename,
    required this.artifactSnapshot,
  });

  final String mapKey;
  final String id;
  final String label;
  final String path;
  final Uint8List? sourceBytes;
  final bool loaded;
  final String? sourceFilename;
  final DatasetArtifactSnapshot? artifactSnapshot;

  factory _DatasetUndoSnapshot.capture(
    MapEntry<String, Dataset> entry, {
    required bool captureArtifacts,
  }) {
    final Dataset dataset = entry.value;
    final String? sourceFilename = dataset.ram['source.filename']?.toString();
    return _DatasetUndoSnapshot(
      mapKey: entry.key,
      id: dataset.id,
      label: dataset.label,
      path: dataset.path,
      sourceBytes: dataset.sourceBytes,
      loaded: dataset.loaded,
      sourceFilename: sourceFilename?.isEmpty == true ? null : sourceFilename,
      artifactSnapshot:
          captureArtifacts ? DatasetArtifactSnapshot.fromDataset(dataset) : null,
    );
  }

  Dataset restore(Map<String, Dataset> currentDatasetsById) {
    final Dataset dataset = currentDatasetsById[id] ??
        Dataset(
          id,
          label: label,
          path: path,
          sourceBytes: sourceBytes,
        );
    dataset.label = label;
    dataset.path = path;
    dataset.sourceBytes = sourceBytes;
    dataset.loaded = loaded;
    if (sourceFilename == null) {
      dataset.ram.remove('source.filename');
    } else {
      dataset.ram['source.filename'] = sourceFilename;
    }
    artifactSnapshot?.applyToDataset(dataset);
    return dataset;
  }
}

class _NodeUndoSnapshot {
  const _NodeUndoSnapshot({
    required this.id,
    required this.type,
    required this.position,
    required this.params,
    required this.markerChange,
    required this.datasetStates,
  });

  final String id;
  final NodeType type;
  final Offset position;
  final Map<String, dynamic> params;
  final MarkerChange markerChange;
  final Map<dynamic, DatasetState> datasetStates;

  factory _NodeUndoSnapshot.capture(NodeModel node) {
    return _NodeUndoSnapshot(
      id: node.id,
      type: node.type,
      position: node.position,
      params: _deepCloneJsonMap(node.params),
      markerChange: MarkerChange.fromJson(node.markerChange.toJson()),
      datasetStates: Map<dynamic, DatasetState>.from(node.datasetStates),
    );
  }

  NodeModel restore() {
    final NodeModel node = NodeModel(
      id: id,
      type: type,
      position: position,
      params: _deepCloneJsonMap(params),
      markerChange: MarkerChange.fromJson(markerChange.toJson()),
    );
    node.datasetStates.addAll(datasetStates);
    return node;
  }
}

class _CanvasUndoSnapshot {
  const _CanvasUndoSnapshot({
    required this.label,
    required this.nodes,
    required this.datasets,
    required this.connections,
    required this.nodeRamSnapshots,
    required this.nodeDiskSnapshotIds,
    required this.selectedNodeId,
    required this.selectedNodeIds,
    required this.selectedConnectionIndex,
    required this.pendingFromNodeId,
    required this.pendingFromPortIndex,
  });

  final String label;
  final List<_NodeUndoSnapshot> nodes;
  final List<_DatasetUndoSnapshot> datasets;
  final List<Map<String, dynamic>> connections;
  final Map<String, Map<String, DatasetArtifactSnapshot>> nodeRamSnapshots;
  final Map<String, Set<String>> nodeDiskSnapshotIds;
  final String? selectedNodeId;
  final Set<String> selectedNodeIds;
  final int? selectedConnectionIndex;
  final String? pendingFromNodeId;
  final int? pendingFromPortIndex;

  factory _CanvasUndoSnapshot.capture(
    CanvasLogic logic,
    String label, {
    Set<String> datasetArtifactIds = const <String>{},
  }) {
    return _CanvasUndoSnapshot(
      label: label,
      nodes: logic.nodes.map(_NodeUndoSnapshot.capture).toList(growable: false),
      datasets: logic.datasets.entries
          .map(
            (MapEntry<String, Dataset> entry) => _DatasetUndoSnapshot.capture(
              entry,
              captureArtifacts: datasetArtifactIds.contains(entry.value.id),
            ),
          )
          .toList(growable: false),
      connections: logic.connections
          .map((Map<String, dynamic> connection) => _deepCloneJsonMap(connection))
          .toList(growable: false),
      nodeRamSnapshots: <String, Map<String, DatasetArtifactSnapshot>>{
        for (final MapEntry<String, Map<String, DatasetArtifactSnapshot>> entry
            in logic._nodeRamSnapshots.entries)
          entry.key: Map<String, DatasetArtifactSnapshot>.from(entry.value),
      },
      nodeDiskSnapshotIds: <String, Set<String>>{
        for (final MapEntry<String, Set<String>> entry
            in logic._nodeDiskSnapshotIds.entries)
          entry.key: Set<String>.from(entry.value),
      },
      selectedNodeId: logic.selectedNodeId,
      selectedNodeIds: Set<String>.from(logic.selectedNodeIds),
      selectedConnectionIndex: logic.selectedConnectionIndex,
      pendingFromNodeId: logic._pendingFromNodeId,
      pendingFromPortIndex: logic._pendingFromPortIndex,
    );
  }

  void restore(CanvasLogic logic) {
    final Map<String, Dataset> currentDatasetsById = <String, Dataset>{
      for (final Dataset dataset in logic.datasets.values) dataset.id: dataset,
    };

    logic.nodes
      ..clear()
      ..addAll(nodes.map((_NodeUndoSnapshot node) => node.restore()));

    logic.datasets.clear();
    for (final _DatasetUndoSnapshot datasetSnapshot in datasets) {
      logic.datasets[datasetSnapshot.mapKey] =
          datasetSnapshot.restore(currentDatasetsById);
    }

    logic.connections
      ..clear()
      ..addAll(
        connections.map(
          (Map<String, dynamic> connection) => _deepCloneJsonMap(connection),
        ),
      );

    logic._nodeRamSnapshots
      ..clear()
      ..addAll(
        <String, Map<String, DatasetArtifactSnapshot>>{
          for (final MapEntry<String, Map<String, DatasetArtifactSnapshot>> entry
              in nodeRamSnapshots.entries)
            entry.key: Map<String, DatasetArtifactSnapshot>.from(entry.value),
        },
      );
    logic._nodeDiskSnapshotIds
      ..clear()
      ..addAll(
        <String, Set<String>>{
          for (final MapEntry<String, Set<String>> entry
              in nodeDiskSnapshotIds.entries)
            entry.key: Set<String>.from(entry.value),
        },
      );

    logic.selectedNodeId = selectedNodeId;
    logic.selectedNodeIds
      ..clear()
      ..addAll(selectedNodeIds);
    logic.selectedConnectionIndex = selectedConnectionIndex;
    logic._pendingFromNodeId = pendingFromNodeId;
    logic._pendingFromPortIndex = pendingFromPortIndex;
  }
}

Map<String, dynamic> _deepCloneJsonMap(Map<dynamic, dynamic> source) {
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in source.entries)
      entry.key.toString(): _deepCloneJsonValue(entry.value),
  };
}

dynamic _deepCloneJsonValue(dynamic value) {
  if (value is Map) {
    return _deepCloneJsonMap(value);
  }
  if (value is List) {
    return value.map(_deepCloneJsonValue).toList(growable: false);
  }
  return value;
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final T value in a) {
    if (!b.contains(value)) {
      return false;
    }
  }
  return true;
}

String _basename(String path) {
  final String normalized = path.replaceAll('\\', '/');
  final int slashIndex = normalized.lastIndexOf('/');
  return slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized;
}

class CanvasLogic {
  CanvasLogic();

  /// Registry of available node types in the sidebar.
  final List<NodeType> availableNodes = <NodeType>[
    ImportNodeType(),
    ChannelCoordinatesNodeType(),
    EditChannelsNodeType(),
    BridgeDetectorNodeType(),
    ResampleNodeType(),
    AverageNodeType(),
    BandpassNodeType(),
    AmplitudeFeaturesNodeType(),
    PSDNodeType(),
    FooofNodeType(),
    SpectralFeaturesNodeType(),
    MicrostatesNodeType(),
    PCANodeType(),
    ICANodeType(),
    EigenvalueDecompositionNodeType(),
    SourceReconstructionNodeType(),
    DetectPeaksNodeType(),
    InterbeatIntervalNodeType(),
    HeartRateVariabilityNodeType(),
    KMeansNodeType(),
    CNNNodeType(),
    AddRemoveMarkersNodeType(),
    InteractiveArtifactDetectionNodeType(),
    RecodeMarkersNodeType(),
    SegmentationNodeType(),
    EyeBlinksNodeType(),
    SleepStagingNodeType(),
    RealignNodeType(),
    ImpedancesNodeType(),
    TopomapNodeType(),
    VisualizationNodeType(),
    DebugOutputNodeType(),
    ExportNodeType(),
    PublishNodeType(),
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
  final ValueNotifier<List<BrainStoryJob>> jobs =
      ValueNotifier<List<BrainStoryJob>>(<BrainStoryJob>[]);
  final ValueNotifier<Map<String, NodeProcessIndicator>> nodeProcessIndicators =
      ValueNotifier<Map<String, NodeProcessIndicator>>(
    <String, NodeProcessIndicator>{},
  );
  final Map<String, Map<String, DatasetArtifactSnapshot>> _nodeRamSnapshots =
      <String, Map<String, DatasetArtifactSnapshot>>{};
  final Map<String, Set<String>> _nodeDiskSnapshotIds = <String, Set<String>>{};
  final Set<String> _cancelRequestedJobIds = <String>{};

  String? selectedNodeId;
  final Set<String> selectedNodeIds = <String>{};
  int? selectedConnectionIndex;
  String? keyboardFocusedNodeId;
  String? currentProjectPath;

  String? _pendingFromNodeId;
  int? _pendingFromPortIndex;
  int _lastGeneratedNodeIdMicros = 0;
  int _lastGeneratedJobIdMicros = 0;
  String? _activeRunJobId;
  String? _activeRunNodeId;
  final Map<NodeCategory, bool> _collapsedCategories = <NodeCategory, bool>{};
  final Map<String, bool> _collapsedSubcategories = <String, bool>{};

  static const double _cardWidth = 160;
  static const double _cardHeight = 72;
  static const double _spawnGap = 48;
  static const double _canvasPadding = 120;
  static const double _gridWidth = _cardWidth;
  static const double _gridHeight = _cardHeight + 24;
  static const int _maxUndoDepth = 60;

  final List<_CanvasUndoSnapshot> _undoStack = <_CanvasUndoSnapshot>[];

  bool get canUndo => _undoStack.isNotEmpty;

  String? undoLast() {
    if (_undoStack.isEmpty) {
      return null;
    }
    final _CanvasUndoSnapshot snapshot = _undoStack.removeLast();
    snapshot.restore(this);
    return snapshot.label;
  }

  void _recordUndo(
    String label, {
    Set<String> datasetArtifactIds = const <String>{},
  }) {
    _undoStack.add(
      _CanvasUndoSnapshot.capture(
        this,
        label,
        datasetArtifactIds: datasetArtifactIds,
      ),
    );
    if (_undoStack.length > _maxUndoDepth) {
      _undoStack.removeAt(0);
    }
  }

  void addNode(NodeType type) {
    _recordUndo('add ${type.title}');
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
      id: _nextNodeId(),
      type: type,
      position: position,
      params: initialParams,
    );
  }

  String _nextNodeId() {
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int nextMicros = nowMicros <= _lastGeneratedNodeIdMicros
        ? _lastGeneratedNodeIdMicros + 1
        : nowMicros;
    _lastGeneratedNodeIdMicros = nextMicros;
    return nextMicros.toString();
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

  void clearAll({bool recordUndo = true}) {
    if (recordUndo &&
        (nodes.isNotEmpty ||
            connections.isNotEmpty ||
            _nodeRamSnapshots.isNotEmpty ||
            _nodeDiskSnapshotIds.isNotEmpty)) {
      _recordUndo('clear all');
    }
    _clearAll();
  }

  void _clearAll() {
    nodes.clear();
    connections.clear();
    _nodeRamSnapshots.clear();
    _nodeDiskSnapshotIds.clear();
    _cancelRequestedJobIds.clear();
    jobs.value = const <BrainStoryJob>[];
    currentProjectPath = null;
    nodeProcessIndicators.value = const <String, NodeProcessIndicator>{};
    runActivity.value = null;
    _activeRunJobId = null;
    _activeRunNodeId = null;
    selectedNodeId = null;
    selectedNodeIds.clear();
    selectedConnectionIndex = null;
    keyboardFocusedNodeId = null;
    _clearPendingConnection();
  }

  Future<void> pickFiles() async {
    final List<XFile> files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'BrainStory Signals',
          extensions: <String>['csv', 'tsv', 'txt', 'edf', 'cnt', 'set', 'fdt', 'vhdr'],
        ),
      ],
    );

    if (files.isNotEmpty) {
      _recordUndo('import files');
    }

    for (final XFile file in files) {
      final String normalizedPath = brainVisionHeaderPathForSelection(
        eeglabMetadataPathForSelection(file.path),
      );
      final bool selectedFdt = file.name.toLowerCase().endsWith('.fdt');
      final bool selectedBrainVisionSidecar = file.name.toLowerCase().endsWith('.eeg') ||
          file.name.toLowerCase().endsWith('.vmrk');
      final bool hasUsablePath = normalizedPath.trim().isNotEmpty;
      final Uint8List? bytes = (!hasUsablePath || kIsWeb)
          ? await file.readAsBytes()
          : null;
      final bool normalizeSidecarName = hasUsablePath && !kIsWeb;
      final String sourceName = normalizeSidecarName
          ? selectedFdt
              ? '${file.name.substring(0, file.name.length - 4)}.set'
              : selectedBrainVisionSidecar
                  ? '${file.name.substring(0, file.name.length - 4)}.vhdr'
                  : file.name
          : file.name;
      final Dataset dataset = datasets.putIfAbsent(
        normalizedPath.isEmpty ? sourceName : normalizedPath,
        () => Dataset(
          DateTime.now().microsecondsSinceEpoch.toString(),
          label: sourceName,
          path: normalizedPath,
          sourceBytes: bytes,
        ),
      );
      dataset.label = sourceName;
      dataset.path = normalizedPath;
      dataset.sourceBytes = bytes;
      dataset.ram['source.filename'] = sourceName;
      _markAllNodes(dataset.id, DatasetState.notReady);
      _refreshDatasetAvailability(dataset.id);
    }
  }

  void deleteSelected() {
    final Set<String> targetIds = selectedNodeIds.isNotEmpty
        ? Set<String>.from(selectedNodeIds)
        : <String>{if (selectedNodeId != null) selectedNodeId!};
    if (targetIds.isEmpty) return;

    _recordUndo(targetIds.length == 1 ? 'delete node' : 'delete nodes');
    nodes.removeWhere((node) => targetIds.contains(node.id));
    connections.removeWhere(
          (connection) =>
      targetIds.contains(connection['fromNode']) ||
          targetIds.contains(connection['toNode']),
    );

    selectedNodeId = null;
    selectedNodeIds.clear();
    selectedConnectionIndex = null;
    if (targetIds.contains(keyboardFocusedNodeId)) {
      keyboardFocusedNodeId = null;
    }
    _clearPendingConnection();
  }

  void deleteSelectedConnection() {
    final int? index = selectedConnectionIndex;
    if (index == null || index < 0 || index >= connections.length) {
      return;
    }
    _recordUndo('delete wire');
    connections.removeAt(index);
    selectedConnectionIndex = null;
  }

  void selectNodesInRect(Rect selectionRect) {
    selectedNodeIds.clear();
    for (final NodeModel node in nodes) {
      final Rect nodeRect = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        _cardWidth,
        _cardHeight,
      );
      if (selectionRect.overlaps(nodeRect)) {
        selectedNodeIds.add(node.id);
      }
    }
    selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
    selectedConnectionIndex = null;
    if (selectedNodeIds.isNotEmpty) {
      _clearPendingConnection();
    }
  }

  bool selectConnectionAt(Offset canvasOffset) {
    final int? index = _connectionIndexAt(canvasOffset);
    if (index == null) {
      return false;
    }
    selectedNodeId = null;
    selectedNodeIds.clear();
    selectedConnectionIndex = index;
    _clearPendingConnection();
    return true;
  }

  bool deleteConnectionAt(Offset canvasOffset) {
    final int? index = _connectionIndexAt(canvasOffset);
    if (index == null) {
      return false;
    }
    _recordUndo('delete wire');
    connections.removeAt(index);
    selectedConnectionIndex = null;
    return true;
  }

  void clearConnectionDraft() {
    _clearPendingConnection();
  }

  NodeModel? get keyboardFocusedNode {
    final String? focusedId = keyboardFocusedNodeId;
    return focusedId == null ? null : _findNode(focusedId);
  }

  void setKeyboardFocusedNode(NodeModel? node) {
    keyboardFocusedNodeId = node?.id;
  }

  void activateNodeFromKeyboard(NodeModel node) {
    keyboardFocusedNodeId = node.id;
    _handleNodeTap(node);
  }

  void openNodeEditorFromKeyboard({
    required BuildContext context,
    required NodeModel node,
    required VoidCallback update,
  }) {
    keyboardFocusedNodeId = node.id;
    selectedNodeId = node.id;
    selectedNodeIds
      ..clear()
      ..add(node.id);
    selectedConnectionIndex = null;
    _openNodeEditor(
      context: context,
      node: node,
      update: update,
    );
  }

  void _clearPendingConnection() {
    _pendingFromNodeId = null;
    _pendingFromPortIndex = null;
  }

  void _collectNodeBranches(
    NodeModel node,
    List<NodeModel> currentBranch,
    List<List<NodeModel>> branches,
  ) {
    final List<NodeModel> nextBranch = <NodeModel>[...currentBranch, node];
    final List<NodeModel> children = _immediateChildren(node.id);
    if (children.isEmpty) {
      branches.add(nextBranch);
      return;
    }
    for (final NodeModel child in children) {
      _collectNodeBranches(child, nextBranch, branches);
    }
  }

  String _datasetTypeLabel(Dataset dataset) {
    final String path = dataset.path.toLowerCase();
    if (path.endsWith('.edf')) {
      return 'EDF';
    }
    if (path.endsWith('.cnt')) {
      return 'ANT CNT';
    }
    if (path.endsWith('.set') || path.endsWith('.fdt')) {
      return 'EEGLAB';
    }
    if (path.endsWith('.csv')) {
      return 'CSV';
    }
    if (path.endsWith('.tsv')) {
      return 'TSV';
    }
    if (path.endsWith('.txt')) {
      return 'text';
    }
    return '';
  }

  String _methodsClauseForNode(NodeModel node) {
    final Map<String, dynamic> params = node.params;
    switch (node.title) {
      case 'Import':
        return 'Data were imported into the workflow.';
      case 'Bridge Detector':
        final int windowSamples = (params['windowSamples'] as num?)?.toInt() ?? 1000;
        return 'Bridge detection was performed by computing channel-wise correlation matrices over the last $windowSamples samples of each full minute of recording.';
      case 'Resample':
        final double sampleRate = (params['newSampleRate'] as num?)?.toDouble() ?? 256.0;
        final String method = (params['method'] ?? 'cubic_spline').toString().replaceAll('_', ' ');
        final bool omitSpikes = (params['omitSpikes'] as bool?) ?? false;
        return 'Signals were resampled to ${sampleRate.toStringAsFixed(sampleRate.truncateToDouble() == sampleRate ? 0 : 2)} Hz using $method interpolation${omitSpikes ? ' with spike omission enabled' : ''}.';
      case 'Bandpass Filter':
        final double low = (params['low'] as num?)?.toDouble() ?? 1.0;
        final double high = (params['high'] as num?)?.toDouble() ?? 40.0;
        final double steepness = (params['steepness'] as num?)?.toDouble() ?? 0.8;
        final double? notch = (params['notch'] as num?)?.toDouble();
        return 'A bandpass filter ($low-$high Hz, steepness $steepness${notch == null ? '' : ', notch at $notch Hz'}) was applied.';
      case 'PSD':
        final double fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
        final double fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
        final String outputMode = (params['outputMode'] ?? 'averaged').toString();
        return 'Power spectral density was estimated from $fLow to $fHigh Hz using ${outputMode == 'segments' ? 'segment-wise output' : 'averaged output'}.';
      case 'FOOOF':
        final double fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
        final double fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
        final int maxPeaks = (params['maxPeaks'] as num?)?.toInt() ?? 4;
        return 'Spectral parameterization was performed from $fLow to $fHigh Hz to estimate the aperiodic intercept and exponent and to identify up to $maxPeaks oscillatory peaks.';
      case 'Spectral Features':
        final List<String> groups = _selectedSpectralFeatureGroups(params);
        return 'Spectral features were extracted from the PSD${groups.isEmpty ? '' : ' (${_joinWithCommas(groups)})'} and assembled into a tabular output.';
      case 'Amplitude Features':
        final List<String> groups = _selectedAmplitudeFeatureGroups(params);
        return 'Time-domain amplitude features were extracted from the signal${groups.isEmpty ? '' : ' (${_joinWithCommas(groups)})'} and assembled into a tabular output.';
      case 'Segmentation':
        return _segmentationMethodsClause(params);
      case 'Realign':
        final double upsampleRate = (params['upsampleRateHz'] as num?)?.toDouble() ?? 100000.0;
        final String method = (params['method'] ?? 'cubic_spline').toString().replaceAll('_', ' ');
        final double maxShiftMs = (params['maxShiftMs'] as num?)?.toDouble() ?? 5.0;
        return 'Segmented data were temporarily upsampled to ${upsampleRate.toStringAsFixed(0)} Hz, realigned by cross-correlation using $method interpolation with a maximum shift of $maxShiftMs ms, and then returned to the original sampling rate.';
      case 'Sleep Staging':
        final double epochSeconds = (params['epochSeconds'] as num?)?.toDouble() ?? 30.0;
        return 'Sleep-stage markers were generated in ${epochSeconds.toStringAsFixed(epochSeconds.truncateToDouble() == epochSeconds ? 0 : 1)}-second epochs while the underlying time-series data were passed through unchanged.';
      case 'Eye Blinks':
        return 'Ocular-event marker detection was configured to emit blink, vertical saccade, and horizontal saccade markers.';
      case 'Interactive Artifact Detection':
        return 'Artifact exemplars were labeled interactively in the time-domain viewer, evolving templates were built by aligned averaging, and candidate artifact matches were reviewed and accepted or rejected within the workflow.';
      case 'Add/Remove Markers':
        return 'Manual marker edits were incorporated into the analysis graph.';
      case 'PCA':
      case 'ICA':
      case 'Eigenvalue Decomposition':
      case 'Microstates':
      case 'K-Means':
      case 'CNN':
        return '${node.title} was included as a configured processing stage in the workflow.';
      case 'EEG Visualization':
        return 'A dedicated visualization node was used for explicit comparison of outputs across branches of the pipeline.';
      case 'Debug Output':
        return 'Intermediate outputs were inspected using a debug-output node.';
      case 'Export':
        final String fileType =
            (params['fileType'] ?? 'edf').toString().toUpperCase();
        return 'Processed outputs were exported as $fileType files.';
      case 'Publish':
        return 'A publish endpoint was configured to generate manuscript-ready descriptions of the workflow and its outputs.';
      default:
        return '${node.title} was included as a processing stage.';
    }
  }

  List<String> _selectedSpectralFeatureGroups(Map<String, dynamic> params) {
    final Map<String, String> labels = <String, String>{
      'power': 'power features',
      'ratios': 'power ratios',
    };
    final List<String> selected = <String>[];
    for (final MapEntry<String, String> entry in labels.entries) {
      if ((params[entry.key] as bool?) ?? false) {
        selected.add(entry.value);
      }
    }
    return selected;
  }

  List<String> _selectedAmplitudeFeatureGroups(Map<String, dynamic> params) {
    final Map<String, String> labels = <String, String>{
      'peak_amplitude': 'peak amplitude',
      'peak_latency': 'peak latency',
      'auc': 'area under the curve',
      'variance': 'variance',
    };
    final Map<String, dynamic> selectedMap = Map<String, dynamic>.from(
      params['amplitudeFeatures'] as Map? ?? <String, dynamic>{},
    );
    final List<String> selected = <String>[];
    for (final MapEntry<String, String> entry in labels.entries) {
      if (selectedMap[entry.key] == true) {
        selected.add(entry.value);
      }
    }
    return selected;
  }

  String _segmentationMethodsClause(Map<String, dynamic> params) {
    final String mode = (params['segmentationMode'] ?? 'events').toString();
    if (mode == 'blocks') {
      final bool concatenate = (params['blocksConcatenate'] as bool?) ?? false;
      final bool invert = (params['blocksInvert'] as bool?) ?? false;
      return 'Data were segmented into marker-defined blocks${concatenate ? ', and multiple blocks were concatenated' : ''}${invert ? ', using the complement of the selected blocks' : ''}.';
    }
    if (mode == 'equal_windows') {
      final double widthMs = (params['equalWidthMs'] as num?)?.toDouble() ?? 1000.0;
      final double overlapPct = (params['equalOverlapPct'] as num?)?.toDouble() ?? 0.0;
      return 'Data were segmented into equal windows of ${widthMs.toStringAsFixed(widthMs.truncateToDouble() == widthMs ? 0 : 1)} ms with ${overlapPct.toStringAsFixed(overlapPct.truncateToDouble() == overlapPct ? 0 : 1)}% overlap.';
    }
    final double windowStart = (params['eventsWindowStartMs'] as num?)?.toDouble() ?? 0.0;
    final double windowStop = (params['eventsWindowStopMs'] as num?)?.toDouble() ?? 0.0;
    final double baselineStart = (params['eventsBaselineStartMs'] as num?)?.toDouble() ?? 0.0;
    final double baselineStop = (params['eventsBaselineStopMs'] as num?)?.toDouble() ?? 0.0;
    return 'Event-locked segmentation was performed with a window from ${windowStart.toStringAsFixed(windowStart.truncateToDouble() == windowStart ? 0 : 1)} to ${windowStop.toStringAsFixed(windowStop.truncateToDouble() == windowStop ? 0 : 1)} ms and a baseline interval from ${baselineStart.toStringAsFixed(baselineStart.truncateToDouble() == baselineStart ? 0 : 1)} to ${baselineStop.toStringAsFixed(baselineStop.truncateToDouble() == baselineStop ? 0 : 1)} ms.';
  }

  String _joinWithCommas(List<String> values) {
    if (values.isEmpty) {
      return '';
    }
    if (values.length == 1) {
      return values.first;
    }
    if (values.length == 2) {
      return '${values.first} and ${values.last}';
    }
    return '${values.sublist(0, values.length - 1).join(', ')}, and ${values.last}';
  }

  List<String> _methodsClausesForBranch(List<NodeModel> branch) {
    return branch
        .map(_methodsClauseForNode)
        .where((String clause) => clause.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<String> _longestCommonClausePrefix(List<List<String>> branches) {
    if (branches.isEmpty) {
      return const <String>[];
    }
    final int maxPrefixLength = branches
        .map((List<String> branch) => branch.length)
        .reduce(math.min);
    final List<String> prefix = <String>[];
    for (int index = 0; index < maxPrefixLength; index++) {
      final String candidate = branches.first[index];
      final bool allMatch = branches.every(
        (List<String> branch) => branch[index] == candidate,
      );
      if (!allMatch) {
        break;
      }
      prefix.add(candidate);
    }
    return prefix;
  }

  String get saveBrainStoryLabel {
    final String? path = currentProjectPath;
    if (path == null || path.trim().isEmpty) {
      return 'Save BrainStory';
    }
    return 'Save ${_basename(path)}';
  }

  Future<void> saveBrainStory(BuildContext context) async {
    final String? path = currentProjectPath;
    if (path == null || path.trim().isEmpty) {
      await saveBrainStoryAs(context);
      return;
    }

    final String jsonPayload = const JsonEncoder.withIndent('  ').convert(
      exportProjectJson(),
    );
    final String? savedPath = await saveBrainStoryProject(
      suggestedName: _basename(path),
      targetPath: path,
      jsonPayload: jsonPayload,
    );
    if (savedPath != null) {
      currentProjectPath = savedPath;
    }
    if (context.mounted) {
      _showStatusSnackBar(
        context,
        savedPath == null
            ? 'BrainStory save was canceled.'
            : 'Saved BrainStory project to $savedPath.',
      );
    }
  }

  Future<void> saveBrainStoryAs(BuildContext context) async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: currentProjectPath == null
          ? 'brainstory_project.bst'
          : _basename(currentProjectPath!),
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
      suggestedName: _basename(location.path),
      targetPath: location.path,
      jsonPayload: jsonPayload,
    );
    if (savedPath != null) {
      currentProjectPath = savedPath;
    }
    if (context.mounted) {
      _showStatusSnackBar(
        context,
        savedPath == null
            ? 'BrainStory save was canceled.'
            : 'Saved BrainStory project to $savedPath.',
      );
    }
  }

  Future<void> openBrainStory(BuildContext context) async {
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
      _recordUndo('load BrainStory');
      importProjectJson(jsonMap);
      currentProjectPath = file.path;
      await _refreshDiskSnapshotFlagsForLoadedProject();
      _normalizeNodeStatesAfterProjectLoad();
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

  Future<void> exportBrainStory(BuildContext context) => saveBrainStoryAs(context);

  Future<void> loadBrainStory(BuildContext context) => openBrainStory(context);

  Future<void> showPublishDialog(BuildContext context) async {
    final String methodsText = generateMethodsDescription();
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Publish'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: SelectableText(methodsText),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: methodsText));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  _showStatusSnackBar(
                    context,
                    'Copied publish-ready methods text to the clipboard.',
                  );
                }
              },
              child: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  Future<List<MemoryArtifactSummary>> memoryArtifactSummaries() async {
    final List<MemoryArtifactSummary> summaries = <MemoryArtifactSummary>[];
    final List<NodeModel> orderedNodes =
        _orderedNodes(nodes.map((NodeModel node) => node.id).toSet());
    final List<Dataset> orderedDatasets = datasets.values.toList(growable: false)
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));

    for (final NodeModel node in orderedNodes) {
      final NodeDatasetStatusSnapshot status = await _datasetStatusSnapshotForNode(
        node: node,
        params: node.params,
      );
      for (final Dataset dataset in orderedDatasets) {
        final DatasetState processingState =
            status.processedDatasetStates[dataset.id] ?? DatasetState.notReady;
        final bool inRam = status.ramLoadedDatasetIds.contains(dataset.id);
        final bool onDisk = status.diskSavedDatasetIds.contains(dataset.id);
        final bool available = status.availableDatasetIds.contains(dataset.id);
        if (!available &&
            processingState == DatasetState.notReady &&
            !inRam &&
            !onDisk) {
          continue;
        }

        final DatasetArtifactSnapshot? snapshot =
            _nodeRamSnapshots[node.id]?[dataset.id];
        summaries.add(
          MemoryArtifactSummary(
            nodeId: node.id,
            nodeDescriptor: _nodeDescriptor(node),
            datasetId: dataset.id,
            datasetLabel: dataset.label,
            artifactLabel: _memoryArtifactLabel(
              node: node,
              dataset: dataset,
              snapshot: snapshot,
            ),
            processingState: processingState,
            inRam: inRam,
            onDisk: onDisk,
            precisionLabel: _memoryPrecisionLabel(
              node: node,
              dataset: dataset,
              snapshot: snapshot,
            ),
            approxRamBytes: snapshot == null
                ? 0
                : _estimateSnapshotNumericBytes(snapshot),
            approxDiskBytes: onDisk
                ? await nodeSnapshotDiskBytes(
                    nodeId: node.id,
                    datasetId: dataset.id,
                  )
                : null,
          ),
        );
      }
    }

    return summaries;
  }

  Future<String> loadMemorySummariesToRam(
    Iterable<MemoryArtifactSummary> rows,
  ) async {
    return _runMemorySummaryAction(
      rows,
      (NodeModel node, Set<String> datasetIds) => _loadNodeSnapshotsToRam(
        node: node,
        datasetIds: datasetIds,
        update: () {},
      ),
    );
  }

  Future<String> saveMemorySummariesToDisk(
    Iterable<MemoryArtifactSummary> rows,
  ) async {
    return _runMemorySummaryAction(
      rows,
      (NodeModel node, Set<String> datasetIds) => _saveNodeSnapshotsToDisk(
        node: node,
        datasetIds: datasetIds,
        update: () {},
      ),
    );
  }

  Future<String> purgeMemorySummariesFromRam(
    Iterable<MemoryArtifactSummary> rows,
  ) async {
    return _runMemorySummaryAction(
      rows,
      (NodeModel node, Set<String> datasetIds) => _clearNodeResults(
        node: node,
        params: node.params,
        datasetIds: datasetIds,
        update: () {},
      ),
    );
  }

  Future<String> purgeMemorySummariesFromDisk(
    Iterable<MemoryArtifactSummary> rows,
  ) async {
    return _runMemorySummaryAction(
      rows,
      (NodeModel node, Set<String> datasetIds) => _deleteNodeSnapshotsFromDisk(
        node: node,
        datasetIds: datasetIds,
        update: () {},
      ),
    );
  }

  String generateMethodsDescription() {
    if (nodes.isEmpty) {
      return 'No BrainStory pipeline is currently defined.';
    }

    final List<String> datasetLabels = datasets.values
        .map((Dataset dataset) => dataset.label.trim().isEmpty ? 'Dataset' : dataset.label.trim())
        .toList(growable: false)
      ..sort();
    final Set<String> datasetTypes = datasets.values
        .map(_datasetTypeLabel)
        .where((String type) => type.isNotEmpty)
        .toSet();
    final List<NodeModel> roots = nodes
        .where((NodeModel node) => _immediateParents(node.id).isEmpty)
        .toList(growable: false);
    final List<List<NodeModel>> branches = <List<NodeModel>>[];
    for (final NodeModel root in roots) {
      _collectNodeBranches(root, <NodeModel>[], branches);
    }
    final List<List<String>> branchClauses = branches
        .map(_methodsClausesForBranch)
        .where((List<String> clauses) => clauses.isNotEmpty)
        .toList(growable: false);
    final List<List<String>> uniqueBranchClauses = <List<String>>[];
    final Set<String> seenBranchTexts = <String>{};
    for (final List<String> clauses in branchClauses) {
      final String branchKey = clauses.join(' ');
      if (seenBranchTexts.add(branchKey)) {
        uniqueBranchClauses.add(clauses);
      }
    }
    final List<String> sharedPrefix = _longestCommonClausePrefix(uniqueBranchClauses);
    final List<List<String>> branchSuffixes = uniqueBranchClauses
        .map(
          (List<String> clauses) => clauses.length <= sharedPrefix.length
              ? const <String>[]
              : clauses.sublist(sharedPrefix.length),
        )
        .toList(growable: false);

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('Data were processed in BrainStory using a node-based analysis pipeline.');
    if (datasetLabels.isNotEmpty) {
      final String datasetSummary = datasetLabels.length == 1
          ? datasetLabels.first
          : '${datasetLabels.length} datasets (${_joinWithCommas(datasetLabels)})';
      if (datasetTypes.isNotEmpty) {
        final List<String> sortedTypes = datasetTypes.toList(growable: false)..sort();
        buffer.writeln(
          'The workflow operated on $datasetSummary imported from ${_joinWithCommas(sortedTypes)} source files.',
        );
      } else {
        buffer.writeln('The workflow operated on $datasetSummary.');
      }
    }
    buffer.writeln();
    buffer.writeln('Pipeline summary:');

    if (uniqueBranchClauses.isEmpty) {
      final String fallback = nodes
          .map(_methodsClauseForNode)
          .where((String clause) => clause.isNotEmpty)
          .join(' ');
      buffer.writeln('1. $fallback');
    } else if (uniqueBranchClauses.length == 1) {
      buffer.writeln('1. ${uniqueBranchClauses.first.join(' ')}');
    } else {
      if (sharedPrefix.isNotEmpty) {
        buffer.writeln('Shared preprocessing: ${sharedPrefix.join(' ')}');
        buffer.writeln();
        buffer.writeln(
          'After the shared preprocessing steps, the workflow diverged into ${uniqueBranchClauses.length} analysis branches:',
        );
      }

      int branchNumber = 1;
      for (final List<String> suffix in branchSuffixes) {
        final String branchText = suffix.isEmpty
            ? 'No additional branch-specific processing steps were applied.'
            : suffix.join(' ');
        buffer.writeln('$branchNumber. $branchText');
        branchNumber++;
      }
    }

    if (nodes.any(canVisualizeNode)) {
      buffer.writeln();
      buffer.writeln(
        'Outputs were reviewed visually within BrainStory using node-linked inspection views appropriate to each data type, including raw time-domain traces, power spectra, hypnograms, and bridge-detection heatmaps when available.',
      );
    }

    return buffer.toString().trimRight();
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
              'markerChange': node.markerChange.toJson(),
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
    clearAll(recordUndo: false);
    datasets.clear();

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
        markerChange: data['markerChange'] is Map<String, dynamic>
            ? MarkerChange.fromJson(data['markerChange'] as Map<String, dynamic>)
            : data['markerChange'] is Map
                ? MarkerChange.fromJson(
                    Map<String, dynamic>.from(data['markerChange'] as Map),
                  )
                : const MarkerChange(),
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
    required VoidCallback update,
  }) {
    final List<NodeCategory> categoryOrder = <NodeCategory>[
      NodeCategory.import,
      NodeCategory.transform,
      NodeCategory.machineLearning,
      NodeCategory.markerFunctions,
      NodeCategory.endpoints,
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
        .where((NodeType node) {
          return node.allPlacements.any(
            (NodePlacement placement) => placement.category == category,
          );
        })
        .toList(growable: false);
    final Map<String, List<NodeType>> nodesBySubcategory = <String, List<NodeType>>{};
    for (final NodeType type in categoryNodes) {
      for (final NodePlacement placement in type.allPlacements) {
        if (placement.category != category) {
          continue;
        }
        nodesBySubcategory
            .putIfAbsent(placement.subcategory, () => <NodeType>[])
            .add(type);
      }
    }
    for (final List<NodeType> types in nodesBySubcategory.values) {
      types.sort((NodeType a, NodeType b) => a.title.compareTo(b.title));
    }
    final List<String> subcategoryOrder = nodesBySubcategory.keys.toList()..sort();
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
        for (final String subcategory in subcategoryOrder) ...<Widget>[
          Builder(
            builder: (BuildContext context) {
              final String collapseKey = '${category.name}::$subcategory';
              final bool subcategoryCollapsed =
                  _collapsedSubcategories[collapseKey] ?? false;
              return Column(
                children: <Widget>[
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _collapsedSubcategories[collapseKey] =
                          !subcategoryCollapsed;
                      update();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 28, bottom: 6, top: 2),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            subcategoryCollapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            color: Colors.white.withValues(alpha: 0.72),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              subcategory,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!subcategoryCollapsed)
                    for (final NodeType type in nodesBySubcategory[subcategory]!)
                      Padding(
                        padding: const EdgeInsets.only(left: 36, bottom: 6),
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
                ],
              );
            },
          ),
        ],
    ];
  }

  List<Widget> connectionWidgets() {
    final Map<String, NodeModel> nodeById = <String, NodeModel>{
      for (final NodeModel node in nodes) node.id: node,
    };
    return connections.asMap().entries.map((MapEntry<int, Map<String, dynamic>> entry) {
      final int connectionIndex = entry.key;
      final Map<String, dynamic> connection = entry.value;
      final NodeModel? fromNode = nodeById[connection['fromNode'] as String];
      final NodeModel? toNode = nodeById[connection['toNode'] as String];

      if (fromNode == null || toNode == null) {
        return const SizedBox.shrink();
      }

      final int fromPort = (connection['fromPort'] as num?)?.toInt() ?? 0;
      final Offset start = _outputAnchor(fromNode, toNode, fromPortIndex: fromPort);
      final Offset end = _inputAnchor(fromNode, toNode);
      final bool preferVertical = _shouldUseVerticalAnchors(fromNode, toNode);

        return CustomPaint(
          painter: ConnectionPainter(
            start: start,
            end: end,
            preferVertical: preferVertical,
            gridWidth: _gridWidth,
            gridHeight: _gridHeight,
            obstacles: _connectionObstacles(fromNode, toNode),
            selected: selectedConnectionIndex == connectionIndex,
            color: _outputColorForPort(fromNode, fromPort),
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
        processIndicator: _processViewForNode(node),
        highlighted: _isHighlighted(node),
        highlightColor: _nodeHighlightColor(node),
        done: node.visualState == DatasetState.done,
        onDragEnd: (Offset globalOffset) {
          moveNodeOrSelection(
            node,
            translateDropOffset(globalOffset),
          );
          update();
        },
        onTap: () {
          _handleNodeTap(node);
          update();
        },
        onDoubleTap: () {
          selectedNodeId = node.id;
          selectedNodeIds
            ..clear()
            ..add(node.id);
          if (canVisualizeNode(node)) {
            openVisualizationWindow(node);
            return;
          }
          _openNodeEditor(
            context: context,
            node: node,
            update: update,
          );
        },
        onDelete: () {
          selectedNodeId = node.id;
          selectedNodeIds
            ..clear()
            ..add(node.id);
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
          final Set<String> datasetIds = _datasetsForNode(node);
          if (await promptLoadFromDiskInsteadOfRun(
            context: context,
            node: node,
            datasetIds: datasetIds,
            update: update,
          )) {
            return;
          }
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
            failRunUi(error);
            if (context.mounted) {
              _showStatusSnackBar(
                context,
                error is BrainStoryRunCanceled
                    ? 'Run canceled.'
                    : 'Run failed: $error',
              );
            }
          } finally {
            if (runActivity.value != null) {
              finishRunUi();
            }
          }
        },
        onRunFromStart: () async {
          final Set<String> datasetIds = _datasetsForNode(node);
          if (await promptLoadFromDiskInsteadOfRun(
            context: context,
            node: node,
            datasetIds: datasetIds,
            update: update,
          )) {
            return;
          }
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
            failRunUi(error);
            if (context.mounted) {
              _showStatusSnackBar(
                context,
                error is BrainStoryRunCanceled
                    ? 'Run canceled.'
                    : 'Run failed: $error',
              );
            }
          } finally {
            if (runActivity.value != null) {
              finishRunUi();
            }
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
            failRunUi(error);
            if (context.mounted) {
              _showStatusSnackBar(
                context,
                error is BrainStoryRunCanceled
                    ? 'Run canceled.'
                    : 'Run failed: $error',
              );
            }
          } finally {
            if (runActivity.value != null) {
              finishRunUi();
            }
          }
        },
      );
    }).toList();
  }

  void _handleNodeTap(NodeModel node) {
    final bool canUseSelectionAsConnectionSource =
        selectedNodeId != null &&
            selectedNodeId != node.id &&
            selectedNodeIds.length <= 1;
    if (!canUseSelectionAsConnectionSource) {
      selectedNodeId = node.id;
      selectedNodeIds
        ..clear()
        ..add(node.id);
      selectedConnectionIndex = null;
      return;
    }

    final NodeModel? fromNode = _findNode(selectedNodeId!);
    if (fromNode == null) {
      selectedNodeId = node.id;
      selectedNodeIds
        ..clear()
        ..add(node.id);
      selectedConnectionIndex = null;
      _clearPendingConnection();
      return;
    }

    final _PortConnection? portConnection =
        _firstMatchingPortConnection(fromNode, node);
    final bool validDirection = _isValidDownstreamPlacement(fromNode, node);
    final bool introducesCycle =
        _collectDescendantsInclusive(node.id).contains(fromNode.id);

    if (portConnection == null || !validDirection || introducesCycle) {
      selectedNodeId = node.id;
      selectedNodeIds
        ..clear()
        ..add(node.id);
      selectedConnectionIndex = null;
      return;
    }

    final Map<String, dynamic> nextConnection = <String, dynamic>{
      'fromNode': fromNode.id,
      'fromPort': portConnection.fromPortIndex,
      'toNode': node.id,
      'toPort': portConnection.toPortIndex,
    };

    final bool duplicate = connections.any(
      (Map<String, dynamic> connection) =>
          connection['fromNode'] == nextConnection['fromNode'] &&
          connection['fromPort'] == nextConnection['fromPort'] &&
          connection['toNode'] == nextConnection['toNode'] &&
          connection['toPort'] == nextConnection['toPort'],
    );

    if (!duplicate) {
      _recordUndo('connect nodes');
      connections.add(nextConnection);
    }

    selectedNodeId = node.id;
    selectedNodeIds
      ..clear()
      ..add(node.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();
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
            failRunUi(error);
            if (context.mounted) {
              _showStatusSnackBar(
                context,
                error is BrainStoryRunCanceled
                    ? 'Run canceled.'
                    : 'Run failed: $error',
              );
            }
          } finally {
            if (runActivity.value != null) {
              finishRunUi();
            }
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
    _recordUndo('edit ${node.title} parameters');
    final Map<String, dynamic> previousParams = _deepCloneJsonMap(node.params);
    final Map<dynamic, DatasetState> previousStates =
        Map<dynamic, DatasetState>.from(node.datasetStates);
    final bool outputParametersChanged =
        node.type.paramsAffectOutput(previousParams, params);
    node.params = params;
    if (node.type is ImportNodeType) {
      ImportNodeType.applyDatasetAliases(params, datasets.values);
    }
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(node);
    for (final Dataset dataset in datasets.values) {
      final bool selected = availableDatasetIds.contains(dataset.id);
      if (!selected) {
        node.datasetStates[dataset.id] = DatasetState.notReady;
        continue;
      }

      final DatasetState previousState =
          previousStates[dataset.id] ?? DatasetState.notReady;
      if (!outputParametersChanged) {
        node.datasetStates[dataset.id] =
            previousState == DatasetState.notReady ? DatasetState.ready : previousState;
        continue;
      }

      node.datasetStates[dataset.id] = DatasetState.ready;
      if (previousState == DatasetState.done || previousState == DatasetState.stale) {
        _markImmediateChildrenStale(
          node.id,
          dataset.id,
          changeSet: ArtifactChangeSet(
            datasetId: dataset.id,
            sourceNodeId: node.id,
            changeTypes: const <ArtifactChangeType>{
              ArtifactChangeType.params,
            },
            paramKeys: _changedParamKeys(previousParams, params),
            description: '${node.title} parameters changed.',
          ),
        );
      }
    }
    update();
  }

  List<String> _changedParamKeys(
    Map<String, dynamic> previousParams,
    Map<String, dynamic> nextParams,
  ) {
    final Set<String> keys = <String>{
      ...previousParams.keys,
      ...nextParams.keys,
    };
    final List<String> changed = keys.where((String key) {
      return jsonEncode(previousParams[key]) != jsonEncode(nextParams[key]);
    }).toList()
      ..sort();
    return changed;
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

    return sourceDatasetsForVisualizationNode(node.id);
  }

  Future<List<Dataset>> datasetsForVisualizationNode(String nodeId) async {
    final List<VisualizationSourceRef> sources =
        visualizationSourceRefsForNode(nodeId);
    return materializedDatasetViewsForSourceRefs(sources);
  }

  List<Dataset> sourceDatasetsForVisualizationNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return <Dataset>[];
    }

    final Set<String> datasetIds = _availableDatasetIdsForNode(node);
    final List<Dataset> matchingDatasets = datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList(growable: false);
    matchingDatasets.sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    return matchingDatasets;
  }

  List<VisualizationSourceRef> visualizationSourceRefsForNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return const <VisualizationSourceRef>[];
    }

    final List<VisualizationSourceRef> refs = <VisualizationSourceRef>[];
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id)
          .where((NodeModel parent) => parent.outputPorts.isNotEmpty)
          .toList(growable: false)
        ..sort(
          (NodeModel a, NodeModel b) =>
              _nodeDescriptor(a).compareTo(_nodeDescriptor(b)),
        );
      for (final NodeModel parent in parents) {
        final Set<String> datasetIds = _availableDatasetIdsForNode(parent);
        final List<Dataset> matchingDatasets = datasets.values
            .where((Dataset dataset) => datasetIds.contains(dataset.id))
            .toList(growable: false)
          ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
        for (final Dataset dataset in matchingDatasets) {
          refs.add(
            VisualizationSourceRef(
              key: '${parent.id}|${dataset.id}',
              datasetId: dataset.id,
              datasetLabel: dataset.label,
              materializeFromNodeId: parent.id,
              sourceDescriptor: _nodeDescriptor(parent),
            ),
          );
        }
      }
      return refs;
    }

    final Set<String> datasetIds = _availableDatasetIdsForNode(node);
    final List<Dataset> matchingDatasets = datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList(growable: false)
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    for (final Dataset dataset in matchingDatasets) {
      refs.add(
        VisualizationSourceRef(
          key: '${node.id}|${dataset.id}',
          datasetId: dataset.id,
          datasetLabel: dataset.label,
          materializeFromNodeId: node.id,
          sourceDescriptor: _nodeDescriptor(node),
        ),
      );
    }
    return refs;
  }

  Future<List<Dataset>> materializedDatasetViewsForNode(
    String nodeId,
    List<Dataset> sources,
  ) async {
    final List<Dataset> views = <Dataset>[];
    for (final Dataset source in sources) {
      views.add(await materializedDatasetViewForNode(nodeId, source));
    }
    return views;
  }

  Future<List<Dataset>> materializedDatasetViewsForSourceRefs(
    List<VisualizationSourceRef> sources,
  ) async {
    final List<Dataset> views = <Dataset>[];
    for (final VisualizationSourceRef source in sources) {
      views.add(await materializedDatasetViewForSourceRef(source));
    }
    return views;
  }

  Future<Dataset> materializedDatasetViewForSourceRef(
    VisualizationSourceRef source,
  ) async {
    final Dataset? dataset = datasets[source.datasetId];
    if (dataset == null) {
      return Dataset(source.datasetId, label: source.displayLabel);
    }
    final Dataset view = await materializedDatasetViewForNode(
      source.materializeFromNodeId,
      dataset,
    );
    view.label = source.displayLabel;
    view.ram['viewer.sourceKey'] = source.key;
    view.ram['viewer.sourceDescriptor'] = source.sourceDescriptor;
    view.ram['viewer.baseDatasetLabel'] = source.datasetLabel;
    return view;
  }

  Future<Dataset> materializedDatasetViewForNode(String nodeId, Dataset source) async {
    final Dataset view = _datasetShell(source);
    final Set<String> ancestorIds = _collectAncestorsInclusive(nodeId);
    final List<NodeModel> orderedAncestors = _orderedNodes(ancestorIds);
    bool appliedAnySnapshot = false;

    for (final NodeModel ancestor in orderedAncestors) {
      if (ancestor.datasetStates[source.id] != DatasetState.done) {
        continue;
      }
      final DatasetArtifactSnapshot? snapshot =
          await _loadSnapshotForNodeDataset(
        ancestor.id,
        source.id,
        cacheInRam: _shouldCacheLoadedSnapshotInRam(ancestor),
      );
      if (snapshot != null && !snapshot.isEmpty) {
        _snapshotScopedToNodeOutputs(ancestor, snapshot).applyToDataset(view);
        appliedAnySnapshot = true;
        continue;
      }
      if (ancestor.type is ImportNodeType && !appliedAnySnapshot) {
        _applyLiveSourceArtifacts(view, source);
      }
    }

    if (!appliedAnySnapshot && view.timeSeries == null) {
      _applyLiveSourceArtifacts(view, source);
    }
    return view;
  }

  Dataset _datasetShell(Dataset source) {
    final Dataset shell = Dataset(
      source.id,
      label: source.label,
      path: source.path,
    );
    shell.loaded = source.loaded;
    final Object? sourceFilename = source.ram['source.filename'];
    if (sourceFilename != null) {
      shell.ram['source.filename'] = sourceFilename;
    }
    return shell;
  }

  void _applyLiveSourceArtifacts(Dataset target, Dataset source) {
    target.timeSeries = source.timeSeries?.copyWith();
    final Map<BrainStoryArtifactKind, ArtifactIdentity> sourceIdentities =
        source.artifactIdentities;
    target.artifactIdentities =
        Map<BrainStoryArtifactKind, ArtifactIdentity>.fromEntries(
      sourceIdentities.entries.where(
        (MapEntry<BrainStoryArtifactKind, ArtifactIdentity> entry) =>
            entry.key == BrainStoryArtifactKind.timeSeries ||
            entry.key == BrainStoryArtifactKind.markers,
      ),
    );
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
    if (node.type is BridgeDetectorNodeType) {
      return true;
    }
    if (node.type is TopomapNodeType) {
      return true;
    }
    if (node.type is PSDNodeType) {
      return true;
    }
    if (node.type is SegmentationNodeType || node.type is RealignNodeType) {
      return true;
    }
    if (node.type is SleepStagingNodeType) {
      return true;
    }
    return node.outputPorts.any((PortSpec port) {
      return port.type == PortType.signal;
    });
  }

  String visualizationViewForNode(NodeModel node) {
    return _fallbackVisualizationViewForNode(node);
  }

  String visualizationViewForNodeAndDatasets(
    NodeModel node,
    List<Dataset> datasets,
  ) {
    for (final Dataset dataset in datasets) {
      if (dataset.bridgeDetection != null) {
        return 'bridge';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.timeFrequency != null) {
        return 'time_frequency';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.spectrum != null) {
        return 'psd';
      }
    }
    for (final Dataset dataset in datasets) {
      final TimeSeriesData? timeSeries = dataset.timeSeries;
      if (timeSeries != null &&
          timeSeries.markers.any((TimeMarker marker) => isSleepStageMarker(marker))) {
        return 'hypnogram';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.segmentedTimeSeries != null) {
        return 'segments';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.timeSeries != null || dataset.segmentedTimeSeries != null) {
        return 'raw';
      }
    }
    return _fallbackVisualizationViewForNode(node);
  }

  String _fallbackVisualizationViewForNode(NodeModel node) {
    if (node.type is SleepStagingNodeType) {
      return 'hypnogram';
    }
    if (node.type is BridgeDetectorNodeType) {
      return 'bridge';
    }
    if (node.type is TopomapNodeType) {
      return 'topomap';
    }
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id);
      if (parents.any((NodeModel parent) => parent.type is SleepStagingNodeType)) {
        return 'hypnogram';
      }
      if (parents.any((NodeModel parent) => parent.type is BridgeDetectorNodeType)) {
        return 'bridge';
      }
      if (parents.any((NodeModel parent) => parent.type is PSDNodeType)) {
        return 'psd';
      }
      if (parents.any(
        (NodeModel parent) =>
            parent.type is SegmentationNodeType || parent.type is RealignNodeType,
      )) {
        return 'segments';
      }
      if (parents.any((NodeModel parent) => parent.type.title.contains('Time-Frequency'))) {
        return 'time_frequency';
      }
      return 'raw';
    }
    if (node.type is SegmentationNodeType || node.type is RealignNodeType) {
      return 'segments';
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
    final BrainStoryJob job = _createJob(label: label);
    _activeRunJobId = job.id;
    runActivity.value = RunActivity(
      label: label,
      detail: 'Preparing run state...',
      jobId: job.id,
    );
    _updateJob(
      job.id,
      status: BrainStoryJobStatus.running,
      detail: 'Preparing run state...',
      progress: 0.04,
    );
    await _yieldToUi();
    await setRunDetail('Settling the interface...');
    await _yieldToUi();
    await setRunDetail('Preparing data flow...');
    await _yieldToUi(extraDelayMs: 24);
  }

  void finishRunUi() {
    final String? jobId = _activeRunJobId ?? runActivity.value?.jobId;
    if (jobId != null && _cancelRequestedJobIds.contains(jobId)) {
      cancelRunUi();
      return;
    }
    if (jobId != null) {
      _updateJob(
        jobId,
        status: BrainStoryJobStatus.completed,
        detail: 'Complete',
        progress: 1.0,
        finishedAt: DateTime.now(),
        cancelRequested: false,
      );
    }
    if (jobId != null) {
      _cancelRequestedJobIds.remove(jobId);
    }
    _activeRunJobId = null;
    _activeRunNodeId = null;
    runActivity.value = null;
  }

  void failRunUi(Object error) {
    if (error is BrainStoryRunCanceled) {
      cancelRunUi(error.message);
      return;
    }
    final String? jobId = _activeRunJobId ?? runActivity.value?.jobId;
    if (jobId != null) {
      _updateJob(
        jobId,
        status: BrainStoryJobStatus.failed,
        detail: 'Failed',
        error: error.toString(),
        finishedAt: DateTime.now(),
        cancelRequested: false,
      );
      _cancelRequestedJobIds.remove(jobId);
    }
    _activeRunJobId = null;
    _activeRunNodeId = null;
    runActivity.value = null;
  }

  void cancelRunUi([String detail = 'Canceled']) {
    final String? jobId = _activeRunJobId ?? runActivity.value?.jobId;
    if (jobId != null) {
      _updateJob(
        jobId,
        status: BrainStoryJobStatus.canceled,
        detail: detail,
        finishedAt: DateTime.now(),
        cancelRequested: false,
      );
      _cancelRequestedJobIds.remove(jobId);
    }
    _activeRunJobId = null;
    _activeRunNodeId = null;
    runActivity.value = null;
  }

  void cancelActiveRun() {
    final String? jobId = _activeRunJobId ?? runActivity.value?.jobId;
    if (jobId == null) {
      return;
    }
    _cancelRequestedJobIds.add(jobId);
    if (_activeRunNodeId != null) {
      _setNodeProcessStatus(_activeRunNodeId!, NodeProcessStatus.canceling);
    }
    _updateJob(
      jobId,
      status: BrainStoryJobStatus.running,
      detail: 'A sub-process is finishing; cancellation will take effect next.',
      cancelRequested: true,
    );
    final RunActivity? current = runActivity.value;
    if (current != null) {
      runActivity.value = current.copyWith(
        detail: 'A sub-process is finishing; cancellation will take effect next.',
      );
    }
  }

  Future<void> setRunDetail(String detail) async {
    final RunActivity? current = runActivity.value;
    if (current == null) {
      return;
    }
    runActivity.value = current.copyWith(detail: detail);
    if (current.jobId != null) {
      _updateJob(current.jobId!, detail: detail);
    }
    await _yieldToUi();
  }

  BrainStoryJob _createJob({
    required String label,
    String? nodeId,
    Set<String> datasetIds = const <String>{},
  }) {
    final DateTime now = DateTime.now();
    final BrainStoryJob job = BrainStoryJob(
      id: _nextJobId(),
      label: label,
      detail: 'Queued',
      status: BrainStoryJobStatus.queued,
      progress: 0.0,
      createdAt: now,
      nodeId: nodeId,
      datasetIds: datasetIds,
      cancellable: true,
    );
    jobs.value = <BrainStoryJob>[job, ...jobs.value].take(12).toList(growable: false);
    return job;
  }

  String _nextJobId() {
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int nextMicros = nowMicros <= _lastGeneratedJobIdMicros
        ? _lastGeneratedJobIdMicros + 1
        : nowMicros;
    _lastGeneratedJobIdMicros = nextMicros;
    return 'job-$nextMicros';
  }

  void _updateJob(
    String jobId, {
    String? detail,
    BrainStoryJobStatus? status,
    double? progress,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
    bool? cancelRequested,
  }) {
    final List<BrainStoryJob> currentJobs = jobs.value;
    final int index = currentJobs.indexWhere((BrainStoryJob job) => job.id == jobId);
    if (index < 0) {
      return;
    }
    final BrainStoryJob current = currentJobs[index];
    final BrainStoryJob next = current.copyWith(
      detail: detail,
      status: status,
      progress: progress,
      startedAt: startedAt ??
          (status == BrainStoryJobStatus.running && current.startedAt == null
              ? DateTime.now()
              : null),
      finishedAt: finishedAt,
      error: error,
      cancelRequested: cancelRequested,
    );
    jobs.value = <BrainStoryJob>[
      for (int i = 0; i < currentJobs.length; i++)
        if (i == index) next else currentJobs[i],
    ];
  }

  void _updateActiveRunProgress(double progress) {
    final String? jobId = _activeRunJobId ?? runActivity.value?.jobId;
    if (jobId == null) {
      return;
    }
    _updateJob(jobId, progress: progress.clamp(0.04, 0.96).toDouble());
  }

  void _throwIfActiveRunCanceled() {
    final String? jobId = _activeRunJobId ?? runActivity.value?.jobId;
    if (jobId != null && _cancelRequestedJobIds.contains(jobId)) {
      if (_activeRunNodeId != null) {
        _setNodeProcessStatus(_activeRunNodeId!, NodeProcessStatus.canceled);
      }
      throw const BrainStoryRunCanceled();
    }
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
    _throwIfActiveRunCanceled();

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

    final int totalWorkUnits = math.max(
      1,
      targetDatasets.length * orderedNodes.length,
    );
    int completedWorkUnits = 0;
    _setNodeProcessStatuses(
      orderedNodes,
      NodeProcessStatus.waiting,
      clearExisting: true,
    );

    for (final Dataset dataset in targetDatasets) {
      _throwIfActiveRunCanceled();
      await setRunDetail('Preparing ${dataset.label}...');
      for (final NodeModel node in orderedNodes) {
        _throwIfActiveRunCanceled();
        if (!_datasetsForNode(node).contains(dataset.id)) {
          continue;
        }
        if (node.type is! ImportNodeType &&
            !_availableDatasetIdsForNode(node).contains(dataset.id)) {
          continue;
        }

        if (node.datasetStates[dataset.id] == DatasetState.done) {
          await setRunDetail('Skipping ${node.title} for ${dataset.label} (already done)...');
          await _restoreMaterializedOutputIfNeeded(node, dataset);
          _setNodeProcessStatus(node.id, NodeProcessStatus.done);
          completedWorkUnits++;
          _updateActiveRunProgress(completedWorkUnits / totalWorkUnits);
          continue;
        }

        node.datasetStates[dataset.id] = DatasetState.ready;
        try {
          _activeRunNodeId = node.id;
          _setNodeProcessStatus(node.id, NodeProcessStatus.running);
          dataset.ram.remove('artifact.lastChangeSet');
          await _restoreUpstreamInputForRun(node, dataset);
          final List<String> sourceArtifactIds =
              _sourceArtifactIdsForDataset(dataset);
          await setRunDetail('Running ${node.title} on ${dataset.label}...');
          _throwIfActiveRunCanceled();
          await _runNodeTypeOnDataset(
            node: node,
            dataset: dataset,
            sourceArtifactIds: sourceArtifactIds,
          );
          _throwIfActiveRunCanceled();
          _activeRunNodeId = null;
          node.datasetStates[dataset.id] = DatasetState.done;
          _setNodeProcessStatus(node.id, NodeProcessStatus.done);
          await _materializeNodeOutput(
            node,
            dataset,
            sourceArtifactIds: sourceArtifactIds,
          );
          _markImmediateChildrenStale(
            node.id,
            dataset.id,
            changeSet: _takeLastChangeSet(dataset),
          );
          completedWorkUnits++;
          _updateActiveRunProgress(completedWorkUnits / totalWorkUnits);
        } catch (_) {
          if (_cancelRequestedJobIds.contains(_activeRunJobId)) {
            _setNodeProcessStatus(node.id, NodeProcessStatus.canceled);
          } else {
            _setNodeProcessStatus(node.id, NodeProcessStatus.failed);
          }
          _activeRunNodeId = null;
          node.datasetStates[dataset.id] = _availableDatasetIdsForNode(node)
                  .contains(dataset.id)
              ? DatasetState.ready
              : DatasetState.notReady;
          rethrow;
        }
      }
    }
  }

  Future<void> _runNodeTypeOnDataset({
    required NodeModel node,
    required Dataset dataset,
    required List<String> sourceArtifactIds,
  }) async {
    if (!node.type.supportsBackgroundRun) {
      await node.type.run(dataset, node.params);
      return;
    }

    final String paramsFingerprint = jsonEncode(node.params);
    final Set<String> sourceArtifactIdSet = sourceArtifactIds.toSet();
    final Set<BrainStoryArtifactKind> inputKinds =
        _artifactKindsForNodeInputs(node, dataset);
    final DatasetArtifactSnapshot inputSnapshot =
        DatasetArtifactSnapshot.fromDataset(
      dataset,
      includedKinds: inputKinds,
    );

    await setRunDetail('Running ${node.title} on ${dataset.label} in the background...');
    final Map<String, dynamic> outputSnapshotJson =
        await runNodeSnapshotInBackground(
      nodeTitle: node.title,
      datasetId: dataset.id,
      datasetLabel: dataset.label,
      datasetPath: dataset.path,
      datasetLoaded: dataset.loaded,
      params: _deepCloneJsonMap(node.params),
      inputSnapshotJson: inputSnapshot.toJson(),
    );
    _throwIfActiveRunCanceled();

    if (jsonEncode(node.params) != paramsFingerprint) {
      throw StateError(
        '${node.title} parameters changed while it was running; discarded background result.',
      );
    }
    if (!_setEquals(_sourceArtifactIdsForDataset(dataset).toSet(), sourceArtifactIdSet)) {
      throw StateError(
        '${dataset.label} changed upstream while ${node.title} was running; discarded background result.',
      );
    }

    DatasetArtifactSnapshot.fromJson(outputSnapshotJson).applyToDataset(dataset);
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
            (NodeModel parent) => _nodeHasRunForDataset(parent, dataset.id),
          );
        })
        .map((Dataset dataset) => dataset.id)
        .toSet();
  }

  bool _nodeHasRunForDataset(NodeModel node, String datasetId) {
    final DatasetState state =
        node.datasetStates[datasetId] ?? DatasetState.notReady;
    return state == DatasetState.done || state == DatasetState.stale;
  }

  Map<String, DatasetState> _processedDatasetStatesForNode(NodeModel node) {
    return <String, DatasetState>{
      for (final Dataset dataset in datasets.values)
        dataset.id: _effectiveDatasetStateForNode(node, dataset.id),
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
        if (_nodeHasRunForDataset(parent, dataset.id)) {
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

  List<NodeModel> _immediateChildren(String nodeId) {
    final List<NodeModel> children = <NodeModel>[];
    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != nodeId) continue;
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child != null) {
        children.add(child);
      }
    }
    return children;
  }

  List<NodeModel> _orderedNodes(Set<String> nodeIds) {
    final Map<String, int> inDegree = <String, int>{
      for (final String id in nodeIds) id: 0,
    };
    final Map<String, List<String>> outgoingEdges = <String, List<String>>{
      for (final String id in nodeIds) id: <String>[],
    };

    for (final Map<String, dynamic> connection in connections) {
      final String fromNode = connection['fromNode'] as String;
      final String toNode = connection['toNode'] as String;
      if (nodeIds.contains(fromNode) && nodeIds.contains(toNode)) {
        inDegree[toNode] = (inDegree[toNode] ?? 0) + 1;
        outgoingEdges.putIfAbsent(fromNode, () => <String>[]).add(toNode);
      }
    }

    final List<String> queue = nodes
        .map((NodeModel node) => node.id)
        .where((String id) => nodeIds.contains(id) && inDegree[id] == 0)
        .toList();
    final List<String> orderedIds = <String>[];
    int queueIndex = 0;

    while (queueIndex < queue.length) {
      final String current = queue[queueIndex++];
      orderedIds.add(current);

      for (final String target in outgoingEdges[current] ?? const <String>[]) {
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

  void _refreshDatasetAvailability(String datasetId) {
    final List<NodeModel> orderedNodes =
        _orderedNodes(nodes.map((NodeModel node) => node.id).toSet());
    for (final NodeModel node in orderedNodes) {
      final bool selectedForNode = _datasetsForNode(node).contains(datasetId);
      if (!selectedForNode) {
        if ((node.datasetStates[datasetId] ?? DatasetState.notReady) !=
            DatasetState.done) {
          node.datasetStates[datasetId] = DatasetState.notReady;
        }
        continue;
      }

      final List<NodeModel> parents = _immediateParents(node.id);
      final bool structurallyReady =
          node.type is ImportNodeType ||
          parents.every((NodeModel parent) => _nodeHasRunForDataset(parent, datasetId));

      if (!structurallyReady) {
        if ((node.datasetStates[datasetId] ?? DatasetState.notReady) !=
            DatasetState.done) {
          node.datasetStates[datasetId] = DatasetState.notReady;
        }
        continue;
      }

      final DatasetState currentState =
          node.datasetStates[datasetId] ?? DatasetState.notReady;
      final bool hasMaterializedResult =
          _nodeRamSnapshots[node.id]?.containsKey(datasetId) == true ||
          _nodeDiskSnapshotIds[node.id]?.contains(datasetId) == true;
      if ((currentState == DatasetState.done ||
              currentState == DatasetState.stale) &&
          hasMaterializedResult) {
        continue;
      }

      node.datasetStates[datasetId] = DatasetState.ready;
    }
  }

  ArtifactChangeSet? _takeLastChangeSet(Dataset dataset) {
    final Object? rawValue = dataset.ram.remove('artifact.lastChangeSet');
    if (rawValue is ArtifactChangeSet) {
      return rawValue;
    }
    if (rawValue is Map) {
      return ArtifactChangeSet.fromJson(
        Map<String, dynamic>.from(rawValue),
      );
    }
    return null;
  }

  void _markImmediateChildrenStale(
    String nodeId,
    String datasetId, {
    ArtifactChangeSet? changeSet,
  }) {
    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != nodeId) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child == null) {
        continue;
      }
      if (child.datasetStates[datasetId] == DatasetState.done &&
          _nodeInvalidatedByChangeSet(child, changeSet)) {
        child.datasetStates[datasetId] = DatasetState.stale;
      }
    }
  }

  bool _nodeInvalidatedByChangeSet(
    NodeModel node,
    ArtifactChangeSet? changeSet,
  ) {
    if (changeSet == null) {
      return true;
    }
    if (changeSet.changeTypes.isEmpty) {
      return false;
    }

    final bool usesSignal = node.inputPorts.any(
      (PortSpec port) => port.type == PortType.signal,
    );
    final bool usesMarkers = node.inputPorts.any(
      (PortSpec port) => port.type == PortType.markers,
    );
    final bool usesMetadata = node.inputPorts.any(
      (PortSpec port) => port.type == PortType.metadata,
    );
    final bool signalChanged = changeSet.touchesSamples ||
        changeSet.touchesChannelLabels ||
        changeSet.touchesChannelTopology ||
        changeSet.touchesChannelCoordinates;
    final bool markerOrSegmentChanged =
        changeSet.touchesMarkers || changeSet.touchesSegmentWindows;

    if (changeSet.touchesParams) {
      return true;
    }
    if (signalChanged && usesSignal) {
      return true;
    }
    if (markerOrSegmentChanged && (usesMarkers || usesMetadata)) {
      return true;
    }
    if (!signalChanged && !markerOrSegmentChanged) {
      return true;
    }
    return false;
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

    _recordUndo(
      'save marker edits',
      datasetArtifactIds: <String>{dataset.id},
    );
    final NodeModel markerNode = _ensureMarkerNode(sourceNode);
    markerNode.params['markers'] = rawMarkers;

    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      final List<String> sourceArtifactIds = _sourceArtifactIdsForDataset(dataset);
      dataset.timeSeries = timeSeries.copyWith(
        markers: AddRemoveMarkersNodeType.markersForDataset(
          dataset.id,
          rawMarkers,
        ),
      );
      dataset.ram['artifact.lastChangeSet'] = ArtifactChangeSet(
        datasetId: dataset.id,
        sourceNodeId: markerNode.id,
        changeTypes: const <ArtifactChangeType>{
          ArtifactChangeType.markers,
        },
        description: 'Marker edits',
      );
      _cacheVisualizationEditOutput(
        markerNode,
        dataset,
        sourceArtifactIds: sourceArtifactIds,
      );
    }

    markerNode.datasetStates[dataset.id] = DatasetState.done;
    _markImmediateChildrenStale(
      markerNode.id,
      dataset.id,
      changeSet: _takeLastChangeSet(dataset),
    );
    selectedNodeId = markerNode.id;
    selectedNodeIds
      ..clear()
      ..add(markerNode.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  void applyChannelEditsFromVisualization({
    required String nodeId,
    required Dataset dataset,
    required Map<String, dynamic> datasetConfig,
  }) {
    final NodeModel? sourceNode = _channelEditSourceNode(nodeId);
    if (sourceNode == null) {
      return;
    }

    _recordUndo(
      'save channel edits',
      datasetArtifactIds: <String>{dataset.id},
    );
    final NodeModel channelNode = _ensureChannelEditNode(sourceNode);
    EditChannelsNodeType.setConfigForDataset(
      channelNode.params,
      dataset.id,
      datasetConfig,
    );

    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      final List<String> sourceArtifactIds = _sourceArtifactIdsForDataset(dataset);
      final ArtifactChangeSet changeSet =
          EditChannelsNodeType.changeSetForConfig(
        datasetId: dataset.id,
        timeSeries: timeSeries,
        config: datasetConfig,
        sourceNodeId: channelNode.id,
      );
      dataset.timeSeries = EditChannelsNodeType.applyChannelEdits(
        timeSeries,
        datasetConfig,
        warningSink: (String warning) {
          dataset.ram['editChannels.lastWarning'] = warning;
        },
      );
      dataset.ram['artifact.lastChangeSet'] = changeSet;
      _cacheVisualizationEditOutput(
        channelNode,
        dataset,
        sourceArtifactIds: sourceArtifactIds,
      );
    }

    channelNode.datasetStates[dataset.id] = DatasetState.done;
    _markImmediateChildrenStale(
      channelNode.id,
      dataset.id,
      changeSet: _takeLastChangeSet(dataset),
    );
    selectedNodeId = channelNode.id;
    selectedNodeIds
      ..clear()
      ..add(channelNode.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  String applyInteractiveArtifactDetectionFromVisualization({
    required String nodeId,
    required Dataset dataset,
  }) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return 'Interactive save failed because the source node is no longer available.';
    }
    final NodeModel? sourceNode = _interactiveArtifactSourceNode(nodeId);
    final NodeModel? targetNode;
    final bool createdNode;
    if (sourceNode != null) {
      targetNode = sourceNode;
      createdNode = false;
    } else if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id)
          .where((NodeModel parent) => parent.outputPorts.isNotEmpty)
          .toList(growable: false);
      if (parents.isEmpty) {
        return 'Interactive save failed because there is no upstream dataset to attach the node to.';
      }
      final NodeModel parent = parents.first;
      final bool hadInteractiveChild = _immediateChildren(parent.id)
          .any((NodeModel child) => child.type is InteractiveArtifactDetectionNodeType);
      targetNode = _ensureInteractiveArtifactNode(parent);
      createdNode = !hadInteractiveChild;
      _copyInteractiveArtifactViewerParams(
        fromParams: node.params,
        toParams: targetNode.params,
      );
    } else {
      final bool hadInteractiveChild = _immediateChildren(node.id)
          .any((NodeModel child) => child.type is InteractiveArtifactDetectionNodeType);
      targetNode = _ensureInteractiveArtifactNode(node);
      createdNode = !hadInteractiveChild;
      _copyInteractiveArtifactViewerParams(
        fromParams: node.params,
        toParams: targetNode.params,
      );
    }

    _recordUndo(
      'save artifact edits',
      datasetArtifactIds: <String>{dataset.id},
    );
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      final List<String> sourceArtifactIds = _sourceArtifactIdsForDataset(dataset);
      dataset.timeSeries = timeSeries.copyWith(
        markers: InteractiveArtifactDetectionNodeType.acceptedMarkersForDataset(
          dataset.id,
          targetNode.params,
          baseMarkers: timeSeries.markers,
        ),
      );
      _cacheVisualizationEditOutput(
        targetNode,
        dataset,
        sourceArtifactIds: sourceArtifactIds,
      );
    }

    targetNode.datasetStates[dataset.id] = DatasetState.done;
    _markImmediateChildrenStale(targetNode.id, dataset.id);
    selectedNodeId = targetNode.id;
    selectedNodeIds
      ..clear()
      ..add(targetNode.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();
    final int exemplarCount = InteractiveArtifactDetectionNodeType.exemplarsForDataset(
      dataset.id,
      targetNode.params,
    ).length;
    final int pendingCount = InteractiveArtifactDetectionNodeType.candidatesForDataset(
      dataset.id,
      targetNode.params,
      statuses: const <String>{
        InteractiveArtifactDetectionNodeType.pendingStatus,
      },
    ).length;
    final int acceptedCount = InteractiveArtifactDetectionNodeType.candidatesForDataset(
      dataset.id,
      targetNode.params,
      statuses: const <String>{
        InteractiveArtifactDetectionNodeType.acceptedStatus,
      },
    ).length;
    final String action = createdNode ? 'Added' : 'Updated';
    return '$action Interactive Artifact Detection for ${dataset.label}: '
        '$exemplarCount exemplar${exemplarCount == 1 ? '' : 's'}, '
        '$pendingCount pending candidate${pendingCount == 1 ? '' : 's'}, '
        '$acceptedCount accepted.';
  }

  void _cacheVisualizationEditOutput(
    NodeModel node,
    Dataset dataset, {
    List<String> sourceArtifactIds = const <String>[],
  }) {
    _stampArtifactIdentities(
      node: node,
      dataset: dataset,
      sourceArtifactIds: sourceArtifactIds,
    );
    final Set<BrainStoryArtifactKind> outputKinds =
        _artifactKindsForNodeOutputs(node, dataset);
    final DatasetArtifactSnapshot snapshot =
        DatasetArtifactSnapshot.fromDataset(
      dataset,
      includedKinds: outputKinds,
    );
    if (snapshot.isEmpty) {
      _nodeRamSnapshots[node.id]?.remove(dataset.id);
      return;
    }
    _nodeRamSnapshots
        .putIfAbsent(node.id, () => <String, DatasetArtifactSnapshot>{})[dataset.id] =
        snapshot;
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
      hasLoadableDiskCache:
          (Map<String, dynamic> params, Set<String> datasetIds) =>
              _nodeHasLoadableDiskCache(node: node, datasetIds: datasetIds),
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
              _clearNodeResults(
        node: node,
        params: params,
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

  Future<void> _materializeNodeOutput(
    NodeModel node,
    Dataset dataset, {
    List<String> sourceArtifactIds = const <String>[],
  }) async {
    await setRunDetail('Materializing ${node.title} for ${dataset.label}...');
    _stampArtifactIdentities(
      node: node,
      dataset: dataset,
      sourceArtifactIds: sourceArtifactIds,
    );
    final Set<BrainStoryArtifactKind> outputKinds =
        _artifactKindsForNodeOutputs(node, dataset);
    final DatasetArtifactSnapshot snapshot =
        DatasetArtifactSnapshot.fromDataset(
      dataset,
      includedKinds: outputKinds,
    );
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
      _nodeDiskSnapshotIds
          .putIfAbsent(node.id, () => <String>{})
          .add(dataset.id);
      if (policy == NodeStoragePolicy.preferDisk) {
        _nodeRamSnapshots[node.id]?.remove(dataset.id);
      }
    }
  }

  List<String> _sourceArtifactIdsForDataset(Dataset dataset) {
    return dataset.artifactIdentities.values
        .map((ArtifactIdentity identity) => identity.artifactId)
        .where((String id) => id.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  void _stampArtifactIdentities({
    required NodeModel node,
    required Dataset dataset,
    List<String> sourceArtifactIds = const <String>[],
  }) {
    for (final BrainStoryArtifactKind kind in _artifactKindsForNodeOutputs(
      node,
      dataset,
    )) {
      final String artifactId = _artifactIdForNodeDatasetKind(
        node: node,
        dataset: dataset,
        kind: kind,
      );
      final ArtifactIdentity? previous = dataset.artifactIdentityFor(kind);
      dataset.setArtifactIdentity(
        ArtifactIdentity(
          artifactId: artifactId,
          datasetId: dataset.id,
          kind: kind,
          producerNodeId: node.id,
          sourceArtifactIds: sourceArtifactIds,
          revision: previous?.artifactId == artifactId
              ? previous!.revision + 1
              : 0,
        ),
      );
    }
  }

  String _artifactIdForNodeDatasetKind({
    required NodeModel node,
    required Dataset dataset,
    required BrainStoryArtifactKind kind,
  }) {
    return '${node.id}:${dataset.id}:${kind.name}';
  }

  Set<BrainStoryArtifactKind> _artifactKindsForNodeOutputs(
    NodeModel node,
    Dataset dataset,
  ) {
    final Set<BrainStoryArtifactKind> kinds = <BrainStoryArtifactKind>{};
    for (final PortSpec output in node.outputPorts) {
      final String outputName = output.name.toLowerCase();
      switch (output.type) {
        case PortType.signal:
          if ((outputName.contains('psd') ||
                  outputName.contains('spectrum')) &&
              dataset.spectrum != null) {
            kinds.add(BrainStoryArtifactKind.spectrum);
          } else if (dataset.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.timeSeries);
          }
          break;
        case PortType.markers:
          if (dataset.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.markers);
          }
          break;
        case PortType.metadata:
          if (outputName.contains('segment') &&
              dataset.segmentedTimeSeries != null) {
            kinds.add(BrainStoryArtifactKind.segmentedTimeSeries);
          } else if (dataset.fooofResult != null) {
            kinds.add(BrainStoryArtifactKind.fooofResult);
          } else if (dataset.featureTable != null) {
            kinds.add(BrainStoryArtifactKind.featureTable);
          } else if (dataset.bridgeDetection != null) {
            kinds.add(BrainStoryArtifactKind.bridgeDetection);
          } else if (dataset.timeFrequency != null) {
            kinds.add(BrainStoryArtifactKind.timeFrequency);
          }
          break;
        case PortType.matrixTransformation:
          if (dataset.matrixTransformation != null) {
            kinds.add(BrainStoryArtifactKind.matrixTransformation);
          }
          break;
      }
    }
    return kinds;
  }

  Set<BrainStoryArtifactKind> _artifactKindsForNodeInputs(
    NodeModel node,
    Dataset dataset,
  ) {
    final Set<BrainStoryArtifactKind> kinds = <BrainStoryArtifactKind>{};
    for (final PortSpec input in node.inputPorts) {
      final String inputName = input.name.toLowerCase();
      switch (input.type) {
        case PortType.signal:
          if ((inputName.contains('psd') || inputName.contains('spectrum')) &&
              dataset.spectrum != null) {
            kinds.add(BrainStoryArtifactKind.spectrum);
          } else if (dataset.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.timeSeries);
          }
          break;
        case PortType.markers:
          if (dataset.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.markers);
          }
          break;
        case PortType.metadata:
          if (inputName.contains('segment') &&
              dataset.segmentedTimeSeries != null) {
            kinds.add(BrainStoryArtifactKind.segmentedTimeSeries);
          } else if (dataset.fooofResult != null) {
            kinds.add(BrainStoryArtifactKind.fooofResult);
          } else if (dataset.featureTable != null) {
            kinds.add(BrainStoryArtifactKind.featureTable);
          } else if (dataset.bridgeDetection != null) {
            kinds.add(BrainStoryArtifactKind.bridgeDetection);
          } else if (dataset.timeFrequency != null) {
            kinds.add(BrainStoryArtifactKind.timeFrequency);
          }
          break;
        case PortType.matrixTransformation:
          if (dataset.matrixTransformation != null) {
            kinds.add(BrainStoryArtifactKind.matrixTransformation);
          }
          break;
      }
    }
    return kinds;
  }

  Set<BrainStoryArtifactKind> _artifactKindsForSnapshotOutputs(
    NodeModel node,
    DatasetArtifactSnapshot snapshot,
  ) {
    final Set<BrainStoryArtifactKind> kinds = <BrainStoryArtifactKind>{};
    for (final PortSpec output in node.outputPorts) {
      final String outputName = output.name.toLowerCase();
      switch (output.type) {
        case PortType.signal:
          if ((outputName.contains('psd') ||
                  outputName.contains('spectrum')) &&
              snapshot.spectrum != null) {
            kinds.add(BrainStoryArtifactKind.spectrum);
          } else if (snapshot.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.timeSeries);
          }
          break;
        case PortType.markers:
          if (snapshot.markers != null || snapshot.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.markers);
          }
          break;
        case PortType.metadata:
          if (outputName.contains('segment') &&
              snapshot.segmentedTimeSeries != null) {
            kinds.add(BrainStoryArtifactKind.segmentedTimeSeries);
          } else if (snapshot.fooofResult != null) {
            kinds.add(BrainStoryArtifactKind.fooofResult);
          } else if (snapshot.featureTable != null) {
            kinds.add(BrainStoryArtifactKind.featureTable);
          } else if (snapshot.bridgeDetection != null) {
            kinds.add(BrainStoryArtifactKind.bridgeDetection);
          } else if (snapshot.timeFrequency != null) {
            kinds.add(BrainStoryArtifactKind.timeFrequency);
          }
          break;
        case PortType.matrixTransformation:
          if (snapshot.matrixTransformation != null) {
            kinds.add(BrainStoryArtifactKind.matrixTransformation);
          }
          break;
      }
    }
    return kinds;
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
      if (diskSavedDatasetIds.isEmpty) {
        _nodeDiskSnapshotIds.remove(node.id);
      } else {
        _nodeDiskSnapshotIds[node.id] = diskSavedDatasetIds;
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
    } catch (error) {
      failRunUi(error);
      rethrow;
    } finally {
      if (runActivity.value != null) {
        finishRunUi();
      }
    }
  }

  Future<bool> _nodeHasLoadableDiskCache({
    required NodeModel node,
    required Set<String> datasetIds,
  }) async {
    if (!supportsNodeSnapshotDiskStore || datasetIds.isEmpty) {
      return false;
    }
    for (final Dataset dataset in _datasetsForAction(datasetIds)) {
      final bool inRam = _nodeRamSnapshots[node.id]?.containsKey(dataset.id) == true;
      if (inRam) {
        continue;
      }
      final bool onDisk = await hasNodeSnapshotOnDisk(
        nodeId: node.id,
        datasetId: dataset.id,
      );
      if (onDisk) {
        _nodeDiskSnapshotIds.putIfAbsent(node.id, () => <String>{}).add(dataset.id);
        return true;
      }
    }
    return false;
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
      _nodeDiskSnapshotIds
          .putIfAbsent(node.id, () => <String>{})
          .add(dataset.id);
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
      _nodeDiskSnapshotIds
          .putIfAbsent(node.id, () => <String>{})
          .add(dataset.id);
      snapshot.applyToDataset(dataset);
      node.datasetStates[dataset.id] = DatasetState.done;
      _markImmediateChildrenStale(node.id, dataset.id);
      loadedCount++;
    }

    if (loadedCount == 0) {
      return 'No disk cache found yet for ${node.title}.';
    }

    update();
    return 'Loaded $loadedCount cached output(s) into RAM for ${node.title}.';
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
      _nodeDiskSnapshotIds[node.id]?.remove(dataset.id);
      if (_nodeDiskSnapshotIds[node.id]?.isEmpty ?? false) {
        _nodeDiskSnapshotIds.remove(node.id);
      }
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
      if (_clearNodeParamsForDataset(node, dataset.id)) {
        changed = true;
      }
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
          _nodeDiskSnapshotIds[node.id]?.remove(dataset.id);
          if (_nodeDiskSnapshotIds[node.id]?.isEmpty ?? false) {
            _nodeDiskSnapshotIds.remove(node.id);
          }
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
      if (changed) {
        clearedCount++;
      }
    }

    update();
    return clearedCount == 0
        ? 'There were no results to clear for ${node.title}.'
        : 'Cleared $clearedCount result set(s) for ${node.title}.';
  }

  bool _clearNodeParamsForDataset(NodeModel node, String datasetId) {
    if (node.type is! InteractiveArtifactDetectionNodeType) {
      return false;
    }
    bool changed = false;
    for (final String key in const <String>[
      'artifactExemplars',
      'artifactCandidates',
      'artifactTemplates',
    ]) {
      final List<dynamic> current =
          node.params[key] as List<dynamic>? ?? const <dynamic>[];
      final List<Map<String, dynamic>> filtered = current
          .whereType<Map<String, dynamic>>()
          .where((Map<String, dynamic> item) => item['datasetId'] != datasetId)
          .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (filtered.length != current.length) {
        node.params[key] = filtered;
        changed = true;
      }
    }
    return changed;
  }

  Future<String> clearNodeResultsForTesting(
    String nodeId, {
    required Set<String> datasetIds,
  }) async {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return 'Node not found.';
    }
    return _clearNodeResults(
      node: node,
      params: node.params,
      datasetIds: datasetIds,
      update: () {},
    );
  }

  Future<void> _restoreMaterializedOutputIfNeeded(
    NodeModel node,
    Dataset dataset,
  ) async {
    final Dataset view = await materializedDatasetViewForNode(node.id, dataset);
    _replaceDatasetRam(dataset, view);
  }

  Future<bool> promptLoadFromDiskInsteadOfRun({
    required BuildContext context,
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final bool hasLoadableCache = await _nodeHasLoadableDiskCache(
      node: node,
      datasetIds: datasetIds,
    );
    if (!hasLoadableCache || !context.mounted) {
      return false;
    }
    final bool? loadInstead = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Load from disk instead?'),
          content: Text(
            'BrainStory found cached output for ${node.title} on disk. Loading it is likely faster than recomputing it.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Run anyway'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Load from disk'),
            ),
          ],
        );
      },
    );
    if (loadInstead != true) {
      return false;
    }
    final String message = await _loadNodeSnapshotsToRam(
      node: node,
      datasetIds: datasetIds,
      update: update,
    );
    if (context.mounted) {
      _showStatusSnackBar(context, message);
    }
    return true;
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

    final Set<String> upstreamIds = _collectAncestorsInclusive(node.id)
      ..remove(node.id);
    final Dataset view = _datasetShell(dataset);
    bool appliedAnySnapshot = false;
    for (final NodeModel upstreamNode in _orderedNodes(upstreamIds)) {
      if (upstreamNode.datasetStates[dataset.id] != DatasetState.done) {
        continue;
      }
      final DatasetArtifactSnapshot? snapshot =
          await _loadSnapshotForNodeDataset(
        upstreamNode.id,
        dataset.id,
        cacheInRam: _shouldCacheLoadedSnapshotInRam(upstreamNode),
      );
      if (snapshot != null && !snapshot.isEmpty) {
        _snapshotScopedToNodeOutputs(upstreamNode, snapshot).applyToDataset(view);
        appliedAnySnapshot = true;
        continue;
      }
      if (upstreamNode.type is ImportNodeType && !appliedAnySnapshot) {
        _applyLiveSourceArtifacts(view, dataset);
      }
    }
    if (appliedAnySnapshot || view.timeSeries != null) {
      _replaceDatasetRam(dataset, view);
    }
  }

  void _replaceDatasetRam(Dataset target, Dataset source) {
    target.ram
      ..clear()
      ..addAll(source.ram);
  }

  DatasetArtifactSnapshot _snapshotScopedToNodeOutputs(
    NodeModel node,
    DatasetArtifactSnapshot snapshot,
  ) {
    if (snapshot.includedKinds != null) {
      return snapshot;
    }
    final Set<BrainStoryArtifactKind> kinds =
        _artifactKindsForSnapshotOutputs(node, snapshot);
    if (kinds.isEmpty) {
      return snapshot;
    }
    return DatasetArtifactSnapshot(
      timeSeries: kinds.contains(BrainStoryArtifactKind.timeSeries)
          ? snapshot.timeSeries
          : null,
      segmentedTimeSeries:
          kinds.contains(BrainStoryArtifactKind.segmentedTimeSeries)
              ? snapshot.segmentedTimeSeries
              : null,
      spectrum: kinds.contains(BrainStoryArtifactKind.spectrum)
          ? snapshot.spectrum
          : null,
      fooofResult: kinds.contains(BrainStoryArtifactKind.fooofResult)
          ? snapshot.fooofResult
          : null,
      featureTable: kinds.contains(BrainStoryArtifactKind.featureTable)
          ? snapshot.featureTable
          : null,
      bridgeDetection: kinds.contains(BrainStoryArtifactKind.bridgeDetection)
          ? snapshot.bridgeDetection
          : null,
      timeFrequency: kinds.contains(BrainStoryArtifactKind.timeFrequency)
          ? snapshot.timeFrequency
          : null,
      matrixTransformation:
          kinds.contains(BrainStoryArtifactKind.matrixTransformation)
              ? snapshot.matrixTransformation
              : null,
      markers: kinds.contains(BrainStoryArtifactKind.markers)
          ? snapshot.markers ??
              snapshot.timeSeries?.markers
                  .map((TimeMarker marker) => TimeMarker.fromJson(marker.toJson()))
                  .toList(growable: false)
          : null,
      artifactIdentities:
          Map<BrainStoryArtifactKind, ArtifactIdentity>.fromEntries(
        snapshot.artifactIdentities.entries.where(
          (MapEntry<BrainStoryArtifactKind, ArtifactIdentity> entry) =>
              kinds.contains(entry.key),
        ),
      ),
      includedKinds: kinds,
    );
  }

  Future<DatasetArtifactSnapshot?> _loadSnapshotForNodeDataset(
    String nodeId,
    String datasetId,
    {bool cacheInRam = true}
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
    _nodeDiskSnapshotIds.putIfAbsent(nodeId, () => <String>{}).add(datasetId);
    if (cacheInRam) {
      _nodeRamSnapshots.putIfAbsent(
        nodeId,
        () => <String, DatasetArtifactSnapshot>{},
      )[datasetId] = snapshot;
    }
    return snapshot;
  }

  bool _shouldCacheLoadedSnapshotInRam(NodeModel node) {
    final NodeStoragePolicy policy = _storagePolicyForNode(node);
    switch (policy) {
      case NodeStoragePolicy.preferDisk:
      case NodeStoragePolicy.onDemand:
        return false;
      case NodeStoragePolicy.automatic:
      case NodeStoragePolicy.preferRam:
      case NodeStoragePolicy.ramAndDisk:
        return true;
    }
  }

  Future<void> _refreshDiskSnapshotFlagsForLoadedProject() async {
    _nodeRamSnapshots.clear();
    _nodeDiskSnapshotIds.clear();
    if (!supportsNodeSnapshotDiskStore) {
      return;
    }
    for (final NodeModel node in nodes) {
      for (final Dataset dataset in datasets.values) {
        final bool exists = await hasNodeSnapshotOnDisk(
          nodeId: node.id,
          datasetId: dataset.id,
        );
        if (exists) {
          _nodeDiskSnapshotIds.putIfAbsent(node.id, () => <String>{}).add(dataset.id);
        }
      }
    }
  }

  void _normalizeNodeStatesAfterProjectLoad() {
    for (final NodeModel node in nodes) {
      for (final Dataset dataset in datasets.values) {
        final DatasetState rawState =
            node.datasetStates[dataset.id] ?? DatasetState.notReady;
        if (rawState == DatasetState.notReady) {
          node.datasetStates[dataset.id] = DatasetState.notReady;
          continue;
        }
        node.datasetStates[dataset.id] = DatasetState.ready;
      }
    }
  }

  DatasetState _effectiveDatasetStateForNode(
    NodeModel node,
    String datasetId,
  ) {
    final DatasetState rawState =
        node.datasetStates[datasetId] ?? DatasetState.notReady;
    if (rawState != DatasetState.stale) {
      return rawState;
    }

    final bool hasResult =
        _nodeRamSnapshots[node.id]?.containsKey(datasetId) == true ||
        _nodeDiskSnapshotIds[node.id]?.contains(datasetId) == true;
    if (hasResult) {
      return DatasetState.stale;
    }

    return _availableDatasetIdsForNode(node).contains(datasetId)
        ? DatasetState.ready
        : DatasetState.notReady;
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
      markerChange: node.markerChange,
    )..datasetStates.addAll(node.datasetStates);
  }

  List<Dataset> _datasetsForAction(Set<String> datasetIds) {
    return datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList(growable: false);
  }

  Future<String> _runMemorySummaryAction(
    Iterable<MemoryArtifactSummary> rows,
    Future<String> Function(NodeModel node, Set<String> datasetIds) action,
  ) async {
    final Map<String, Set<String>> datasetIdsByNodeId = <String, Set<String>>{};
    for (final MemoryArtifactSummary row in rows) {
      datasetIdsByNodeId.putIfAbsent(row.nodeId, () => <String>{}).add(row.datasetId);
    }
    if (datasetIdsByNodeId.isEmpty) {
      return 'No memory rows were selected.';
    }

    final List<String> messages = <String>[];
    for (final MapEntry<String, Set<String>> entry in datasetIdsByNodeId.entries) {
      final NodeModel? node = _findNode(entry.key);
      if (node == null) {
        continue;
      }
      messages.add(await action(node, entry.value));
    }
    return messages.join(' ');
  }

  String _memoryArtifactLabel({
    required NodeModel node,
    required Dataset dataset,
    required DatasetArtifactSnapshot? snapshot,
  }) {
    final Set<BrainStoryArtifactKind> kinds = snapshot == null
        ? _artifactKindsForNodeOutputs(node, dataset)
        : _artifactKindsForSnapshotOutputs(node, snapshot);
    if (kinds.isEmpty) {
      return node.outputPorts.map((PortSpec port) => port.name).join(', ');
    }
    return kinds.map(_artifactKindLabel).join(', ');
  }

  String _memoryPrecisionLabel({
    required NodeModel node,
    required Dataset dataset,
    required DatasetArtifactSnapshot? snapshot,
  }) {
    final Set<BrainStoryArtifactKind> kinds = snapshot == null
        ? _artifactKindsForNodeOutputs(node, dataset)
        : _artifactKindsForSnapshotOutputs(node, snapshot);
    final bool hasNumeric = kinds.any(_isNumericArtifactKind);
    final bool hasMarkers = kinds.contains(BrainStoryArtifactKind.markers);
    final bool hasTable = kinds.contains(BrainStoryArtifactKind.featureTable);
    if (hasNumeric && (hasMarkers || hasTable)) {
      return '$kBrainStoryNumericPrecisionLabel + metadata';
    }
    if (hasNumeric) {
      return kBrainStoryNumericPrecisionLabel;
    }
    if (hasTable) {
      return 'Text table';
    }
    if (hasMarkers) {
      return 'Marker metadata';
    }
    return 'Pending';
  }

  bool _isNumericArtifactKind(BrainStoryArtifactKind kind) {
    switch (kind) {
      case BrainStoryArtifactKind.timeSeries:
      case BrainStoryArtifactKind.segmentedTimeSeries:
      case BrainStoryArtifactKind.spectrum:
      case BrainStoryArtifactKind.fooofResult:
      case BrainStoryArtifactKind.bridgeDetection:
      case BrainStoryArtifactKind.timeFrequency:
      case BrainStoryArtifactKind.matrixTransformation:
        return true;
      case BrainStoryArtifactKind.featureTable:
      case BrainStoryArtifactKind.markers:
      case BrainStoryArtifactKind.channelCoordinates:
      case BrainStoryArtifactKind.markerChange:
      case BrainStoryArtifactKind.unknown:
        return false;
    }
  }

  String _artifactKindLabel(BrainStoryArtifactKind kind) {
    switch (kind) {
      case BrainStoryArtifactKind.timeSeries:
        return 'Signal';
      case BrainStoryArtifactKind.segmentedTimeSeries:
        return 'Segments';
      case BrainStoryArtifactKind.spectrum:
        return 'Spectrum';
      case BrainStoryArtifactKind.fooofResult:
        return 'FOOOF';
      case BrainStoryArtifactKind.featureTable:
        return 'Table';
      case BrainStoryArtifactKind.bridgeDetection:
        return 'Bridge matrix';
      case BrainStoryArtifactKind.timeFrequency:
        return 'Time-frequency';
      case BrainStoryArtifactKind.matrixTransformation:
        return 'Matrix';
      case BrainStoryArtifactKind.markers:
        return 'Markers';
      case BrainStoryArtifactKind.channelCoordinates:
        return 'Coordinates';
      case BrainStoryArtifactKind.markerChange:
        return 'Marker changes';
      case BrainStoryArtifactKind.unknown:
        return 'Unknown';
    }
  }

  int _estimateSnapshotNumericBytes(DatasetArtifactSnapshot snapshot) {
    return (snapshot.timeSeries?.estimatedNumericBytes ?? 0) +
        (snapshot.segmentedTimeSeries?.estimatedNumericBytes ?? 0) +
        (snapshot.spectrum?.estimatedNumericBytes ?? 0) +
        (snapshot.fooofResult?.estimatedNumericBytes ?? 0) +
        (snapshot.bridgeDetection?.estimatedNumericBytes ?? 0) +
        (snapshot.timeFrequency?.estimatedNumericBytes ?? 0) +
        (snapshot.matrixTransformation?.estimatedNumericBytes ?? 0);
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

  NodeProcessViewData _processViewForNode(NodeModel node) {
    final NodeProcessIndicator? indicator = nodeProcessIndicators.value[node.id];
    if (indicator != null) {
      return NodeProcessViewData(
        label: indicator.label,
        color: indicator.color,
        active: indicator.active,
      );
    }
    final DatasetState state = node.visualState;
    return NodeProcessViewData(
      label: _nodeStateLabel(state),
      color: _nodeStateColor(state),
    );
  }

  String _nodeStateLabel(DatasetState state) {
    switch (state) {
      case DatasetState.notReady:
        return 'Not ready';
      case DatasetState.ready:
        return 'Ready';
      case DatasetState.done:
        return 'Done';
      case DatasetState.stale:
        return 'Stale';
    }
  }

  Color _nodeStateColor(DatasetState state) {
    switch (state) {
      case DatasetState.notReady:
        return const Color(0xFF9AA2AE);
      case DatasetState.ready:
        return const Color(0xFF66D9FF);
      case DatasetState.done:
        return const Color(0xFF62E391);
      case DatasetState.stale:
        return const Color(0xFFFFC857);
    }
  }

  void _setNodeProcessStatus(String nodeId, NodeProcessStatus status) {
    if (_findNode(nodeId) == null) {
      return;
    }
    nodeProcessIndicators.value = <String, NodeProcessIndicator>{
      ...nodeProcessIndicators.value,
      nodeId: NodeProcessIndicator(
        status: status,
      ),
    };
  }

  void _setNodeProcessStatuses(
    List<NodeModel> targetNodes,
    NodeProcessStatus status, {
    bool clearExisting = false,
  }) {
    final Map<String, NodeProcessIndicator> next =
        clearExisting
            ? <String, NodeProcessIndicator>{}
            : Map<String, NodeProcessIndicator>.from(
                nodeProcessIndicators.value,
              );
    for (final NodeModel node in targetNodes) {
      next[node.id] = NodeProcessIndicator(
        status: status,
      );
    }
    nodeProcessIndicators.value = next;
  }

  Color _nodeColor(NodeModel node) {
    return node.type.category.color;
  }

  bool _isHighlighted(NodeModel node) {
    return node.id == selectedNodeId ||
        selectedNodeIds.contains(node.id) ||
        node.id == keyboardFocusedNodeId;
  }

  Color _nodeHighlightColor(NodeModel node) {
    if (selectedNodeIds.length > 1 && selectedNodeIds.contains(node.id)) {
      return const Color(0xFF6DD3FF);
    }
    if (node.id == keyboardFocusedNodeId &&
        node.id != selectedNodeId &&
        !selectedNodeIds.contains(node.id)) {
      return const Color(0xFF24D6A7);
    }
    return const Color(0xFF958A52);
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

  NodeModel? _interactiveArtifactSourceNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return null;
    }
    if (node.type is InteractiveArtifactDetectionNodeType) {
      return node;
    }
    if (node.type is VisualizationNodeType) {
      for (final NodeModel parent in _immediateParents(node.id)) {
        if (parent.type is InteractiveArtifactDetectionNodeType) {
          return parent;
        }
      }
    }
    return null;
  }

  void _copyInteractiveArtifactViewerParams({
    required Map<String, dynamic> fromParams,
    required Map<String, dynamic> toParams,
  }) {
    toParams['interactiveArtifactDetection'] = true;
    toParams['interaction_mode'] = 'interactive';
    if (fromParams['artifactThreshold'] != null) {
      toParams['artifactThreshold'] = fromParams['artifactThreshold'];
    }
    if (fromParams['artifactExemplars'] is List) {
      toParams['artifactExemplars'] = List<dynamic>.from(
        fromParams['artifactExemplars'] as List<dynamic>,
      );
    }
    if (fromParams['artifactCandidates'] is List) {
      toParams['artifactCandidates'] = List<dynamic>.from(
        fromParams['artifactCandidates'] as List<dynamic>,
      );
    }
    if (fromParams['artifactTemplates'] is List) {
      toParams['artifactTemplates'] = List<dynamic>.from(
        fromParams['artifactTemplates'] as List<dynamic>,
      );
    }
  }

  NodeModel? _channelEditSourceNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return null;
    }
    if (node.type is EditChannelsNodeType) {
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

    int? fromPortIndex;
    int? toPortIndex;
    for (int candidateFromPort = 0;
        candidateFromPort < sourceNode.outputPorts.length;
        candidateFromPort++) {
      final int? candidateToPort =
          _matchingInputPortForOutputPort(sourceNode, candidateFromPort, markerNode);
      if (candidateToPort != null) {
        fromPortIndex = candidateFromPort;
        toPortIndex = candidateToPort;
        break;
      }
    }
    if (fromPortIndex != null && toPortIndex != null) {
      connections.add(<String, dynamic>{
        'fromNode': sourceNode.id,
        'fromPort': fromPortIndex,
        'toNode': markerNode.id,
        'toPort': toPortIndex,
      });
    }

    return markerNode;
  }

  NodeModel _ensureChannelEditNode(NodeModel sourceNode) {
    if (sourceNode.type is EditChannelsNodeType) {
      return sourceNode;
    }

    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != sourceNode.id) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child?.type is EditChannelsNodeType) {
        return child!;
      }
    }

    final NodeType channelType = EditChannelsNodeType();
    final NodeModel channelNode = _buildNode(
      type: channelType,
      position: _nearestAvailablePosition(
        Offset(
          sourceNode.position.dx,
          sourceNode.position.dy + _cardHeight + _spawnGap,
        ),
      ),
      params: <String, dynamic>{
        ...channelType.defaultParams,
        if (sourceNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            sourceNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(channelNode);

    int? fromPortIndex;
    int? toPortIndex;
    for (int candidateFromPort = 0;
        candidateFromPort < sourceNode.outputPorts.length;
        candidateFromPort++) {
      final int? candidateToPort = _matchingInputPortForOutputPort(
        sourceNode,
        candidateFromPort,
        channelNode,
      );
      if (candidateToPort != null) {
        fromPortIndex = candidateFromPort;
        toPortIndex = candidateToPort;
        break;
      }
    }
    if (fromPortIndex != null && toPortIndex != null) {
      connections.add(<String, dynamic>{
        'fromNode': sourceNode.id,
        'fromPort': fromPortIndex,
        'toNode': channelNode.id,
        'toPort': toPortIndex,
      });
    }

    return channelNode;
  }

  NodeModel _ensureInteractiveArtifactNode(NodeModel sourceNode) {
    if (sourceNode.type is InteractiveArtifactDetectionNodeType) {
      return sourceNode;
    }

    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != sourceNode.id) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child?.type is InteractiveArtifactDetectionNodeType) {
        return child!;
      }
    }

    final NodeType interactiveType = InteractiveArtifactDetectionNodeType();
    final NodeModel interactiveNode = _buildNode(
      type: interactiveType,
      position: _nearestAvailablePosition(
        Offset(
          sourceNode.position.dx,
          sourceNode.position.dy + _cardHeight + _spawnGap,
        ),
      ),
      params: <String, dynamic>{
        ...interactiveType.defaultParams,
        'interaction_mode': 'interactive',
        if (sourceNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            sourceNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(interactiveNode);

    int? fromPortIndex;
    int? toPortIndex;
    for (int candidateFromPort = 0;
        candidateFromPort < sourceNode.outputPorts.length;
        candidateFromPort++) {
      final int? candidateToPort = _matchingInputPortForOutputPort(
        sourceNode,
        candidateFromPort,
        interactiveNode,
      );
      if (candidateToPort != null) {
        fromPortIndex = candidateFromPort;
        toPortIndex = candidateToPort;
        break;
      }
    }
    if (fromPortIndex != null && toPortIndex != null) {
      connections.add(<String, dynamic>{
        'fromNode': sourceNode.id,
        'fromPort': fromPortIndex,
        'toNode': interactiveNode.id,
        'toPort': toPortIndex,
      });
    }

    return interactiveNode;
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

  void moveNodeOrSelection(NodeModel draggedNode, Offset targetPosition) {
    if (!selectedNodeIds.contains(draggedNode.id) || selectedNodeIds.length <= 1) {
      final Offset nextPosition = _nearestAvailablePosition(
        targetPosition,
        movingNodeId: draggedNode.id,
      );
      if (_tryInsertNodeIntoConnection(draggedNode, nextPosition)) {
        selectedNodeId = draggedNode.id;
        selectedNodeIds
          ..clear()
          ..add(draggedNode.id);
        selectedConnectionIndex = null;
        _clearPendingConnection();
        return;
      }
      if (nextPosition != draggedNode.position) {
        _recordUndo('move node');
        draggedNode.position = nextPosition;
      }
      selectedNodeId = draggedNode.id;
      selectedNodeIds
        ..clear()
        ..add(draggedNode.id);
      return;
    }

    final Set<String> movingIds = Set<String>.from(selectedNodeIds);
    final Offset snappedTarget = snapToGrid(targetPosition);
    final Offset delta = snappedTarget - draggedNode.position;
    if (delta == Offset.zero) {
      return;
    }

    final Map<String, Offset> nextPositions = <String, Offset>{};
    for (final NodeModel node in nodes) {
      if (!movingIds.contains(node.id)) {
        continue;
      }
      nextPositions[node.id] = Offset(
        math.max(0, node.position.dx + delta.dx),
        math.max(0, node.position.dy + delta.dy),
      );
    }

    if (_groupMoveOverlapsAnyNode(nextPositions, movingIds)) {
      return;
    }

    _recordUndo('move nodes');
    for (final NodeModel node in nodes) {
      final Offset? nextPosition = nextPositions[node.id];
      if (nextPosition != null) {
        node.position = nextPosition;
      }
    }
    selectedNodeId = draggedNode.id;
  }

  bool _groupMoveOverlapsAnyNode(
    Map<String, Offset> nextPositions,
    Set<String> movingIds,
  ) {
    for (final MapEntry<String, Offset> entry in nextPositions.entries) {
      final Rect probe = Rect.fromLTWH(
        entry.value.dx,
        entry.value.dy,
        _cardWidth,
        _cardHeight,
      );
      for (final NodeModel node in nodes) {
        if (movingIds.contains(node.id)) {
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
    }
    return false;
  }

  bool _tryInsertNodeIntoConnection(NodeModel draggedNode, Offset nextPosition) {
    if (_nodeHasAnyConnection(draggedNode.id)) {
      return false;
    }
    final int? connectionIndex = _connectionIndexIntersectingNodeRect(
      Rect.fromLTWH(
        nextPosition.dx,
        nextPosition.dy,
        _cardWidth,
        _cardHeight,
      ),
      ignoredNodeIds: <String>{draggedNode.id},
    );
    if (connectionIndex == null) {
      return false;
    }

    final Map<String, dynamic> existingConnection = Map<String, dynamic>.from(
      connections[connectionIndex],
    );
    final NodeModel? fromNode = _findNode(existingConnection['fromNode'] as String);
    final NodeModel? toNode = _findNode(existingConnection['toNode'] as String);
    if (fromNode == null || toNode == null) {
      return false;
    }
    final int originalFromPort = (existingConnection['fromPort'] as num?)?.toInt() ?? 0;
    final int originalToPort = (existingConnection['toPort'] as num?)?.toInt() ?? 0;
    final int? draggedInputPort = _matchingInputPortForOutputPort(
      fromNode,
      originalFromPort,
      draggedNode,
    );
    final int? draggedOutputPort = _matchingOutputPortForInputPort(
      draggedNode,
      toNode,
      originalToPort,
    );
    final bool introducesCycle =
        _collectDescendantsInclusive(toNode.id).contains(draggedNode.id) ||
            _collectAncestorsInclusive(fromNode.id).contains(draggedNode.id);
    if (draggedInputPort == null ||
        draggedOutputPort == null ||
        introducesCycle) {
      return false;
    }

    final Map<String, DatasetState> previousInsertedStates =
        Map<String, DatasetState>.from(draggedNode.datasetStates);
    final Map<String, DatasetState> previousChildStates =
        Map<String, DatasetState>.from(toNode.datasetStates);
    _recordUndo('insert node into wire');
    draggedNode.position = nextPosition;
    connections.removeAt(connectionIndex);
    connections.add(<String, dynamic>{
      'fromNode': fromNode.id,
      'fromPort': originalFromPort,
      'toNode': draggedNode.id,
      'toPort': draggedInputPort,
    });
    connections.add(<String, dynamic>{
      'fromNode': draggedNode.id,
      'fromPort': draggedOutputPort,
      'toNode': toNode.id,
      'toPort': originalToPort,
    });
    _updateStatesAfterNodeInsertion(
      insertedNode: draggedNode,
      interruptedChild: toNode,
      previousInsertedStates: previousInsertedStates,
      previousChildStates: previousChildStates,
    );
    return true;
  }

  bool _nodeHasAnyConnection(String nodeId) {
    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] == nodeId || connection['toNode'] == nodeId) {
        return true;
      }
    }
    return false;
  }

  int? _matchingOutputPortForInputPort(
    NodeModel fromNode,
    NodeModel toNode,
    int toPortIndex,
  ) {
    if (toPortIndex < 0 || toPortIndex >= toNode.inputPorts.length) {
      return null;
    }
    final PortType inputType = toNode.inputPorts[toPortIndex].type;
    for (final _EffectiveOutputPort outputPort in _effectiveOutputPorts(fromNode)) {
      if (outputPort.port.type == inputType) {
        return outputPort.portIndex;
      }
    }
    return null;
  }

  void _updateStatesAfterNodeInsertion({
    required NodeModel insertedNode,
    required NodeModel interruptedChild,
    required Map<String, DatasetState> previousInsertedStates,
    required Map<String, DatasetState> previousChildStates,
  }) {
    for (final Dataset dataset in datasets.values) {
      final String datasetId = dataset.id;
      insertedNode.datasetStates[datasetId] = _nextStateAfterWireInsertion(
        node: insertedNode,
        datasetId: datasetId,
        previousState: previousInsertedStates[datasetId],
      );
      interruptedChild.datasetStates[datasetId] = _nextStateAfterWireInsertion(
        node: interruptedChild,
        datasetId: datasetId,
        previousState: previousChildStates[datasetId],
      );
    }
  }

  DatasetState _nextStateAfterWireInsertion({
    required NodeModel node,
    required String datasetId,
    required DatasetState? previousState,
  }) {
    final DatasetState prior = previousState ?? DatasetState.notReady;
    final bool selectedForNode = _datasetsForNode(node).contains(datasetId);
    if (!selectedForNode) {
      return prior == DatasetState.done ? DatasetState.done : DatasetState.notReady;
    }
    if (prior == DatasetState.done || prior == DatasetState.stale) {
      return DatasetState.stale;
    }
    final List<NodeModel> parents = _immediateParents(node.id);
    final bool structurallyReady =
        node.type is ImportNodeType ||
        parents.every((NodeModel parent) => _nodeHasRunForDataset(parent, datasetId));
    return structurallyReady ? DatasetState.ready : DatasetState.notReady;
  }

  int? _connectionIndexIntersectingNodeRect(
    Rect nodeRect, {
    Set<String> ignoredNodeIds = const <String>{},
  }) {
    final Rect probe = nodeRect.inflate(8);
    for (int index = connections.length - 1; index >= 0; index--) {
      final Map<String, dynamic> connection = connections[index];
      final String fromNodeId = connection['fromNode'] as String;
      final String toNodeId = connection['toNode'] as String;
      if (ignoredNodeIds.contains(fromNodeId) || ignoredNodeIds.contains(toNodeId)) {
        continue;
      }
      final NodeModel? fromNode = _findNode(fromNodeId);
      final NodeModel? toNode = _findNode(toNodeId);
      if (fromNode == null || toNode == null) {
        continue;
      }
      final int fromPort = (connection['fromPort'] as num?)?.toInt() ?? 0;
      final Offset start = _outputAnchor(fromNode, toNode, fromPortIndex: fromPort);
      final Offset end = _inputAnchor(fromNode, toNode);
      final List<Offset> points = buildConnectionPolyline(
        start: start,
        end: end,
        preferVertical: (end.dy - start.dy).abs() >= (end.dx - start.dx).abs(),
        gridWidth: _gridWidth,
        gridHeight: _gridHeight,
        obstacles: _connectionObstacles(fromNode, toNode),
      );
      if (_polylineIntersectsRect(points, probe)) {
        return index;
      }
    }
    return null;
  }

  bool _polylineIntersectsRect(List<Offset> points, Rect rect) {
    for (int index = 1; index < points.length; index++) {
      if (_segmentIntersectsRect(points[index - 1], points[index], rect)) {
        return true;
      }
    }
    return false;
  }

  bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
    if ((a.dx - b.dx).abs() < 0.001) {
      final double x = a.dx;
      if (x < rect.left || x > rect.right) {
        return false;
      }
      final double top = math.min(a.dy, b.dy);
      final double bottom = math.max(a.dy, b.dy);
      return bottom >= rect.top && top <= rect.bottom;
    }
    if ((a.dy - b.dy).abs() < 0.001) {
      final double y = a.dy;
      if (y < rect.top || y > rect.bottom) {
        return false;
      }
      final double left = math.min(a.dx, b.dx);
      final double right = math.max(a.dx, b.dx);
      return right >= rect.left && left <= rect.right;
    }
    return false;
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
    return '#${nodes.indexOf(node) + 1}${_branchLabelForNode(node.id)} ${node.title}';
  }

  String descriptorForNode(NodeModel node) => _nodeDescriptor(node);

  String _branchLabelForNode(String nodeId) {
    return _branchLabelsByNodeId()[nodeId] ?? 'A';
  }

  Map<String, String> _branchLabelsByNodeId() {
    final Map<String, String> labels = <String, String>{
      for (final NodeModel node in nodes) node.id: 'A',
    };
    final List<NodeModel> orderedNodes =
        _orderedNodes(nodes.map((NodeModel node) => node.id).toSet());

    for (final NodeModel mergeNode in orderedNodes) {
      final List<NodeModel> parents = _immediateParents(mergeNode.id);
      if (parents.length < 2) {
        continue;
      }

      final List<NodeModel> orderedParents = List<NodeModel>.from(parents)
        ..sort((NodeModel a, NodeModel b) {
          final int xCompare = a.position.dx.compareTo(b.position.dx);
          if (xCompare != 0) {
            return xCompare;
          }
          return nodes.indexOf(a).compareTo(nodes.indexOf(b));
        });
      final Map<String, Set<String>> ancestorSets = <String, Set<String>>{
        for (final NodeModel parent in orderedParents)
          parent.id: _collectAncestorsInclusive(parent.id),
      };
      Set<String>? commonAncestors;
      for (final Set<String> ancestorSet in ancestorSets.values) {
        commonAncestors = commonAncestors == null
            ? Set<String>.from(ancestorSet)
            : commonAncestors.intersection(ancestorSet);
      }
      final Set<String> shared = commonAncestors ?? const <String>{};

      for (int index = 0; index < orderedParents.length; index++) {
        final NodeModel parent = orderedParents[index];
        final String letter = _branchLetter(index);
        final Set<String> uniqueNodes = Set<String>.from(
          ancestorSets[parent.id] ?? const <String>{},
        )..removeAll(shared);
        for (final String uniqueNodeId in uniqueNodes) {
          labels[uniqueNodeId] = letter;
        }
      }
    }

    return labels;
  }

  String _branchLetter(int index) {
    if (index < 0) {
      return 'A';
    }
    String value = '';
    int current = index;
    do {
      value = String.fromCharCode(65 + (current % 26)) + value;
      current = (current ~/ 26) - 1;
    } while (current >= 0);
    return value;
  }

  int? _matchingInputPortForOutputPort(
    NodeModel fromNode,
    int fromPortIndex,
    NodeModel toNode,
  ) {
    final List<_EffectiveOutputPort> effectivePorts = _effectiveOutputPorts(fromNode);
    final _EffectiveOutputPort? effectivePort = effectivePorts.cast<_EffectiveOutputPort?>().firstWhere(
      (_EffectiveOutputPort? port) => port?.portIndex == fromPortIndex,
      orElse: () => null,
    );
    if (effectivePort == null) {
      return null;
    }
    final PortType outputType = effectivePort.port.type;
    for (int toPortIndex = 0;
        toPortIndex < toNode.inputPorts.length;
        toPortIndex++) {
      if (toNode.inputPorts[toPortIndex].type == outputType) {
        return toPortIndex;
      }
    }
    return null;
  }

  _PortConnection? _firstMatchingPortConnection(
    NodeModel fromNode,
    NodeModel toNode,
  ) {
    final List<_EffectiveOutputPort> effectivePorts = _effectiveOutputPorts(fromNode);
    for (final _EffectiveOutputPort outputPort in effectivePorts) {
      final int? toPortIndex = _matchingInputPortForOutputPort(
        fromNode,
        outputPort.portIndex,
        toNode,
      );
      if (toPortIndex != null) {
        return _PortConnection(
          fromPortIndex: outputPort.portIndex,
          toPortIndex: toPortIndex,
        );
      }
    }
    return null;
  }

  bool _isValidDownstreamPlacement(NodeModel fromNode, NodeModel toNode) {
    final double dx = toNode.position.dx - fromNode.position.dx;
    final double dy = toNode.position.dy - fromNode.position.dy;
    return dx >= 24 || dy >= 24;
  }

  Offset _outputAnchor(
    NodeModel fromNode,
    NodeModel toNode, {
    required int fromPortIndex,
  }) {
    return _nodeEdgeAnchorFacing(fromNode, toNode);
  }

  Offset _inputAnchor(NodeModel fromNode, NodeModel toNode) {
    return _nodeEdgeAnchorFacing(toNode, fromNode);
  }

  Offset _nodeEdgeAnchorFacing(NodeModel node, NodeModel target) {
    final Offset nodeCenter = Offset(
      node.position.dx + (_cardWidth / 2),
      node.position.dy + (_cardHeight / 2),
    );
    final Offset targetCenter = Offset(
      target.position.dx + (_cardWidth / 2),
      target.position.dy + (_cardHeight / 2),
    );
    final Offset delta = targetCenter - nodeCenter;
    if (delta.dx.abs() > delta.dy.abs()) {
      return Offset(
        delta.dx >= 0 ? node.position.dx + _cardWidth : node.position.dx,
        nodeCenter.dy,
      );
    }
    if (delta.dy >= 0) {
      return Offset(
        nodeCenter.dx,
        node.position.dy + _cardHeight,
      );
    }
    return Offset(
      nodeCenter.dx,
      node.position.dy,
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

      final int fromPort = (connection['fromPort'] as num?)?.toInt() ?? 0;
      final Offset start = _outputAnchor(fromNode, toNode, fromPortIndex: fromPort);
      final Offset end = _inputAnchor(fromNode, toNode);
      if (_isPointNearConnection(
        point,
        start,
        end,
        obstacles: _connectionObstacles(fromNode, toNode),
      )) {
        return index;
      }
    }
    return null;
  }

  bool _isPointNearConnection(
    Offset point,
    Offset start,
    Offset end, {
    List<Rect> obstacles = const <Rect>[],
  }) {
    const double threshold = 12.0;
    final bool preferVertical = (end.dy - start.dy).abs() >= (end.dx - start.dx).abs();
    final List<Offset> points = buildConnectionPolyline(
      start: start,
      end: end,
      preferVertical: preferVertical,
      gridWidth: _gridWidth,
      gridHeight: _gridHeight,
      obstacles: obstacles,
    );

    for (int index = 1; index < points.length; index++) {
      final Offset previous = points[index - 1];
      final Offset current = points[index];
      if (_distanceToSegment(point, previous, current) <= threshold) {
        return true;
      }
    }
    return false;
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

  List<Rect> _connectionObstacles(NodeModel fromNode, NodeModel toNode) {
    return nodes
        .where((NodeModel node) => node.id != fromNode.id && node.id != toNode.id)
        .map((NodeModel node) {
          return Rect.fromLTWH(
            node.position.dx,
            node.position.dy,
            _cardWidth,
            _cardHeight,
          );
        })
        .toList(growable: false);
  }

  List<_EffectiveOutputPort> _effectiveOutputPorts(NodeModel node) {
    final List<_EffectiveOutputPort> ports = <_EffectiveOutputPort>[
      for (int index = 0; index < node.outputPorts.length; index++)
        _EffectiveOutputPort(portIndex: index, port: node.outputPorts[index]),
    ];
    final bool hasSignalLikeOutput = node.outputPorts.any(
      (PortSpec port) =>
          port.type == PortType.signal ||
          (port.type == PortType.metadata &&
              port.name.toLowerCase().contains('segments')),
    );
    final bool hasMarkerOutput = node.outputPorts.any(
      (PortSpec port) => port.type == PortType.markers,
    );
    if (hasSignalLikeOutput && !hasMarkerOutput) {
      ports.add(
        _EffectiveOutputPort(
          portIndex: node.outputPorts.length,
          port: const PortSpec(name: 'markers', type: PortType.markers),
        ),
      );
    }
    return ports;
  }

  bool _hasAnyDiskSnapshot(String nodeId) =>
      (_nodeDiskSnapshotIds[nodeId]?.isNotEmpty ?? false);

  DatasetArtifactSnapshot? _primarySnapshotForNode(NodeModel node) {
    final Map<String, DatasetArtifactSnapshot>? snapshots = _nodeRamSnapshots[node.id];
    if (snapshots == null || snapshots.isEmpty) {
      return null;
    }

    final List<Dataset> orderedDatasets = datasets.values.toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    for (final Dataset dataset in orderedDatasets) {
      final DatasetArtifactSnapshot? snapshot = snapshots[dataset.id];
      if (snapshot != null && !snapshot.isEmpty) {
        return snapshot;
      }
    }

    for (final DatasetArtifactSnapshot snapshot in snapshots.values) {
      if (!snapshot.isEmpty) {
        return snapshot;
      }
    }
    return null;
  }

  _OutputHandleDescriptor? _outputDescriptorForPort({
    required NodeModel node,
    required int portIndex,
    required PortSpec port,
    required DatasetArtifactSnapshot? snapshot,
  }) {
    final String portName = port.name.toLowerCase();
    switch (port.type) {
      case PortType.signal:
        if (portName.contains('psd') && snapshot?.spectrum != null) {
          final int segmentCount = snapshot!.spectrum!.segmentCount;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.spectrum,
            hasOutput: true,
            badgeText: segmentCount == 1 ? '' : '$segmentCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.timeSeries != null) {
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.timeSeries,
            hasOutput: true,
            badgeText: '',
            tooltip: '${port.name} output',
          );
        }
        return _OutputHandleDescriptor(
          kind: portName.contains('psd')
              ? _OutputHandleKind.spectrum
              : _OutputHandleKind.timeSeries,
          hasOutput: _hasAnyDiskSnapshot(node.id),
          badgeText: '',
          tooltip: '${port.name} output',
        );
      case PortType.markers:
        final int markerCount = snapshot?.timeSeries?.markers.length ?? 0;
        return _OutputHandleDescriptor(
          kind: _OutputHandleKind.markers,
          hasOutput: snapshot?.timeSeries != null || _hasAnyDiskSnapshot(node.id),
          badgeText: markerCount == 1 ? '' : '$markerCount',
          tooltip: '${port.name} output',
        );
      case PortType.metadata:
        if (portName.contains('segments') && snapshot?.segmentedTimeSeries != null) {
          final int segmentCount = snapshot!.segmentedTimeSeries!.segmentCount;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.segments,
            hasOutput: true,
            badgeText: segmentCount == 1 ? '' : '$segmentCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.timeFrequency != null &&
            (portName.contains('time_frequency') || portName.contains('time-frequency'))) {
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.timeFrequency,
            hasOutput: true,
            badgeText: '',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.featureTable != null) {
          final int rowCount = snapshot!.featureTable!.rows.length;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.table,
            hasOutput: true,
            badgeText: rowCount == 1 ? '' : '$rowCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.bridgeDetection != null) {
          final int frameCount = snapshot!.bridgeDetection!.frameCount;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.table,
            hasOutput: true,
            badgeText: frameCount == 1 ? '' : '$frameCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.fooofResult != null) {
          final int peakCount = snapshot!.fooofResult!.peaks.length;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.table,
            hasOutput: true,
            badgeText: peakCount == 1 ? '' : '$peakCount',
            tooltip: '${port.name} output',
          );
        }
        return _OutputHandleDescriptor(
          kind: portName.contains('segments')
              ? _OutputHandleKind.segments
              : _OutputHandleKind.table,
          hasOutput: _hasAnyDiskSnapshot(node.id),
          badgeText: '',
          tooltip: '${port.name} output',
        );
      case PortType.matrixTransformation:
        if (snapshot?.matrixTransformation != null) {
          final int count = snapshot!.matrixTransformation!.componentLabels.isNotEmpty
              ? snapshot.matrixTransformation!.componentLabels.length
              : snapshot.matrixTransformation!.matrix.length;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.matrix,
            hasOutput: true,
            badgeText: count == 1 ? '' : '$count',
            tooltip: '${port.name} output',
          );
        }
        return _OutputHandleDescriptor(
          kind: _OutputHandleKind.matrix,
          hasOutput: _hasAnyDiskSnapshot(node.id),
          badgeText: '',
          tooltip: '${port.name} output',
        );
    }
  }

  Color _outputColorForPort(NodeModel node, int portIndex) {
    final PortSpec port = _effectiveOutputPorts(node)
        .firstWhere(( _EffectiveOutputPort item) => item.portIndex == portIndex)
        .port;
    final _OutputHandleDescriptor? descriptor = _outputDescriptorForPort(
      node: node,
      portIndex: portIndex,
      port: port,
      snapshot: _primarySnapshotForNode(node),
    );
    return _outputHandleColor(descriptor?.kind ?? _OutputHandleKind.other);
  }

  Color _outputHandleColor(_OutputHandleKind kind) {
    switch (kind) {
      case _OutputHandleKind.timeSeries:
        return const Color(0xFF4E9AF1);
      case _OutputHandleKind.spectrum:
        return const Color(0xFF8B5CF6);
      case _OutputHandleKind.timeFrequency:
        return const Color(0xFF14B8A6);
      case _OutputHandleKind.markers:
        return const Color(0xFFF59E0B);
      case _OutputHandleKind.segments:
        return const Color(0xFF06B6D4);
      case _OutputHandleKind.table:
        return const Color(0xFFFF6B6B);
      case _OutputHandleKind.matrix:
        return const Color(0xFFEC4899);
      case _OutputHandleKind.other:
        return Colors.white70;
    }
  }

}

class _OutputHandleDescriptor {
  const _OutputHandleDescriptor({
    required this.kind,
    required this.hasOutput,
    required this.badgeText,
    required this.tooltip,
  });

  final _OutputHandleKind kind;
  final bool hasOutput;
  final String badgeText;
  final String tooltip;
}

class _EffectiveOutputPort {
  const _EffectiveOutputPort({
    required this.portIndex,
    required this.port,
  });

  final int portIndex;
  final PortSpec port;
}

class _PortConnection {
  const _PortConnection({
    required this.fromPortIndex,
    required this.toPortIndex,
  });

  final int fromPortIndex;
  final int toPortIndex;
}
