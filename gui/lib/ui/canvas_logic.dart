import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset_artifact_snapshot.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';
import '../model/node.dart';
import '../nodes/add_remove_markers_node.dart';
import '../nodes/amplitude_features_node.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/bridge_detector_node.dart';
import '../nodes/channel_exclusion_node.dart';
import '../nodes/debug_output_node.dart';
import '../nodes/eye_blinks_node.dart';
import '../nodes/export_edf_node.dart';
import '../nodes/fooof_node.dart';
import '../nodes/import_node.dart';
import '../nodes/interactive_artifact_detection_node.dart';
import '../nodes/matrix_transform_nodes.dart';
import '../nodes/machine_learning_nodes.dart';
import '../nodes/node_type.dart';
import '../nodes/psd_node.dart';
import '../nodes/realign_node.dart';
import '../nodes/resample_node.dart';
import '../nodes/segmentation_node.dart';
import '../nodes/sleep_staging_node.dart';
import '../nodes/spectral_features_node.dart';
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
    ChannelExclusionNodeType(),
    BridgeDetectorNodeType(),
    ResampleNodeType(),
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
    KMeansNodeType(),
    CNNNodeType(),
    AddRemoveMarkersNodeType(),
    InteractiveArtifactDetectionNodeType(),
    SegmentationNodeType(),
    EyeBlinksNodeType(),
    SleepStagingNodeType(),
    RealignNodeType(),
    VisualizationNodeType(),
    DebugOutputNodeType(),
    ExportNodeType(),
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
  final Map<String, Set<String>> _nodeDiskSnapshotIds = <String, Set<String>>{};

  String? selectedNodeId;
  int? selectedConnectionIndex;

  String? _pendingFromNodeId;
  final Map<NodeCategory, bool> _collapsedCategories = <NodeCategory, bool>{};
  final Map<String, bool> _collapsedSubcategories = <String, bool>{};

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
    _nodeRamSnapshots.clear();
    _nodeDiskSnapshotIds.clear();
    selectedNodeId = null;
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  Future<void> pickFiles() async {
    final List<XFile> files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'BrainStory Signals',
          extensions: <String>['csv', 'tsv', 'txt', 'edf', 'set', 'fdt'],
        ),
      ],
    );

    for (final XFile file in files) {
      final String normalizedPath = eeglabMetadataPathForSelection(file.path);
      final bool selectedFdt = file.name.toLowerCase().endsWith('.fdt');
      final Uint8List? bytes = selectedFdt ? null : await file.readAsBytes();
      final String sourceName = selectedFdt
          ? '${file.name.substring(0, file.name.length - 4)}.set'
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
    clearAll();
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
    required VoidCallback publish,
    required VoidCallback export,
    required VoidCallback load,
    required VoidCallback clear,
    required VoidCallback update,
  }) {
    final List<NodeCategory> categoryOrder = <NodeCategory>[
      NodeCategory.import,
      NodeCategory.transform,
      NodeCategory.machineLearning,
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
                onPressed: publish,
                child: const Text('Publish'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
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

      final Offset start = _outputAnchor(fromNode, toNode);
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
            if (context.mounted) {
              _showStatusSnackBar(context, 'Run failed: $error');
            }
          } finally {
            finishRunUi();
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
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(node);
    for (final Dataset dataset in datasets.values) {
      node.datasetStates[dataset.id] = availableDatasetIds.contains(dataset.id)
          ? DatasetState.ready
          : DatasetState.notReady;
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

    return sourceDatasetsForVisualizationNode(node.id);
  }

  Future<List<Dataset>> datasetsForVisualizationNode(String nodeId) async {
    return materializedDatasetViewsForNode(
      nodeId,
      sourceDatasetsForVisualizationNode(nodeId),
    );
  }

  List<Dataset> sourceDatasetsForVisualizationNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return <Dataset>[];
    }

    final Set<String> datasetIds = _datasetsForNode(node);
    final List<Dataset> matchingDatasets = datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList(growable: false);
    matchingDatasets.sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    return matchingDatasets;
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

  Future<Dataset> materializedDatasetViewForNode(String nodeId, Dataset source) async {
    final Dataset view = Dataset(
      source.id,
      label: source.label,
      path: source.path,
      sourceBytes: source.sourceBytes,
    );
    view.loaded = source.loaded;
    view.ram.addAll(source.ram);
    final DatasetArtifactSnapshot? snapshot = await _loadSnapshotForNodeDataset(
      nodeId,
      source.id,
    );
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
    if (node.type is BridgeDetectorNodeType) {
      return true;
    }
    if (node.type is PSDNodeType) {
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
          _markImmediateChildrenStale(node.id, dataset.id);
        } catch (_) {
          node.datasetStates[dataset.id] = _availableDatasetIdsForNode(node)
                  .contains(dataset.id)
              ? DatasetState.ready
              : DatasetState.notReady;
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
            (NodeModel parent) =>
                (parent.datasetStates[dataset.id] ?? DatasetState.notReady) !=
                DatasetState.notReady,
          );
        })
        .map((Dataset dataset) => dataset.id)
        .toSet();
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
        if ((parent.datasetStates[dataset.id] ?? DatasetState.notReady) !=
            DatasetState.notReady) {
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
          parents.every(
            (NodeModel parent) =>
                (parent.datasetStates[datasetId] ?? DatasetState.notReady) !=
                DatasetState.notReady,
          );

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

  void _markImmediateChildrenStale(String nodeId, String datasetId) {
    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != nodeId) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child?.datasetStates[datasetId] == DatasetState.done) {
        child!.datasetStates[datasetId] = DatasetState.stale;
      }
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
    _markImmediateChildrenStale(markerNode.id, dataset.id);
    selectedNodeId = markerNode.id;
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  void applyInteractiveArtifactDetectionFromVisualization({
    required String nodeId,
    required Dataset dataset,
  }) {
    final NodeModel? sourceNode = _interactiveArtifactSourceNode(nodeId);
    if (sourceNode == null) {
      return;
    }

    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      dataset.timeSeries = timeSeries.copyWith(
        markers: InteractiveArtifactDetectionNodeType.acceptedMarkersForDataset(
          dataset.id,
          sourceNode.params,
          baseMarkers: timeSeries.markers,
        ),
      );
    }

    sourceNode.datasetStates[dataset.id] = DatasetState.done;
    _markImmediateChildrenStale(sourceNode.id, dataset.id);
    selectedNodeId = sourceNode.id;
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
      _nodeDiskSnapshotIds
          .putIfAbsent(node.id, () => <String>{})
          .add(dataset.id);
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
    } finally {
      finishRunUi();
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
      _markImmediateChildrenStale(node.id, dataset.id);
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
    _nodeDiskSnapshotIds.putIfAbsent(nodeId, () => <String>{}).add(datasetId);
    _nodeRamSnapshots
        .putIfAbsent(nodeId, () => <String, DatasetArtifactSnapshot>{})[datasetId] = snapshot;
    return snapshot;
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
    return node.type.category.color;
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
}
