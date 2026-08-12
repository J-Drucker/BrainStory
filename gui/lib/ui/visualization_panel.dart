import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/node.dart';
import '../platform/brainstory_engine.dart';
import '../nodes/sleep_staging_node.dart';
import 'canvas_logic.dart';
import 'raw_signal_browser.dart';

class VisualizationPanel extends StatelessWidget {
  const VisualizationPanel({
    super.key,
    required this.logic,
    required this.onChanged,
  });

  final CanvasLogic logic;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final NodeModel? node = logic.selectedVisualizationTarget;
    if (node == null) {
      return _panelShell(
        child: _emptyState(
          'Visualization',
          'Select a node to inspect its output here.',
        ),
      );
    }

    if (logic.isVisualizationNode(node) &&
        logic.visualizationDisplayMode(node) == 'window') {
      return _panelShell(child: _WindowModeMessage(title: node.title));
    }

    return _panelShell(
      child: VisualizationSurface(
        logic: logic,
        nodeId: node.id,
        onChanged: onChanged,
      ),
    );
  }

  Widget _panelShell({required Widget child}) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class VisualizationFullscreenPage extends StatelessWidget {
  const VisualizationFullscreenPage({
    super.key,
    required this.logic,
    required this.nodeId,
  });

  final CanvasLogic logic;
  final String nodeId;

  @override
  Widget build(BuildContext context) {
    NodeModel? node;
    for (final NodeModel item in logic.nodes) {
      if (item.id == nodeId) {
        node = item;
        break;
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(node?.title ?? 'Visualization'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: node == null
              ? _emptyState(
                  'Visualization unavailable',
                  'This node is no longer available.',
                )
              : VisualizationSurface(
                  logic: logic,
                  nodeId: nodeId,
                  onChanged: null,
                ),
        ),
      ),
    );
  }
}

class VisualizationSurface extends StatefulWidget {
  const VisualizationSurface({
    super.key,
    required this.logic,
    required this.nodeId,
    required this.onChanged,
  });

  final CanvasLogic logic;
  final String nodeId;
  final VoidCallback? onChanged;

  @override
  State<VisualizationSurface> createState() => _VisualizationSurfaceState();
}

class _VisualizationSurfaceState extends State<VisualizationSurface> {
  final Set<String> _selectedSourceKeys = <String>{};
  String? _activeSourceKey;
  Future<List<Dataset>>? _materializedDatasetsFuture;
  String _materializedDatasetsKey = '';

  CanvasLogic get logic => widget.logic;

  @override
  void didUpdateWidget(covariant VisualizationSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      _selectedSourceKeys.clear();
      _activeSourceKey = null;
      _materializedDatasetsFuture = null;
      _materializedDatasetsKey = '';
    }
    _syncSelectedDatasets(logic.visualizationSourceRefsForNode(widget.nodeId));
  }

  @override
  Widget build(BuildContext context) {
    NodeModel? maybeNode;
    for (final NodeModel item in logic.nodes) {
      if (item.id == widget.nodeId) {
        maybeNode = item;
        break;
      }
    }

    if (maybeNode == null) {
      return _emptyState(
        'Visualization unavailable',
        'This node is no longer available.',
      );
    }
    final NodeModel node = maybeNode;
    final List<VisualizationSourceRef> sourceRefs = logic
        .visualizationSourceRefsForNode(widget.nodeId);
    _syncSelectedDatasets(sourceRefs);
    final bool comparisonNode = logic.isVisualizationNode(node);
    final List<VisualizationSourceRef> selectedSourceRefs = _selectedSources(
      sourceRefs,
    );
    _refreshMaterializedDatasets(selectedSourceRefs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            Text(
              sourceRefs.isEmpty
                  ? (comparisonNode
                        ? 'Connect this visualization node to an Import-backed path and choose datasets to compare.'
                        : 'Run an Import-backed path into this node so there is output available to inspect.')
                  : (comparisonNode
                        ? 'Select one or more datasets to compare.'
                        : 'Select one or more datasets to inspect.'),
              style: const TextStyle(color: Colors.white70, height: 1.2),
            ),
            if (sourceRefs.isNotEmpty)
              ...sourceRefs.map((VisualizationSourceRef source) {
                final bool selected = _selectedSourceKeys.contains(source.key);
                return FilterChip(
                  label: Text(source.displayLabel),
                  selected: selected,
                  onSelected: (bool nextValue) {
                    setState(() {
                      if (nextValue) {
                        _selectedSourceKeys.add(source.key);
                        _activeSourceKey ??= source.key;
                      } else {
                        _selectedSourceKeys.remove(source.key);
                        if (_activeSourceKey == source.key) {
                          _activeSourceKey = _selectedSourceKeys.isEmpty
                              ? null
                              : _selectedSourceKeys.first;
                        }
                      }
                    });
                  },
                );
              }),
          ],
        ),
        if (sourceRefs.isEmpty)
          _emptyState(
            'No dataset',
            comparisonNode
                ? 'Connect this visualization node to an Import-backed path and choose datasets to compare.'
                : 'Run an Import-backed path into this node so there is output available to inspect.',
          )
        else ...<Widget>[
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Dataset>>(
              future: _materializedDatasetsFuture,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<Dataset>> snapshot,
                  ) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Loading node output...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      );
                    }
                    final List<Dataset> datasets =
                        snapshot.data ?? const <Dataset>[];
                    final String view = logic
                        .visualizationViewForNodeAndDatasets(node, datasets);
                    final bool needsActiveDatasetPicker =
                        (view == 'raw' ||
                            view == 'segments' ||
                            view == 'hypnogram' ||
                            view == 'bridge') &&
                        selectedSourceRefs.length > 1;
                    return Column(
                      children: <Widget>[
                        if (needsActiveDatasetPicker)
                          DropdownButtonFormField<String>(
                            initialValue:
                                _activeSourceKey ??
                                selectedSourceRefs.first.key,
                            decoration: const InputDecoration(
                              labelText: 'Active dataset',
                            ),
                            items: selectedSourceRefs
                                .map(
                                  (VisualizationSourceRef source) =>
                                      DropdownMenuItem<String>(
                                        value: source.key,
                                        child: Text(source.displayLabel),
                                      ),
                                )
                                .toList(growable: false),
                            onChanged: (String? value) {
                              setState(() {
                                _activeSourceKey = value;
                              });
                            },
                          ),
                        if (needsActiveDatasetPicker)
                          const SizedBox(height: 12),
                        Expanded(
                          child: _VisualizationChart(
                            logic: logic,
                            nodeId: node.id,
                            datasets: _selectedDatasets(datasets),
                            activeDatasetId: _activeSourceKey,
                            view: view,
                            params: node.params,
                            comparisonNode: comparisonNode,
                            onChanged: () {
                              setState(() {});
                              widget.onChanged?.call();
                            },
                            onDataChanged: () {
                              setState(() {
                                _materializedDatasetsFuture = null;
                                _materializedDatasetsKey = '';
                              });
                              widget.onChanged?.call();
                            },
                          ),
                        ),
                      ],
                    );
                  },
            ),
          ),
        ],
      ],
    );
  }

  List<Dataset> _selectedDatasets(List<Dataset> datasets) {
    return datasets
        .where((Dataset dataset) {
          final String key =
              dataset.ram['viewer.sourceKey']?.toString() ?? dataset.id;
          return _selectedSourceKeys.contains(key);
        })
        .toList(growable: false);
  }

  List<VisualizationSourceRef> _selectedSources(
    List<VisualizationSourceRef> sources,
  ) {
    return sources
        .where(
          (VisualizationSourceRef source) =>
              _selectedSourceKeys.contains(source.key),
        )
        .toList(growable: false);
  }

  void _syncSelectedDatasets(List<VisualizationSourceRef> sources) {
    if (sources.isEmpty) {
      _selectedSourceKeys.clear();
      _materializedDatasetsFuture = Future<List<Dataset>>.value(
        const <Dataset>[],
      );
      _materializedDatasetsKey = '';
      return;
    }

    final Set<String> availableKeys = sources
        .map((VisualizationSourceRef source) => source.key)
        .toSet();
    _selectedSourceKeys.removeWhere(
      (String key) => !availableKeys.contains(key),
    );
    if (_activeSourceKey != null &&
        !_selectedSourceKeys.contains(_activeSourceKey)) {
      _activeSourceKey = _selectedSourceKeys.isEmpty
          ? null
          : _selectedSourceKeys.first;
    }
  }

  void _refreshMaterializedDatasets(
    List<VisualizationSourceRef> selectedSourceRefs,
  ) {
    final String key = <String>[
      widget.nodeId,
      ...selectedSourceRefs.map((VisualizationSourceRef source) => source.key),
    ].join('|');
    if (_materializedDatasetsFuture != null &&
        _materializedDatasetsKey == key) {
      return;
    }
    _materializedDatasetsKey = key;
    _materializedDatasetsFuture = logic.materializedDatasetViewsForSourceRefs(
      selectedSourceRefs,
    );
  }
}

class _WindowModeMessage extends StatelessWidget {
  const _WindowModeMessage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This visualization is configured to open in a fullscreen window.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _VisualizationChart extends StatelessWidget {
  const _VisualizationChart({
    required this.logic,
    required this.nodeId,
    required this.datasets,
    required this.activeDatasetId,
    required this.view,
    required this.params,
    required this.comparisonNode,
    required this.onChanged,
    required this.onDataChanged,
  });

  final CanvasLogic logic;
  final String nodeId;
  final List<Dataset> datasets;
  final String? activeDatasetId;
  final String view;
  final Map<String, dynamic> params;
  final bool comparisonNode;
  final VoidCallback onChanged;
  final VoidCallback onDataChanged;

  @override
  Widget build(BuildContext context) {
    if (datasets.isEmpty) {
      return const _ChartMessage(
        title: 'No dataset selected',
        body: 'Choose one or more datasets above to render the visualization.',
      );
    }

    if (view == 'time_frequency') {
      return const _ChartMessage(
        title: 'Time-frequency view is not implemented yet',
        body:
            'This visualizer can already infer the upstream output type, but the time-frequency renderer still needs to be built.',
      );
    }

    if (view == 'psd') {
      return _PsdChart(
        datasets: datasets,
        params: params,
        onChanged: onChanged,
      );
    }
    if (view == 'impedances') {
      return _ImpedanceChart(
        datasets: datasets,
        params: params,
        onChanged: onChanged,
      );
    }
    if (view == 'bridge') {
      final Dataset activeDataset = datasets.firstWhere(
        (Dataset dataset) => dataset.id == activeDatasetId,
        orElse: () => datasets.first,
      );
      return _BridgeHeatmapChart(
        dataset: activeDataset,
        params: params,
        onChanged: onChanged,
      );
    }
    if (view == 'hypnogram') {
      final Dataset activeDataset = datasets.firstWhere(
        (Dataset dataset) => dataset.id == activeDatasetId,
        orElse: () => datasets.first,
      );
      return _HypnogramChart(
        dataset: activeDataset,
        params: params,
        onChanged: onChanged,
      );
    }
    if (view == 'segments') {
      final Dataset activeDataset = datasets.firstWhere(
        (Dataset dataset) => dataset.id == activeDatasetId,
        orElse: () => datasets.first,
      );
      return _SegmentedChart(dataset: activeDataset, params: params);
    }
    if (comparisonNode && datasets.length > 1) {
      return const _ChartMessage(
        title: 'Raw comparison is not ready yet',
        body:
            'Select one dataset for the raw browser. PSD comparison overlays are inferred and rendered automatically when this node is fed from a PSD path.',
      );
    }
    final Dataset activeDataset = datasets.firstWhere(
      (Dataset dataset) => dataset.id == activeDatasetId,
      orElse: () => datasets.first,
    );
    return RawSignalBrowser(
      dataset: activeDataset,
      params: params,
      onPersistDrafts: (ViewerDraftSaveRequest request) async {
        final String message = await logic.persistViewerEdits(
          viewerNodeId: nodeId,
          dataset: activeDataset,
          markerEdits: request.markerEdits,
          channelEditConfig: request.channelEditConfig,
          interactiveArtifactParams: request.interactiveArtifactParams,
          runAfterSave: request.runAfterSave,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        onDataChanged();
      },
      onQuit: () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        logic.selectedNodeId = null;
        onChanged();
      },
      onChanged: onChanged,
    );
  }
}

class _SegmentedChart extends StatefulWidget {
  const _SegmentedChart({required this.dataset, required this.params});

  final Dataset dataset;
  final Map<String, dynamic> params;

  @override
  State<_SegmentedChart> createState() => _SegmentedChartState();
}

class _SegmentedChartState extends State<_SegmentedChart> {
  static const List<double> _timeSpanOptionsSec = <double>[
    0.1,
    0.25,
    0.5,
    1,
    2,
    5,
    10,
    20,
    30,
  ];
  static const List<double> _yScaleOptionsUv = <double>[
    10,
    25,
    50,
    100,
    200,
    500,
    1000,
  ];
  static const List<double> _channelSpacingOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  late final FocusNode _focusNode;
  final Map<String, ScrollController> _segmentScrollControllers =
      <String, ScrollController>{};
  final Map<String, ScrollController> _plotHorizontalControllers =
      <String, ScrollController>{};
  bool _syncingSegmentScroll = false;
  double _sharedSegmentScrollOffset = 0;
  bool _syncingPlotScroll = false;
  double _sharedPlotScrollOffset = 0;
  double? _currentTimeWindowLimitSeconds;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    for (final ScrollController controller
        in _segmentScrollControllers.values) {
      controller.dispose();
    }
    _segmentScrollControllers.clear();
    for (final ScrollController controller
        in _plotHorizontalControllers.values) {
      controller.dispose();
    }
    _plotHorizontalControllers.clear();
    super.dispose();
  }

  ScrollController _segmentScrollControllerFor(String label) {
    return _segmentScrollControllers.putIfAbsent(label, () {
      final ScrollController controller = ScrollController(
        initialScrollOffset: _sharedSegmentScrollOffset,
      );
      controller.addListener(() => _syncSegmentScrollFrom(label));
      return controller;
    });
  }

  void _pruneSegmentScrollControllers(Set<String> visibleLabels) {
    final List<String> removedLabels = _segmentScrollControllers.keys
        .where((String label) => !visibleLabels.contains(label))
        .toList(growable: false);
    for (final String label in removedLabels) {
      _segmentScrollControllers.remove(label)?.dispose();
    }
  }

  ScrollController _plotScrollControllerFor(String key) {
    return _plotHorizontalControllers.putIfAbsent(key, () {
      final ScrollController controller = ScrollController(
        initialScrollOffset: _sharedPlotScrollOffset,
      );
      controller.addListener(() => _syncPlotScrollFrom(key));
      return controller;
    });
  }

  void _prunePlotScrollControllers(Set<String> visibleKeys) {
    final List<String> removedKeys = _plotHorizontalControllers.keys
        .where((String key) => !visibleKeys.contains(key))
        .toList(growable: false);
    for (final String key in removedKeys) {
      _plotHorizontalControllers.remove(key)?.dispose();
    }
  }

  void _syncSegmentScrollFrom(String sourceLabel) {
    if (_syncingSegmentScroll) {
      return;
    }
    final ScrollController? source = _segmentScrollControllers[sourceLabel];
    if (source == null || !source.hasClients) {
      return;
    }
    final double sourceOffset = source.offset;
    _sharedSegmentScrollOffset = sourceOffset;
    _syncingSegmentScroll = true;
    try {
      for (final MapEntry<String, ScrollController> entry
          in _segmentScrollControllers.entries) {
        final ScrollController target = entry.value;
        if (entry.key == sourceLabel || !target.hasClients) {
          continue;
        }
        final double targetOffset = sourceOffset.clamp(
          target.position.minScrollExtent,
          target.position.maxScrollExtent,
        );
        if ((target.offset - targetOffset).abs() > 0.5) {
          target.jumpTo(targetOffset);
        }
      }
    } finally {
      _syncingSegmentScroll = false;
    }
  }

  void _syncPlotScrollFrom(String sourceKey) {
    if (_syncingPlotScroll) {
      return;
    }
    final ScrollController? source = _plotHorizontalControllers[sourceKey];
    if (source == null || !source.hasClients) {
      return;
    }
    final double sourceOffset = source.offset;
    _sharedPlotScrollOffset = sourceOffset;
    _syncingPlotScroll = true;
    try {
      for (final MapEntry<String, ScrollController> entry
          in _plotHorizontalControllers.entries) {
        final ScrollController target = entry.value;
        if (entry.key == sourceKey || !target.hasClients) {
          continue;
        }
        final double targetOffset = sourceOffset.clamp(
          target.position.minScrollExtent,
          target.position.maxScrollExtent,
        );
        if ((target.offset - targetOffset).abs() > 0.5) {
          target.jumpTo(targetOffset);
        }
      }
    } finally {
      _syncingPlotScroll = false;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final BuildContext? primaryContext =
        FocusManager.instance.primaryFocus?.context;
    if (primaryContext != null &&
        primaryContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool controlPressed = HardwareKeyboard.instance.isControlPressed;

    if (controlPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _stepTimeSpan(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }

    if (controlPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      _stepYScale(key == LogicalKeyboardKey.arrowUp ? 1 : -1);
      return KeyEventResult.handled;
    }

    if (!controlPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _nudgeHorizontalWindow(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _stepTimeSpan(int direction) {
    final List<double> options = _constrainedSegmentTimeSpanOptions(
      _currentTimeWindowLimitSeconds,
    );
    final double current =
        (widget.params['window_sec'] as num?)?.toDouble() ?? options[0];
    final int currentIndex = _closestViewerOptionIndex(options, current);
    final int nextIndex = (currentIndex + direction).clamp(
      0,
      options.length - 1,
    );
    setState(() {
      widget.params['window_sec'] = options[nextIndex];
    });
  }

  void _stepYScale(int direction) {
    final double current =
        (widget.params['y_scale_uv'] as num?)?.toDouble() ??
        _yScaleOptionsUv[3];
    final int currentIndex = _closestViewerOptionIndex(
      _yScaleOptionsUv,
      current,
    );
    final int nextIndex = (currentIndex + direction).clamp(
      0,
      _yScaleOptionsUv.length - 1,
    );
    setState(() {
      widget.params['y_scale_uv'] = _yScaleOptionsUv[nextIndex];
    });
  }

  void _nudgeHorizontalWindow(int direction) {
    ScrollController? controller;
    for (final ScrollController candidate
        in _plotHorizontalControllers.values) {
      if (candidate.hasClients) {
        controller = candidate;
        break;
      }
    }
    if (controller == null) {
      return;
    }
    final double viewportWidth = controller.position.viewportDimension;
    final double step = math.max(24.0, viewportWidth * 0.12);
    controller.jumpTo(
      (controller.offset + (direction * step)).clamp(
        0.0,
        controller.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SegmentedTimeSeriesData? segmented =
        widget.dataset.segmentedTimeSeries;
    if (segmented == null || segmented.segments.isEmpty) {
      return const _ChartMessage(
        title: 'No segmented data',
        body:
            'Run a Segmentation-backed path before opening the segmented viewer.',
      );
    }

    final Map<String, dynamic> params = widget.params;
    params.putIfAbsent('segmented_condition_mode', () => 'natural');
    params.putIfAbsent('segmented_channel_mode', () => 'natural');
    params.putIfAbsent('segmented_segment_mode', () => 'natural');
    params.putIfAbsent('segmented_include_bad', () => false);
    params.putIfAbsent('segmented_visible_marker_labels', () => <String>[]);
    params.putIfAbsent('segmented_marker_filter_initialized', () => false);
    params.putIfAbsent('window_sec', () => 1.0);
    params.putIfAbsent('y_scale_uv', () => 100.0);
    params.putIfAbsent('channel_spacing_factor', () => 1.0);

    final bool includeBad = params['segmented_include_bad'] as bool? ?? false;
    final Set<String> excludedLabels = _excludedSegmentationMarkerLabels(
      params['includedMarkers'],
    );
    final List<SignalSegmentData> configuredSegments = segmented.segments
        .where(
          (SignalSegmentData segment) =>
              !excludedLabels.contains(_normalizedSegmentLabel(segment)),
        )
        .toList(growable: false);
    final List<SignalSegmentData> visibleSegments = configuredSegments
        .where(
          (SignalSegmentData segment) => includeBad || !_segmentIsBad(segment),
        )
        .toList(growable: false);
    if (visibleSegments.isEmpty) {
      return const _ChartMessage(
        title: 'No visible segments',
        body:
            'All segments are currently excluded as bad. Enable "Include bad segments" to inspect them.',
      );
    }

    String conditionMode = (params['segmented_condition_mode'] ?? 'natural')
        .toString();
    final String channelMode = (params['segmented_channel_mode'] ?? 'natural')
        .toString();
    final String segmentMode = (params['segmented_segment_mode'] ?? 'natural')
        .toString();
    final bool displayBaseline = true;
    final bool baselineConfigured = _segmentationBaselineConfigured(params);
    final double baselineStartMs = baselineConfigured
        ? (params['eventBaselineStartMs'] as num?)?.toDouble() ?? -200.0
        : 0.0;
    final double baselineStopMs = baselineConfigured
        ? (params['eventBaselineStopMs'] as num?)?.toDouble() ?? 0.0
        : 0.0;
    final double windowSeconds =
        (params['window_sec'] as num?)?.toDouble() ?? _timeSpanOptionsSec[0];
    final double rangeUv =
        (params['y_scale_uv'] as num?)?.toDouble() ?? _yScaleOptionsUv[3];
    final double spacingFactor =
        (params['channel_spacing_factor'] as num?)?.toDouble() ?? 1.0;
    final List<_SegmentLabelGroup> allGroups = _segmentGroupsByLabel(
      segmented,
      visibleSegments,
    );
    final Set<String> availableLabels = allGroups
        .map((_SegmentLabelGroup group) => group.label)
        .toSet();
    final bool markerFilterInitialized =
        params['segmented_marker_filter_initialized'] as bool? ?? false;
    final List<String> rawSelectedLabels =
        (params['segmented_visible_marker_labels'] as List<dynamic>? ??
                const <dynamic>[])
            .map((dynamic value) => value.toString())
            .where(availableLabels.contains)
            .toList(growable: false);
    final Set<String> selectedLabels = markerFilterInitialized
        ? rawSelectedLabels.toSet()
        : Set<String>.from(availableLabels);
    params['segmented_visible_marker_labels'] = selectedLabels.toList(
      growable: false,
    );
    params['segmented_marker_filter_initialized'] = true;
    final List<_SegmentLabelGroup> groups = allGroups
        .where(
          (_SegmentLabelGroup group) => selectedLabels.contains(group.label),
        )
        .toList(growable: false);
    final bool stackConditionRows =
        channelMode == 'butterfly' && groups.length > 1;
    final List<_SegmentPanelConfig> panels =
        conditionMode == 'butterfly' || stackConditionRows
        ? <_SegmentPanelConfig>[
            _buildConditionOverlayPanelConfig(
              segmented: segmented,
              groups: groups,
              channelMode: channelMode,
              segmentMode: segmentMode,
              displayBaseline: displayBaseline,
              baselineStartMs: baselineStartMs,
              baselineStopMs: baselineStopMs,
              rangeUv: rangeUv,
              spacingFactor: spacingFactor,
            ),
          ]
        : groups
              .map(
                (_SegmentLabelGroup group) => _buildSingleConditionPanelConfig(
                  segmented: segmented,
                  group: group,
                  channelMode: channelMode,
                  segmentMode: segmentMode,
                  displayBaseline: displayBaseline,
                  baselineStartMs: baselineStartMs,
                  baselineStopMs: baselineStopMs,
                  rangeUv: rangeUv,
                  spacingFactor: spacingFactor,
                ),
              )
              .toList(growable: false);
    _pruneSegmentScrollControllers(
      panels.map((_SegmentPanelConfig panel) => panel.key).toSet(),
    );
    _prunePlotScrollControllers(
      panels
          .expand(
            (_SegmentPanelConfig panel) => panel.rowSpecs.map(
              (_SegmentRowSpec row) => '${panel.key}|${row.key}',
            ),
          )
          .toSet(),
    );
    final double? timeWindowLimitSeconds =
        _segmentTimeWindowLimitSecondsForPanels(panels);
    _currentTimeWindowLimitSeconds = timeWindowLimitSeconds;
    final List<double> timeOptionsSeconds = _constrainedSegmentTimeSpanOptions(
      timeWindowLimitSeconds,
    );
    final double displayedWindowSeconds = timeWindowLimitSeconds == null
        ? windowSeconds
        : math.min(windowSeconds, timeWindowLimitSeconds);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _focusNode.requestFocus(),
        child: _ChartCard(
          title: '',
          subtitle: '',
          toolbar: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _SegmentInlineToggleButton(
                    label: 'Include bad',
                    selected: includeBad,
                    onPressed: () {
                      setState(() {
                        params['segmented_include_bad'] = !includeBad;
                      });
                    },
                  ),
                  const _SegmentControlStripDivider(),
                  _SegmentViewerScaleControls(
                    timeSeconds: displayedWindowSeconds,
                    timeOptionsSeconds: timeOptionsSeconds,
                    onTimeSelected: (double value) {
                      setState(() {
                        params['window_sec'] = value;
                      });
                    },
                    rangeUv: rangeUv,
                    rangeOptionsUv: _yScaleOptionsUv,
                    onRangeSelected: (double value) {
                      setState(() {
                        params['y_scale_uv'] = value;
                      });
                    },
                    spacingFactor: spacingFactor,
                    spacingOptions: _channelSpacingOptions,
                    onSpacingSelected: (double value) {
                      setState(() {
                        params['channel_spacing_factor'] = value;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SegmentModeTileRow(
                groups: allGroups,
                selectedLabels: selectedLabels,
                includeBad: includeBad,
                conditionMode: conditionMode,
                channelMode: channelMode,
                segmentMode: segmentMode,
                selectedConditionCount: groups.length,
                totalConditionCount: allGroups.length,
                totalSegmentCount: segmented.segmentCount,
                visibleSegmentCount: visibleSegments.length,
                onConditionLabelsChanged: (Set<String> nextLabels) {
                  setState(() {
                    params['segmented_visible_marker_labels'] = nextLabels
                        .toList(growable: false);
                    params['segmented_marker_filter_initialized'] = true;
                  });
                },
                onConditionModeChanged: (String value) {
                  setState(() {
                    params['segmented_condition_mode'] = value;
                  });
                },
                onChannelModeChanged: (String value) {
                  setState(() {
                    params['segmented_channel_mode'] = value;
                  });
                },
                onSegmentModeChanged: (String value) {
                  setState(() {
                    params['segmented_segment_mode'] = value;
                  });
                },
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (groups.isEmpty || panels.isEmpty) {
                return const _ChartMessage(
                  title: 'No selected markers',
                  body:
                      'Select one or more condition chips above to show segmented data.',
                );
              }
              const double gapWidth = 12;
              const double minPanelWidth = 360;
              final double availableWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : panels.length * minPanelWidth;
              final double filledPanelWidth = panels.length == 1
                  ? availableWidth
                  : (availableWidth - (gapWidth * (panels.length - 1))) /
                        panels.length;
              final double panelWidth = math.max(
                panels.length == 1 ? availableWidth : minPanelWidth,
                filledPanelWidth,
              );
              return Scrollbar(
                thumbVisibility: panels.length * panelWidth > availableWidth,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: panels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: gapWidth),
                  itemBuilder: (BuildContext context, int index) {
                    final _SegmentPanelConfig panel = panels[index];
                    return SizedBox(
                      width: panelWidth,
                      child: _SegmentPanelView(
                        panel: panel,
                        verticalController: _segmentScrollControllerFor(
                          panel.key,
                        ),
                        horizontalControllerForRow: (String rowKey) =>
                            _plotScrollControllerFor('${panel.key}|$rowKey'),
                        windowSeconds: displayedWindowSeconds,
                        rangeUv: rangeUv,
                        onWindowSecondsChanged: (double value) {
                          setState(() {
                            params['window_sec'] = value;
                          });
                        },
                        onRangeUvChanged: (double value) {
                          setState(() {
                            params['y_scale_uv'] = value;
                          });
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SegmentPanelView extends StatelessWidget {
  const _SegmentPanelView({
    required this.panel,
    required this.verticalController,
    required this.horizontalControllerForRow,
    required this.windowSeconds,
    required this.rangeUv,
    required this.onWindowSecondsChanged,
    required this.onRangeUvChanged,
  });

  final _SegmentPanelConfig panel;
  final ScrollController verticalController;
  final ScrollController Function(String rowKey) horizontalControllerForRow;
  final double windowSeconds;
  final double rangeUv;
  final ValueChanged<double> onWindowSecondsChanged;
  final ValueChanged<double> onRangeUvChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: panel.accentColor.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 26,
                  decoration: BoxDecoration(
                    color: panel.accentColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        panel.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        panel.subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: verticalController,
                itemCount: panel.rowSpecs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final _SegmentRowSpec row = panel.rowSpecs[index];
                  return _SegmentPlotTile(
                    title: row.title,
                    height: row.height,
                    plotData: row.plotData,
                    horizontalController: horizontalControllerForRow(row.key),
                    windowSeconds: windowSeconds,
                    rangeUv: rangeUv,
                    onWindowSecondsChanged: onWindowSecondsChanged,
                    onRangeUvChanged: onRangeUvChanged,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentPlotTile extends StatelessWidget {
  const _SegmentPlotTile({
    required this.title,
    required this.height,
    required this.plotData,
    required this.horizontalController,
    required this.windowSeconds,
    required this.rangeUv,
    required this.onWindowSecondsChanged,
    required this.onRangeUvChanged,
  });

  final String title;
  final double height;
  final _SegmentSequencePlotData plotData;
  final ScrollController horizontalController;
  final double windowSeconds;
  final double rangeUv;
  final ValueChanged<double> onWindowSecondsChanged;
  final ValueChanged<double> onRangeUvChanged;

  void _handlePointerSignal(PointerSignalEvent event) {
    final ViewerScrollGesture? gesture = viewerScrollGestureFromPointerSignal(
      event,
    );
    if (gesture == null) {
      return;
    }
    switch (gesture.intent) {
      case ViewerScrollIntent.horizontalPan:
        scrollControllerBy(horizontalController, gesture.primaryDelta);
        return;
      case ViewerScrollIntent.timeZoom:
        final double factor = viewerZoomFactor(zoomingIn: gesture.zoomingIn);
        final double maximumWindowSeconds = plotData.stitchedSegments
            ? 30.0
            : math.max(0.05, (plotData.maxX - plotData.minX) / 1000.0);
        final double minimumWindowSeconds = math.min(
          0.05,
          maximumWindowSeconds,
        );
        final double currentWindowSeconds = math.min(
          windowSeconds,
          maximumWindowSeconds,
        );
        onWindowSecondsChanged(
          (currentWindowSeconds * factor).clamp(
            minimumWindowSeconds,
            maximumWindowSeconds,
          ),
        );
        return;
      case ViewerScrollIntent.amplitudeZoom:
        final double factor = viewerZoomFactor(zoomingIn: gesture.zoomingIn);
        onRangeUvChanged((rangeUv * factor).clamp(10.0, 1000.0));
        return;
      case ViewerScrollIntent.verticalPan:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: height,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (DragUpdateDetails details) {
                    scrollControllerBy(horizontalController, -details.delta.dx);
                  },
                  child: Listener(
                    onPointerSignal: _handlePointerSignal,
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final double visibleWindowMs = math.max(
                              1.0,
                              (plotData.stitchedSegments
                                      ? windowSeconds
                                      : math.min(
                                          windowSeconds,
                                          math.max(
                                            0.05,
                                            (plotData.maxX - plotData.minX) /
                                                1000.0,
                                          ),
                                        )) *
                                  1000.0,
                            );
                            final double totalSpanMs = math.max(
                              1.0,
                              plotData.maxX - plotData.minX,
                            );
                            final double widthFactor = math.max(
                              1.0,
                              totalSpanMs / visibleWindowMs,
                            );
                            final double chartWidth = math.max(
                              constraints.maxWidth,
                              constraints.maxWidth * widthFactor,
                            );
                            return Scrollbar(
                              controller: horizontalController,
                              thumbVisibility: widthFactor > 1.01,
                              notificationPredicate:
                                  (ScrollNotification notification) =>
                                      notification.metrics.axis ==
                                      Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: horizontalController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: chartWidth,
                                  height: height,
                                  child: _segmentLineChart(
                                    plotData,
                                    rangeUv: rangeUv,
                                  ),
                                ),
                              ),
                            );
                          },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _SegmentIndividualView extends StatelessWidget {
  const _SegmentIndividualView({
    required this.segmented,
    required this.visibleSegments,
    required this.by,
    required this.pageSize,
    required this.pageStart,
    required this.focusChannelIndex,
    required this.focusSegmentIndex,
  });

  final SegmentedTimeSeriesData segmented;
  final List<SignalSegmentData> visibleSegments;
  final String by;
  final int pageSize;
  final int pageStart;
  final int focusChannelIndex;
  final int focusSegmentIndex;

  @override
  Widget build(BuildContext context) {
    final List<_MiniTraceData> traces = by == 'segments'
        ? visibleSegments
              .skip(pageStart)
              .take(pageSize)
              .toList(growable: false)
              .asMap()
              .entries
              .map((MapEntry<int, SignalSegmentData> entry) {
                final int absoluteIndex = pageStart + entry.key;
                final SignalSegmentData segment = entry.value;
                return _MiniTraceData(
                  title: _segmentDisplayLabel(segment, absoluteIndex),
                  points: _segmentChannelSpots(
                    segmented,
                    segment,
                    segmented.sampleRate,
                    focusChannelIndex,
                  ),
                  color: _seriesColor(absoluteIndex),
                );
              })
              .toList(growable: false)
        : List<int>.generate(
                math.max(
                  0,
                  segmented.channelCountForSegment(
                        visibleSegments[focusSegmentIndex],
                      ) -
                      pageStart,
                ),
                (int index) => pageStart + index,
                growable: false,
              )
              .take(pageSize)
              .map(
                (int channelIndex) => _MiniTraceData(
                  title: _segmentChannelLabel(segmented, channelIndex),
                  points: _segmentChannelSpots(
                    segmented,
                    visibleSegments[focusSegmentIndex],
                    segmented.sampleRate,
                    channelIndex,
                  ),
                  color: _seriesColor(channelIndex),
                ),
              )
              .toList(growable: false);

    if (traces.isEmpty) {
      return const _ChartMessage(
        title: 'Nothing to show',
        body: 'There are no segments or channels in the selected page.',
      );
    }

    final List<double> allX = traces
        .expand(
          (_MiniTraceData trace) => trace.points.map((FlSpot spot) => spot.x),
        )
        .toList();
    final List<double> allY = traces
        .expand(
          (_MiniTraceData trace) => trace.points.map((FlSpot spot) => spot.y),
        )
        .toList();
    final double minX = allX.isEmpty ? 0.0 : allX.reduce(math.min);
    final double maxX = allX.isEmpty ? 1.0 : allX.reduce(math.max);
    final double minY = allY.isEmpty ? -1.0 : allY.reduce(math.min);
    final double maxY = allY.isEmpty ? 1.0 : allY.reduce(math.max);
    final int crossAxisCount = traces.length <= 1
        ? 1
        : traces.length <= 4
        ? 2
        : traces.length <= 9
        ? 3
        : 4;

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: traces.length,
      itemBuilder: (BuildContext context, int index) {
        final _MiniTraceData trace = traces[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  trace.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      minX: minX,
                      maxX: maxX,
                      minY: minY,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        horizontalInterval: _niceAxisStep(maxY - minY),
                        verticalInterval: _niceAxisStep(maxX - minX),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      titlesData: _chartTitles(
                        minX: minX,
                        maxX: maxX,
                        minY: minY,
                        maxY: maxY,
                        xAxisLabel: 'ms',
                        yAxisLabel: 'μV',
                        wholeNumberYLabels: true,
                      ),
                      lineBarsData: <LineChartBarData>[
                        LineChartBarData(
                          spots: trace.points,
                          isCurved: false,
                          barWidth: 1.8,
                          color: trace.color,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ignore: unused_element
class _SegmentAggregateView extends StatelessWidget {
  const _SegmentAggregateView({
    required this.segmented,
    required this.visibleSegments,
    required this.aggregateBy,
    required this.focusChannelIndex,
    required this.focusSegmentIndex,
    required this.showMean,
    required this.showTraces,
    required this.showSpread,
  });

  final SegmentedTimeSeriesData segmented;
  final List<SignalSegmentData> visibleSegments;
  final String aggregateBy;
  final int focusChannelIndex;
  final int focusSegmentIndex;
  final bool showMean;
  final bool showTraces;
  final bool showSpread;

  @override
  Widget build(BuildContext context) {
    if (!showMean && !showTraces && !showSpread) {
      return const _ChartMessage(
        title: 'Nothing to render',
        body: 'Enable at least one aggregate option: mean, traces, or spread.',
      );
    }

    if (aggregateBy == 'segments') {
      return _SegmentAggregateMontageView(
        segmented: segmented,
        visibleSegments: visibleSegments,
        showMean: showMean,
        showTraces: showTraces,
        showSpread: showSpread,
      );
    }

    final List<_AlignedTrace> traces = switch (aggregateBy) {
      'channels' => _alignedChannelTracesForSegment(
        segmented: segmented,
        segment: visibleSegments[focusSegmentIndex],
      ),
      'both' => _alignedChannelTracesForAllSegments(segmented, visibleSegments),
      _ => const <_AlignedTrace>[],
    };

    if (traces.isEmpty) {
      return const _ChartMessage(
        title: 'No aggregate data',
        body:
            'This aggregate selection did not produce any traces to summarize.',
      );
    }

    final _AggregatePlotData? plotData = _buildAggregatePlotData(
      traces,
      showMean: showMean,
      showTraces: showTraces,
      showSpread: showSpread,
    );
    if (plotData == null) {
      return const _ChartMessage(
        title: 'No aggregate data',
        body: 'The selected traces do not contain any samples.',
      );
    }

    final String aggregateLabel = switch (aggregateBy) {
      'channels' =>
        'channels in ${_segmentDisplayLabel(visibleSegments[focusSegmentIndex], focusSegmentIndex)}',
      'both' => 'all channels across all visible segments',
      _ => 'segments',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Aggregate by $aggregateLabel',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: plotData.minX,
              maxX: plotData.maxX,
              minY: plotData.minY,
              maxY: plotData.maxY,
              gridData: FlGridData(
                show: true,
                horizontalInterval: _niceAxisStep(
                  plotData.maxY - plotData.minY,
                ),
                verticalInterval: _niceAxisStep(plotData.maxX - plotData.minX),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: _chartTitles(
                minX: plotData.minX,
                maxX: plotData.maxX,
                minY: plotData.minY,
                maxY: plotData.maxY,
                xAxisLabel: 'ms',
                yAxisLabel: 'μV',
                wholeNumberYLabels: true,
              ),
              betweenBarsData: plotData.betweenBars,
              lineBarsData: plotData.lineBars,
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentAggregateMontageView extends StatelessWidget {
  const _SegmentAggregateMontageView({
    required this.segmented,
    required this.visibleSegments,
    required this.showMean,
    required this.showTraces,
    required this.showSpread,
  });

  final SegmentedTimeSeriesData segmented;
  final List<SignalSegmentData> visibleSegments;
  final bool showMean;
  final bool showTraces;
  final bool showSpread;

  @override
  Widget build(BuildContext context) {
    final int channelCount = segmented.channelLabels.isNotEmpty
        ? segmented.channelLabels.length
        : math.max(1, segmented.channelCountForSegment(visibleSegments.first));
    return ListView.separated(
      itemCount: channelCount,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int channelIndex) {
        final List<_AlignedTrace> traces = _alignedSegmentTracesForChannel(
          segmented: segmented,
          segments: visibleSegments,
          channelIndex: channelIndex,
        );
        final _AggregatePlotData? plotData = _buildAggregatePlotData(
          traces,
          showMean: showMean,
          showTraces: showTraces,
          showSpread: showSpread,
        );
        if (plotData == null) {
          return const SizedBox.shrink();
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _segmentChannelLabel(segmented, channelIndex),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 130,
                  child: LineChart(
                    LineChartData(
                      minX: plotData.minX,
                      maxX: plotData.maxX,
                      minY: plotData.minY,
                      maxY: plotData.maxY,
                      gridData: FlGridData(
                        show: true,
                        horizontalInterval: _niceAxisStep(
                          plotData.maxY - plotData.minY,
                        ),
                        verticalInterval: _niceAxisStep(
                          plotData.maxX - plotData.minX,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      titlesData: _chartTitles(
                        minX: plotData.minX,
                        maxX: plotData.maxX,
                        minY: plotData.minY,
                        maxY: plotData.maxY,
                        xAxisLabel: 'ms',
                        yAxisLabel: 'μV',
                        wholeNumberYLabels: true,
                      ),
                      betweenBarsData: plotData.betweenBars,
                      lineBarsData: plotData.lineBars,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ignore: unused_element
class _PagerChip extends StatelessWidget {
  const _PagerChip({
    required this.startIndex,
    required this.pageSize,
    required this.totalCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int startIndex;
  final int pageSize;
  final int totalCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final int start = totalCount == 0 ? 0 : startIndex + 1;
    final int stop = math.min(totalCount, startIndex + pageSize);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: Colors.white70,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '$start-$stop / $totalCount',
            style: const TextStyle(color: Colors.white70),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: Colors.white70,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _MiniTraceData {
  const _MiniTraceData({
    required this.title,
    required this.points,
    required this.color,
  });

  final String title;
  final List<FlSpot> points;
  final Color color;
}

class _AlignedTrace {
  const _AlignedTrace({required this.values, required this.xValues});

  final List<double> values;
  final List<double> xValues;
}

class _AggregatePlotData {
  const _AggregatePlotData({
    required this.lineBars,
    required this.betweenBars,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final List<LineChartBarData> lineBars;
  final List<BetweenBarsData> betweenBars;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

class _HypnogramChart extends StatelessWidget {
  const _HypnogramChart({
    required this.dataset,
    required this.params,
    required this.onChanged,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return const _ChartMessage(
        title: 'No time-domain data',
        body: 'Run an import-backed signal path before viewing sleep stages.',
      );
    }

    final List<TimeMarker> stageMarkers =
        timeSeries.markers.where(isSleepStageMarker).toList(growable: false)
          ..sort(
            (TimeMarker a, TimeMarker b) =>
                a.onsetMicros.compareTo(b.onsetMicros),
          );
    if (stageMarkers.isEmpty) {
      return const _ChartMessage(
        title: 'No sleep stages yet',
        body:
            'Run the Sleep Staging node to generate WAKE, REM, and SWS markers.',
      );
    }

    final List<String> stageLabels = sleepStagePatternFromTimeSeries(
      timeSeries,
    );
    params.putIfAbsent('hypnogram_window_sec', () => 30.0);
    final double windowSeconds =
        (params['hypnogram_window_sec'] as num?)?.toDouble() ?? 30.0;
    const List<String> preferredOrder = <String>['WAKE', 'REM', 'SWS'];
    final List<String> orderedStages = preferredOrder
        .where(stageLabels.contains)
        .followedBy(
          stageLabels.where((String label) => !preferredOrder.contains(label)),
        )
        .toList(growable: false);
    final Map<String, double> yByStage = <String, double>{
      for (int index = 0; index < orderedStages.length; index++)
        orderedStages[index]: (orderedStages.length - 1 - index).toDouble(),
    };

    final List<FlSpot> spots = <FlSpot>[];
    for (int index = 0; index < stageMarkers.length; index++) {
      final TimeMarker marker = stageMarkers[index];
      final double startSeconds = marker.onsetMicros / 1000000.0;
      final double endSeconds =
          (marker.onsetMicros + marker.durationMicros) / 1000000.0;
      final double y = yByStage[marker.label.trim().toUpperCase()] ?? 0.0;
      if (spots.isEmpty) {
        spots.add(FlSpot(startSeconds, y));
      } else {
        spots.add(FlSpot(startSeconds, spots.last.y));
        spots.add(FlSpot(startSeconds, y));
      }
      spots.add(FlSpot(endSeconds, y));
      if (index == stageMarkers.length - 1) {
        spots.add(FlSpot(endSeconds, y));
      }
    }

    final double totalSeconds = timeSeries.sampleCount / timeSeries.sampleRate;
    return _ChartCard(
      title: 'Hypnogram',
      subtitle: dataset.label,
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _PsdMenuChip<double>(
            label: 'Time',
            valueLabel: '${windowSeconds.toStringAsFixed(0)} s',
            options: _continuousViewerWindowOptionsSec,
            itemLabel: (double value) => '${value.toStringAsFixed(0)} s',
            onSelected: (double value) {
              params['hypnogram_window_sec'] = value;
              onChanged();
            },
          ),
        ],
      ),
      legend: orderedStages
          .map(
            (String label) => _SeriesData(
              label: label,
              color: _sleepStageColor(label),
              points: const <FlSpot>[],
              subtitle: 'Sleep stage',
            ),
          )
          .toList(growable: false),
      child: _SharedZoomableChartViewport(
        totalSpan: math.max(totalSeconds, spots.last.x),
        windowSpan: windowSeconds,
        windowOptions: _continuousViewerWindowOptionsSec,
        onWindowSpanChanged: (double value) {
          params['hypnogram_window_sec'] = value;
          onChanged();
        },
        builder: (double chartWidth) {
          final double fullSpan = math.max(totalSeconds, spots.last.x);
          return SizedBox(
            width: chartWidth,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: fullSpan,
                minY: -0.25,
                maxY: math.max(0.0, orderedStages.length - 1 + 0.25),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 1,
                  verticalInterval: _niceAxisStep(math.max(fullSpan, 1.0)),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Seconds',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: _niceAxisStep(math.max(fullSpan, 1.0)),
                      reservedSize: 28,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: 1,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final String label = yByStage.entries
                            .firstWhere(
                              (MapEntry<String, double> entry) =>
                                  (entry.value - value).abs() < 0.001,
                              orElse: () =>
                                  const MapEntry<String, double>('', -999),
                            )
                            .key;
                        if (label.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: _sleepStageColor(label),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: <LineChartBarData>[
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    barWidth: 2.5,
                    color: Colors.cyanAccent,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.cyanAccent.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImpedanceChart extends StatelessWidget {
  const _ImpedanceChart({
    required this.datasets,
    required this.params,
    required this.onChanged,
  });

  final List<Dataset> datasets;
  final Map<String, dynamic> params;
  final VoidCallback onChanged;

  static const List<Color> _datasetColors = <Color>[
    Color(0xFF71D4CE),
    Color(0xFFE3A25A),
    Color(0xFFC589C8),
    Color(0xFF8DBB66),
    Color(0xFF78A8D8),
    Color(0xFFD97979),
  ];

  @override
  Widget build(BuildContext context) {
    params.putIfAbsent('impedance_channel', () => '');
    params.putIfAbsent('impedance_quantity', () => 'impedance');
    params.putIfAbsent('impedance_y_scale', () => 'linear');
    params.putIfAbsent('impedance_line_mode', () => 'line');

    final List<ImpedanceData> available = datasets
        .map((Dataset dataset) => dataset.timeSeries?.impedanceData)
        .whereType<ImpedanceData>()
        .where(
          (ImpedanceData data) =>
              data.measurementCount > 0 && data.channelCount > 0,
        )
        .toList(growable: false);
    if (available.isEmpty) {
      return const _ChartMessage(
        title: 'No impedance measurements',
        body: 'Import a recording that contains impedance measurements.',
      );
    }

    final List<String> channelLabels =
        available
            .expand((ImpedanceData data) => data.channelLabels)
            .where((String label) => label.trim().isNotEmpty)
            .toSet()
            .toList(growable: true)
          ..sort();
    if (channelLabels.isEmpty) {
      return const _ChartMessage(
        title: 'No impedance channels',
        body: 'The selected datasets do not contain named impedance channels.',
      );
    }

    String channel = params['impedance_channel']?.toString() ?? '';
    if (!channelLabels.contains(channel)) {
      channel = channelLabels.first;
      params['impedance_channel'] = channel;
    }
    final bool admittance = params['impedance_quantity'] == 'admittance';
    final bool logY = params['impedance_y_scale'] == 'log';
    final String lineMode =
        <String>{
          'none',
          'line',
          'smooth',
        }.contains(params['impedance_line_mode'])
        ? params['impedance_line_mode'].toString()
        : 'line';
    params['impedance_line_mode'] = lineMode;

    final List<_SeriesData> series = <_SeriesData>[];
    for (int datasetIndex = 0; datasetIndex < datasets.length; datasetIndex++) {
      final Dataset dataset = datasets[datasetIndex];
      final ImpedanceData? data = dataset.timeSeries?.impedanceData;
      if (data == null) {
        continue;
      }
      final int channelIndex = data.channelLabels.indexOf(channel);
      if (channelIndex < 0) {
        continue;
      }
      final List<FlSpot> points = <FlSpot>[];
      for (int timeIndex = 0; timeIndex < data.measurementCount; timeIndex++) {
        final double? ohms = data.ohmsByChannel[channelIndex][timeIndex];
        if (ohms == null || !ohms.isFinite || ohms <= 0) {
          continue;
        }
        final double displayValue = admittance
            ? 1000000.0 / ohms
            : ohms / 1000.0;
        if (!displayValue.isFinite || displayValue <= 0) {
          continue;
        }
        points.add(
          FlSpot(
            data.measurementTimesMicros[timeIndex] / 1000000.0,
            logY ? math.log(displayValue) / math.ln10 : displayValue,
          ),
        );
      }
      if (points.isNotEmpty) {
        series.add(
          _SeriesData(
            label: dataset.label,
            color: _datasetColors[datasetIndex % _datasetColors.length],
            points: points,
            subtitle:
                '$channel, ${points.length} measurement${points.length == 1 ? '' : 's'}',
          ),
        );
      }
    }
    if (series.isEmpty) {
      return _ChartMessage(
        title: 'No readings for $channel',
        body:
            'Choose a channel that has impedance measurements in the selected datasets.',
      );
    }

    final List<FlSpot> allPoints = series
        .expand((_SeriesData item) => item.points)
        .toList(growable: false);
    final double rawMinX = allPoints
        .map((FlSpot point) => point.x)
        .reduce(math.min);
    final double rawMaxX = allPoints
        .map((FlSpot point) => point.x)
        .reduce(math.max);
    final double rawMinY = allPoints
        .map((FlSpot point) => point.y)
        .reduce(math.min);
    final double rawMaxY = allPoints
        .map((FlSpot point) => point.y)
        .reduce(math.max);
    final double xPadding = math.max(1.0, (rawMaxX - rawMinX).abs() * 0.06);
    final double yRange = (rawMaxY - rawMinY).abs();
    final double yPadding = yRange == 0
        ? math.max(logY ? 0.08 : 0.001, rawMinY.abs() * 0.08)
        : math.max(logY ? 0.04 : 0.001, yRange * 0.1);
    final double minX = rawMinX == rawMaxX ? rawMinX - 1 : rawMinX - xPadding;
    final double maxX = rawMinX == rawMaxX ? rawMaxX + 1 : rawMaxX + xPadding;
    final double minY = logY
        ? rawMinY - yPadding
        : math.max(0.0, rawMinY - yPadding);
    final double maxY = rawMaxY + yPadding;
    final String unit = admittance ? 'uS' : 'kOhm';
    final String yAxisLabel = logY
        ? 'log10($unit)'
        : '${admittance ? 'Admittance' : 'Impedance'} ($unit)';

    return _ChartCard(
      title: '${admittance ? 'Admittance' : 'Impedance'}: $channel',
      subtitle:
          '${series.length} dataset overlay${series.length == 1 ? '' : 's'}; markers are measured values.',
      legend: series,
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _PsdMenuChip<String>(
            label: 'Channel',
            valueLabel: channel,
            options: channelLabels,
            itemLabel: (String value) => value,
            onSelected: (String value) {
              params['impedance_channel'] = value;
              onChanged();
            },
          ),
          _PsdMenuChip<String>(
            label: 'Quantity',
            valueLabel: admittance ? 'Admittance' : 'Impedance',
            options: const <String>['impedance', 'admittance'],
            itemLabel: (String value) =>
                value == 'admittance' ? 'Admittance' : 'Impedance',
            onSelected: (String value) {
              params['impedance_quantity'] = value;
              onChanged();
            },
          ),
          _PsdMenuChip<String>(
            label: 'Y Axis',
            valueLabel: logY ? 'Log10' : 'Linear',
            options: const <String>['linear', 'log'],
            itemLabel: (String value) => value == 'log' ? 'Log10' : 'Linear',
            onSelected: (String value) {
              params['impedance_y_scale'] = value;
              onChanged();
            },
          ),
          _PsdMenuChip<String>(
            label: 'Line',
            valueLabel: switch (lineMode) {
              'none' => 'Points',
              'smooth' => 'Smooth',
              _ => 'Straight',
            },
            options: const <String>['none', 'line', 'smooth'],
            itemLabel: (String value) => switch (value) {
              'none' => 'Points only',
              'smooth' => 'Smooth spline',
              _ => 'Straight',
            },
            onSelected: (String value) {
              params['impedance_line_mode'] = value;
              onChanged();
            },
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            horizontalInterval: _niceAxisStep(maxY - minY),
            verticalInterval: _niceAxisStep(maxX - minX),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: _chartTitles(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            logY: logY,
            xAxisLabel: 'Time (s)',
            yAxisLabel: yAxisLabel,
            yAxisReservedSize: 64,
          ),
          lineBarsData: series
              .map((_SeriesData item) {
                final bool drawLine =
                    lineMode != 'none' && item.points.length > 1;
                return LineChartBarData(
                  spots: item.points,
                  isCurved: lineMode == 'smooth' && item.points.length > 2,
                  preventCurveOverShooting: true,
                  curveSmoothness: 0.22,
                  barWidth: drawLine ? 2.2 : 0,
                  color: item.color,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter:
                        (FlSpot _, double __, LineChartBarData ___, int ____) =>
                            FlDotCirclePainter(
                              radius: 4.2,
                              color: item.color,
                              strokeWidth: 1.4,
                              strokeColor: Colors.white,
                            ),
                  ),
                );
              })
              .toList(growable: false),
          clipData: const FlClipData.all(),
        ),
      ),
    );
  }
}

Map<String, List<double>> _psdConditionPowers(
  Dataset dataset,
  FrequencySpectrumData spectrum,
  int channelIndex,
) {
  final List<double> channelPower = channelIndex < spectrum.channelPowers.length
      ? spectrum.channelPowers[channelIndex]
      : channelIndex == 0
      ? spectrum.power
      : const <double>[];
  final List<List<double>> channelSegmentPowers =
      channelIndex < spectrum.channelSegmentPowers.length
      ? spectrum.channelSegmentPowers[channelIndex]
      : channelIndex == 0
      ? spectrum.segmentPowers
      : const <List<double>>[];
  final List<SignalSegmentData> segments =
      dataset.segmentedTimeSeries?.segments ?? const <SignalSegmentData>[];
  if (channelSegmentPowers.isEmpty ||
      segments.length != channelSegmentPowers.length) {
    return <String, List<double>>{'All segments': channelPower};
  }

  final Map<String, List<List<double>>> grouped =
      <String, List<List<double>>>{};
  for (int index = 0; index < segments.length; index++) {
    grouped
        .putIfAbsent(
          _normalizedSegmentLabel(segments[index]),
          () => <List<double>>[],
        )
        .add(channelSegmentPowers[index]);
  }
  return grouped.map((String label, List<List<double>> powers) {
    final int binCount = powers
        .map((List<double> values) => values.length)
        .fold<int>(powers.first.length, math.min);
    final List<double> mean = List<double>.filled(binCount, 0.0);
    for (final List<double> values in powers) {
      for (int index = 0; index < binCount; index++) {
        mean[index] += values[index];
      }
    }
    for (int index = 0; index < binCount; index++) {
      mean[index] /= powers.length;
    }
    return MapEntry<String, List<double>>(label, mean);
  });
}

class _PsdChart extends StatelessWidget {
  const _PsdChart({
    required this.datasets,
    required this.params,
    required this.onChanged,
  });

  final List<Dataset> datasets;
  final Map<String, dynamic> params;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    params.putIfAbsent('psd_view_max_hz', () => 40.0);
    params.putIfAbsent('psd_view_scale_mode', () => 'auto');
    params.putIfAbsent('psd_view_max_power', () => 10.0);
    params.putIfAbsent('psd_view_log_y', () => true);
    params.putIfAbsent('psd_condition_mode', () => 'separate');
    params.putIfAbsent('psd_channel_index', () => 0);

    final int channelCount = datasets
        .map((Dataset dataset) {
          final FrequencySpectrumData? spectrum = dataset.spectrum;
          if (spectrum == null) {
            return 0;
          }
          return math.max(
            spectrum.channelPowers.length,
            spectrum.power.isEmpty ? 0 : 1,
          );
        })
        .fold<int>(0, math.max);
    final int selectedChannelIndex = channelCount == 0
        ? 0
        : ((params['psd_channel_index'] as num?)?.toInt() ?? 0).clamp(
            0,
            channelCount - 1,
          );
    params['psd_channel_index'] = selectedChannelIndex;
    FrequencySpectrumData? labelSpectrum;
    for (final Dataset dataset in datasets) {
      if (dataset.spectrum != null) {
        labelSpectrum = dataset.spectrum;
        break;
      }
    }
    final List<String> channelLabels = List<String>.generate(
      channelCount,
      (int index) =>
          labelSpectrum != null && index < labelSpectrum.channelLabels.length
          ? labelSpectrum.channelLabels[index]
          : 'Channel ${index + 1}',
      growable: false,
    );

    final double windowHz =
        (params['psd_view_max_hz'] as num?)?.toDouble() ?? 40.0;
    final bool logY = params['psd_view_log_y'] as bool? ?? false;
    final Map<String, List<_SeriesData>> seriesByCondition =
        <String, List<_SeriesData>>{};
    int seriesIndex = 0;
    for (int datasetIndex = 0; datasetIndex < datasets.length; datasetIndex++) {
      final Dataset dataset = datasets[datasetIndex];
      final FrequencySpectrumData? spectrum = dataset.spectrum;
      final List<double>? freqs = spectrum?.frequencies;
      if (freqs == null || freqs.isEmpty || spectrum == null) {
        continue;
      }
      final Map<String, List<double>> conditionPowers = _psdConditionPowers(
        dataset,
        spectrum,
        selectedChannelIndex,
      );
      for (final MapEntry<String, List<double>> entry
          in conditionPowers.entries) {
        final int count = math.min(freqs.length, entry.value.length);
        final List<FlSpot> points = <FlSpot>[];
        for (int i = 0; i < count; i++) {
          final double sourcePower = entry.value[i];
          final double plotPower = logY
              ? math.log((sourcePower <= 0 ? 1.0e-12 : sourcePower)) / math.ln10
              : sourcePower;
          points.add(FlSpot(freqs[i], plotPower));
        }
        if (points.isEmpty) {
          continue;
        }
        final String condition = entry.key;
        seriesByCondition
            .putIfAbsent(condition, () => <_SeriesData>[])
            .add(
              _SeriesData(
                label: datasets.length == 1 ? condition : dataset.label,
                color: _seriesColor(seriesIndex++),
                points: points,
                subtitle: '$count bins',
              ),
            );
      }
    }

    final List<_SeriesData> series = seriesByCondition.values
        .expand((List<_SeriesData> values) => values)
        .toList(growable: false);

    if (series.isEmpty) {
      return const _ChartMessage(
        title: 'No PSD data',
        body: 'Run a PSD node upstream, then run the visualization node again.',
      );
    }

    final List<double> allY = series
        .expand((_SeriesData s) => s.points.map((FlSpot p) => p.y))
        .toList();
    final List<double> allX = series
        .expand((_SeriesData s) => s.points.map((FlSpot p) => p.x))
        .toList();
    final String scaleMode = (params['psd_view_scale_mode'] ?? 'auto')
        .toString();
    final double configuredMaxPower =
        (params['psd_view_max_power'] as num?)?.toDouble() ?? 10.0;
    final double dataMinY = allY.reduce(math.min);
    final double dataMaxY = allY.reduce(math.max);
    final double minY = math.min(0.0, dataMinY);
    final double maxY = scaleMode == 'fixed'
        ? math.max(configuredMaxPower, minY + 0.001)
        : math.max(dataMaxY * 1.1, minY + 0.001);
    final double maxX = allX.reduce(math.max);
    final String conditionMode = (params['psd_condition_mode'] ?? 'separate')
        .toString();
    final bool separateConditions =
        seriesByCondition.length > 1 && conditionMode == 'separate';

    LineChart buildLineChart(List<_SeriesData> visibleSeries) {
      return LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            horizontalInterval: _niceAxisStep(maxY - minY),
            verticalInterval: _niceAxisStep(maxX),
          ),
          rangeAnnotations: RangeAnnotations(
            verticalRangeAnnotations: _canonicalBandAnnotations(maxX),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _chartTitles(
            minX: 0,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            logY: logY,
            yAxisReservedSize: 84,
          ),
          clipData: const FlClipData.all(),
          lineBarsData: visibleSeries
              .map(
                (_SeriesData seriesData) => LineChartBarData(
                  spots: seriesData.points,
                  isCurved: false,
                  barWidth: 2,
                  color: seriesData.color,
                  dotData: const FlDotData(show: false),
                ),
              )
              .toList(),
        ),
      );
    }

    return _ChartCard(
      title: 'PSD',
      subtitle: '${series.length} overlay${series.length == 1 ? '' : 's'}',
      legend: series,
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          if (channelCount > 1)
            _PsdMenuChip<int>(
              label: 'Channel',
              valueLabel: channelLabels[selectedChannelIndex],
              options: List<int>.generate(channelCount, (int index) => index),
              itemLabel: (int index) => channelLabels[index],
              onSelected: (int value) {
                params['psd_channel_index'] = value;
                onChanged();
              },
            ),
          _PsdMenuChip<double>(
            label: 'Range',
            valueLabel: '${windowHz.toStringAsFixed(0)} Hz',
            options: _psdWindowOptionsHz,
            itemLabel: (double value) => '${value.toStringAsFixed(0)} Hz',
            onSelected: (double value) {
              params['psd_view_max_hz'] = value;
              onChanged();
            },
          ),
          _PsdMenuChip<String>(
            label: 'Scale',
            valueLabel: scaleMode == 'fixed'
                ? '${configuredMaxPower.toStringAsFixed(1)} uV^2/Hz'
                : 'Auto',
            options: const <String>['auto', 'fixed'],
            itemLabel: (String value) => value == 'auto' ? 'Auto' : 'Fixed',
            onSelected: (String value) {
              params['psd_view_scale_mode'] = value;
              onChanged();
            },
          ),
          if (scaleMode == 'fixed')
            _PsdMenuChip<double>(
              label: 'Max',
              valueLabel: '${configuredMaxPower.toStringAsFixed(1)} uV^2/Hz',
              options: const <double>[0.1, 0.5, 1, 2, 5, 10, 20, 50, 100, 200],
              itemLabel: (double value) =>
                  '${value.toStringAsFixed(value < 1 ? 1 : 0)} uV^2/Hz',
              onSelected: (double value) {
                params['psd_view_max_power'] = value;
                onChanged();
              },
            ),
          _PsdMenuChip<bool>(
            label: 'Y Axis',
            valueLabel: logY ? 'Log10' : 'Linear',
            options: const <bool>[false, true],
            itemLabel: (bool value) => value ? 'Log10' : 'Linear',
            onSelected: (bool value) {
              params['psd_view_log_y'] = value;
              onChanged();
            },
          ),
          if (seriesByCondition.length > 1)
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'separate',
                  label: Text('Separate'),
                ),
                ButtonSegment<String>(value: 'overlay', label: Text('Overlay')),
              ],
              selected: <String>{conditionMode},
              onSelectionChanged: (Set<String> selection) {
                params['psd_condition_mode'] = selection.first;
                onChanged();
              },
            ),
        ],
      ),
      child: _SharedZoomableChartViewport(
        totalSpan: maxX,
        windowSpan: windowHz,
        windowOptions: _psdWindowOptionsHz,
        onWindowSpanChanged: (double value) {
          params['psd_view_max_hz'] = value;
          onChanged();
        },
        yScale: configuredMaxPower,
        yScaleOptions: _psdMaxPowerOptions,
        onYScaleChanged: (double value) {
          params['psd_view_scale_mode'] = 'fixed';
          params['psd_view_max_power'] = value;
          onChanged();
        },
        yScaleEnabled: true,
        builder: (double chartWidth) {
          return SizedBox(
            width: chartWidth,
            child: separateConditions
                ? LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final double panelHeight = math.max(
                            220,
                            (constraints.maxHeight -
                                    (12 * (seriesByCondition.length - 1))) /
                                seriesByCondition.length,
                          );
                          return ListView.separated(
                            itemCount: seriesByCondition.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (BuildContext context, int index) {
                              final MapEntry<String, List<_SeriesData>> group =
                                  seriesByCondition.entries.elementAt(index);
                              return SizedBox(
                                height: panelHeight,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      group.key,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: buildLineChart(group.value),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                  )
                : buildLineChart(series),
          );
        },
      ),
    );
  }
}

class _BridgeHeatmapChart extends StatefulWidget {
  const _BridgeHeatmapChart({
    required this.dataset,
    required this.params,
    required this.onChanged,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback onChanged;

  @override
  State<_BridgeHeatmapChart> createState() => _BridgeHeatmapChartState();
}

class _BridgeHeatmapChartState extends State<_BridgeHeatmapChart> {
  int? _selectedMinuteIndex;
  String _channelOrderMode = 'data';
  final Map<String, List<int>> _covarianceOrderCache = <String, List<int>>{};

  @override
  void didUpdateWidget(covariant _BridgeHeatmapChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataset.id != widget.dataset.id) {
      _selectedMinuteIndex = null;
      _channelOrderMode = 'data';
    }
  }

  @override
  Widget build(BuildContext context) {
    final BridgeDetectionData? bridge = widget.dataset.bridgeDetection;
    if (bridge == null || bridge.frames.isEmpty) {
      return const _ChartMessage(
        title: 'No bridge data',
        body:
            'Run Bridge Detector upstream to compute minute-by-minute channel correlations.',
      );
    }

    final int resolvedMinuteIndex = _resolveMinuteIndex(bridge);
    final BridgeCorrelationFrameData frame = bridge.frames[resolvedMinuteIndex];
    final String minuteLabel = 'Minute ${frame.minuteIndex + 1}';
    final double startSeconds = frame.startSample / bridge.sampleRate;
    final double stopSeconds = frame.endSampleExclusive / bridge.sampleRate;
    final List<int> channelOrder = _channelOrderMode == 'covariance'
        ? _covarianceOrderForBridge(widget.dataset.id, bridge)
        : List<int>.generate(
            bridge.channelCount,
            (int index) => index,
            growable: false,
          );

    return _ChartCard(
      title: 'Bridge Detector',
      subtitle:
          '${widget.dataset.label} • ${bridge.channelCount} ch • ${bridge.frameCount} minute frame(s)',
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'data', label: Text('Data Order')),
              ButtonSegment<String>(
                value: 'covariance',
                label: Text('Covariance Order'),
              ),
            ],
            selected: <String>{_channelOrderMode},
            onSelectionChanged: (Set<String> selection) {
              setState(() {
                _channelOrderMode = selection.first;
              });
            },
          ),
          _PsdMenuChip<int>(
            label: 'Minute',
            valueLabel: minuteLabel,
            options: List<int>.generate(
              bridge.frames.length,
              (int index) => index,
              growable: false,
            ),
            itemLabel: (int index) =>
                'Minute ${bridge.frames[index].minuteIndex + 1}',
            onSelected: (int index) {
              setState(() {
                _selectedMinuteIndex = index;
              });
            },
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${startSeconds.toStringAsFixed(1)}s - ${stopSeconds.toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _BridgeHeatmap(
              frame: frame,
              channelLabels: bridge.channelLabels,
              channelOrder: channelOrder,
            ),
          ),
          const SizedBox(height: 10),
          const _BridgeScaleLegend(),
        ],
      ),
    );
  }

  int _resolveMinuteIndex(BridgeDetectionData bridge) {
    if (_selectedMinuteIndex == null) {
      return 0;
    }
    return _selectedMinuteIndex!.clamp(0, bridge.frames.length - 1);
  }

  List<int> _covarianceOrderForBridge(
    String datasetId,
    BridgeDetectionData bridge,
  ) {
    final String cacheKey =
        '$datasetId:${bridge.channelCount}:${bridge.frameCount}:${bridge.valueCount}:${bridge.windowSampleCount}:${bridge.sampleRate}';
    final List<int>? cached = _covarianceOrderCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final List<int> order = _computeCovarianceOrdering(bridge);
    _covarianceOrderCache[cacheKey] = order;
    return order;
  }
}

class _BridgeHeatmap extends StatelessWidget {
  const _BridgeHeatmap({
    required this.frame,
    required this.channelLabels,
    required this.channelOrder,
  });

  final BridgeCorrelationFrameData frame;
  final List<String> channelLabels;
  final List<int> channelOrder;

  @override
  Widget build(BuildContext context) {
    final int matrixSize = frame.correlationMatrix.length;
    if (matrixSize == 0) {
      return const _ChartMessage(
        title: 'No heatmap data',
        body:
            'This bridge-detection frame does not contain a correlation matrix.',
      );
    }

    final List<String> labels = channelLabels.length == matrixSize
        ? channelLabels
        : List<String>.generate(
            matrixSize,
            (int index) => 'Ch ${index + 1}',
            growable: false,
          );
    final List<int> resolvedOrder = channelOrder.length == matrixSize
        ? channelOrder
        : List<int>.generate(matrixSize, (int index) => index, growable: false);
    final List<String> orderedLabels = resolvedOrder
        .map((int index) => labels[index])
        .toList(growable: false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double axisLabelSpace = 56;
        final double availableWidth = math.max(
          120.0,
          constraints.maxWidth - axisLabelSpace,
        );
        final double availableHeight = math.max(
          120.0,
          constraints.maxHeight - axisLabelSpace,
        );
        final double heatmapSize = math.min(availableWidth, availableHeight);

        return Center(
          child: SizedBox(
            width: heatmapSize + axisLabelSpace,
            height: heatmapSize + axisLabelSpace,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: axisLabelSpace,
                  top: 0,
                  width: heatmapSize,
                  height: axisLabelSpace,
                  child: _BridgeTopLabels(
                    labels: orderedLabels,
                    cellExtent: heatmapSize / matrixSize,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: axisLabelSpace,
                  width: axisLabelSpace,
                  height: heatmapSize,
                  child: _BridgeSideLabels(
                    labels: orderedLabels,
                    cellExtent: heatmapSize / matrixSize,
                  ),
                ),
                Positioned(
                  left: axisLabelSpace,
                  top: axisLabelSpace,
                  width: heatmapSize,
                  height: heatmapSize,
                  child: CustomPaint(
                    painter: _BridgeHeatmapPainter(
                      matrix: frame.correlationMatrix,
                      channelOrder: resolvedOrder,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BridgeTopLabels extends StatelessWidget {
  const _BridgeTopLabels({required this.labels, required this.cellExtent});

  final List<String> labels;
  final double cellExtent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List<Widget>.generate(labels.length, (int index) {
        return Positioned(
          left: index * cellExtent,
          top: 0,
          width: cellExtent,
          height: 56,
          child: Center(
            child: Transform.rotate(
              angle: -math.pi / 4,
              child: Text(
                labels[index],
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _BridgeSideLabels extends StatelessWidget {
  const _BridgeSideLabels({required this.labels, required this.cellExtent});

  final List<String> labels;
  final double cellExtent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List<Widget>.generate(labels.length, (int index) {
        return Positioned(
          left: 0,
          top: index * cellExtent,
          width: 56,
          height: cellExtent,
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                labels[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _BridgeHeatmapPainter extends CustomPainter {
  const _BridgeHeatmapPainter({
    required this.matrix,
    required this.channelOrder,
  });

  final List<List<double>> matrix;
  final List<int> channelOrder;

  @override
  void paint(Canvas canvas, Size size) {
    final int count = matrix.length;
    if (count == 0) {
      return;
    }

    final double cellWidth = size.width / count;
    final double cellHeight = size.height / count;
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 0.5;

    for (int row = 0; row < count; row++) {
      final int sourceRow = channelOrder[row];
      final List<double> values = matrix[sourceRow];
      for (int column = 0; column < math.min(count, values.length); column++) {
        final int sourceColumn = channelOrder[column];
        fillPaint.color = _bridgeCorrelationColor(values[sourceColumn]);
        final Rect rect = Rect.fromLTWH(
          column * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
      }
    }

    final Paint outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;
    canvas.drawRect(Offset.zero & size, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _BridgeHeatmapPainter oldDelegate) {
    return oldDelegate.matrix != matrix ||
        oldDelegate.channelOrder != channelOrder;
  }
}

class _BridgeScaleLegend extends StatelessWidget {
  const _BridgeScaleLegend();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Correlation',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xFF215DFF),
                Color(0xFFF4F6FB),
                Color(0xFFD62939),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('-1', style: TextStyle(color: Colors.white70, fontSize: 11)),
            Text('0', style: TextStyle(color: Colors.white70, fontSize: 11)),
            Text('1', style: TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

bool _segmentIsBad(SignalSegmentData segment) {
  final String label = segment.label.trim().toLowerCase();
  final String kind = segment.kind.trim().toLowerCase();
  return label.contains('bad') ||
      label.contains('artifact') ||
      label.contains('reject') ||
      kind.contains('bad') ||
      kind.contains('artifact') ||
      kind.contains('reject');
}

class _SegmentLabelGroup {
  const _SegmentLabelGroup({
    required this.label,
    required this.segments,
    required this.color,
  });

  final String label;
  final List<SignalSegmentData> segments;
  final Color color;
}

class _SegmentSequencePlotData {
  const _SegmentSequencePlotData({
    required this.lineBars,
    this.betweenBars = const <BetweenBarsData>[],
    required this.dividers,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    this.stitchedSegments = false,
    this.fitYToData = false,
    this.yAxisLabels = const <_SegmentYAxisLabel>[],
  });

  final List<LineChartBarData> lineBars;
  final List<BetweenBarsData> betweenBars;
  final List<VerticalRangeAnnotation> dividers;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final bool stitchedSegments;
  final bool fitYToData;
  final List<_SegmentYAxisLabel> yAxisLabels;
}

class _SegmentYAxisLabel {
  const _SegmentYAxisLabel({required this.position, required this.label});

  final double position;
  final String label;
}

class _SegmentRowSpec {
  const _SegmentRowSpec({
    required this.key,
    required this.title,
    required this.plotData,
    required this.height,
  });

  final String key;
  final String title;
  final _SegmentSequencePlotData plotData;
  final double height;
}

class _SegmentPanelConfig {
  const _SegmentPanelConfig({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.rowSpecs,
  });

  final String key;
  final String title;
  final String subtitle;
  final Color accentColor;
  final List<_SegmentRowSpec> rowSpecs;
}

double? _segmentTimeWindowLimitSecondsForPanels(
  List<_SegmentPanelConfig> panels,
) {
  double? limitSeconds;
  for (final _SegmentPanelConfig panel in panels) {
    for (final _SegmentRowSpec row in panel.rowSpecs) {
      if (row.plotData.stitchedSegments) {
        continue;
      }
      final double spanSeconds = math.max(
        0.001,
        (row.plotData.maxX - row.plotData.minX) / 1000.0,
      );
      limitSeconds = limitSeconds == null
          ? spanSeconds
          : math.min(limitSeconds, spanSeconds);
    }
  }
  return limitSeconds;
}

List<double> _constrainedSegmentTimeSpanOptions(double? limitSeconds) {
  if (limitSeconds == null || !limitSeconds.isFinite) {
    return _SegmentedChartState._timeSpanOptionsSec;
  }
  final double boundedLimit = limitSeconds.clamp(0.05, 30.0);
  final List<double> options = _SegmentedChartState._timeSpanOptionsSec
      .where((double option) => option <= boundedLimit + 0.001)
      .toList(growable: true);
  if (options.isEmpty || (options.last - boundedLimit).abs() > 0.001) {
    options.add(boundedLimit);
  }
  return options;
}

class _SegmentAggregateSeriesInput {
  const _SegmentAggregateSeriesInput({
    required this.traces,
    required this.lineColor,
    required this.fillColor,
    this.barWidth = 2.0,
    this.showSpread = true,
  });

  final List<_AlignedTrace> traces;
  final Color lineColor;
  final Color fillColor;
  final double barWidth;
  final bool showSpread;
}

List<_SegmentLabelGroup> _segmentGroupsByLabel(
  SegmentedTimeSeriesData segmented,
  List<SignalSegmentData> segments,
) {
  final Map<String, List<SignalSegmentData>> grouped =
      <String, List<SignalSegmentData>>{};
  for (final SignalSegmentData segment in segments) {
    final String label = segment.label.trim().isEmpty
        ? 'Unlabeled'
        : segment.label.trim();
    grouped.putIfAbsent(label, () => <SignalSegmentData>[]).add(segment);
  }
  int index = 0;
  return grouped.entries
      .map((MapEntry<String, List<SignalSegmentData>> entry) {
        return _SegmentLabelGroup(
          label: entry.key,
          segments: entry.value,
          color: _segmentLabelColor(entry.key, index++),
        );
      })
      .toList(growable: false);
}

Set<String> _excludedSegmentationMarkerLabels(dynamic rawIncludedMarkers) {
  final Map<String, dynamic> includedMarkers = Map<String, dynamic>.from(
    rawIncludedMarkers as Map? ?? const <String, dynamic>{},
  );
  if (includedMarkers.isEmpty) {
    return const <String>{};
  }
  return includedMarkers.entries
      .where((MapEntry<String, dynamic> entry) => !_truthyBool(entry.value))
      .map((MapEntry<String, dynamic> entry) {
        final String key = entry.key.trim();
        final int separatorIndex = key.indexOf('|');
        final String label = separatorIndex < 0
            ? key
            : key.substring(separatorIndex + 1).trim();
        return label.isEmpty ? 'Unlabeled' : label;
      })
      .toSet();
}

bool _truthyBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.trim().toLowerCase() != 'false';
  }
  return true;
}

String _normalizedSegmentLabel(SignalSegmentData segment) {
  final String label = segment.label.trim();
  return label.isEmpty ? 'Unlabeled' : label;
}

bool _segmentationBaselineConfigured(Map<String, dynamic> params) {
  final bool explicit = params['eventBaselineConfigured'] as bool? ?? false;
  if (explicit) {
    return true;
  }
  final double startMs =
      (params['eventBaselineStartMs'] as num?)?.toDouble() ?? -200.0;
  final double stopMs =
      (params['eventBaselineStopMs'] as num?)?.toDouble() ?? 0.0;
  return (startMs - (-200.0)).abs() > 0.001 || stopMs.abs() > 0.001;
}

const int _segmentPreviewMaxPoints = 360;
const int _segmentAverageMaxPoints = 640;
final Expando<Map<String, List<double>>> _segmentDisplayValueCache =
    Expando<Map<String, List<double>>>('segmentDisplayValueCache');

int _segmentGroupChannelCount(
  SegmentedTimeSeriesData segmented,
  List<SignalSegmentData> segments,
) {
  if (segmented.channelLabels.isNotEmpty) {
    return segmented.channelLabels.length;
  }
  int channelCount = 0;
  for (final SignalSegmentData segment in segments) {
    channelCount = math.max(
      channelCount,
      segmented.channelCountForSegment(segment),
    );
  }
  return math.max(1, channelCount);
}

_SegmentPanelConfig _buildSingleConditionPanelConfig({
  required SegmentedTimeSeriesData segmented,
  required _SegmentLabelGroup group,
  required String channelMode,
  required String segmentMode,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
  required double rangeUv,
  required double spacingFactor,
}) {
  final int channelCount = _segmentGroupChannelCount(segmented, group.segments);
  final List<_SegmentRowSpec> rows = <_SegmentRowSpec>[];
  final double summaryRowHeight = _segmentRowHeight(
    rangeUv: rangeUv,
    spacingFactor: spacingFactor,
    naturalChannels: false,
  );

  if (channelMode == 'natural') {
    rows.add(
      _SegmentRowSpec(
        key: 'channels:stacked',
        title: 'Stacked channels',
        plotData: _buildStackedChannelsSegmentPlotData(
          segmented: segmented,
          segments: group.segments,
          channelCount: channelCount,
          segmentMode: segmentMode,
          color: group.color,
          displayBaseline: displayBaseline,
          baselineStartMs: baselineStartMs,
          baselineStopMs: baselineStopMs,
          rangeUv: rangeUv,
          spacingFactor: spacingFactor,
        ),
        height: _segmentStackedChannelsRowHeight(
          channelCount: channelCount,
          rangeUv: rangeUv,
          spacingFactor: spacingFactor,
        ),
      ),
    );
  } else if (channelMode == 'butterfly') {
    final _SegmentSequencePlotData plotData = switch (segmentMode) {
      'butterfly' => _buildSegmentButterflyChannelsAndSegmentsPlotData(
        segmented: segmented,
        segments: group.segments,
        color: group.color,
        displayBaseline: displayBaseline,
        baselineStartMs: baselineStartMs,
        baselineStopMs: baselineStopMs,
      ),
      'average' => _buildSegmentAggregatePlotData(
        List<_SegmentAggregateSeriesInput>.generate(
          channelCount,
          (int channelIndex) => _SegmentAggregateSeriesInput(
            traces: _alignedDisplayedSegmentTracesForChannel(
              segmented: segmented,
              segments: group.segments,
              channelIndex: channelIndex,
              displayBaseline: displayBaseline,
              baselineStartMs: baselineStartMs,
              baselineStopMs: baselineStopMs,
            ),
            lineColor: _channelOverlayColor(group.color, channelIndex),
            fillColor: _channelOverlayColor(
              group.color,
              channelIndex,
            ).withValues(alpha: 0.10),
          ),
          growable: false,
        ),
      ),
      _ => _buildSegmentSequencePlotData(
        segmented: segmented,
        segments: group.segments,
        channelIndex: 0,
        color: group.color,
        overlayChannels: true,
        displayBaseline: displayBaseline,
        baselineStartMs: baselineStartMs,
        baselineStopMs: baselineStopMs,
      ),
    };
    rows.add(
      _SegmentRowSpec(
        key: 'channels:all',
        title: segmentMode == 'average'
            ? 'Channels (mean across segments)'
            : segmentMode == 'butterfly'
            ? 'Channels x segments'
            : 'Channels',
        plotData: plotData,
        height: summaryRowHeight,
      ),
    );
  } else {
    final _SegmentSequencePlotData plotData = switch (segmentMode) {
      'butterfly' => _buildAverageChannelsButterflySegmentsPlotData(
        segmented: segmented,
        segments: group.segments,
        color: group.color,
        displayBaseline: displayBaseline,
        baselineStartMs: baselineStartMs,
        baselineStopMs: baselineStopMs,
      ),
      'average' =>
        _buildSegmentAggregatePlotData(<_SegmentAggregateSeriesInput>[
          _SegmentAggregateSeriesInput(
            traces: _alignedAverageChannelsTracesForSegments(
              segmented: segmented,
              segments: group.segments,
              displayBaseline: displayBaseline,
              baselineStartMs: baselineStartMs,
              baselineStopMs: baselineStopMs,
            ),
            lineColor: group.color,
            fillColor: group.color.withValues(alpha: 0.14),
          ),
        ]),
      _ => _buildAverageChannelsStitchedPlotData(
        segmented: segmented,
        segments: group.segments,
        color: group.color,
        displayBaseline: displayBaseline,
        baselineStartMs: baselineStartMs,
        baselineStopMs: baselineStopMs,
      ),
    };
    rows.add(
      _SegmentRowSpec(
        key: 'channels:mean',
        title: 'Mean across channels',
        plotData: plotData,
        height: summaryRowHeight,
      ),
    );
  }

  return _SegmentPanelConfig(
    key: group.label,
    title: group.label,
    subtitle:
        '${group.segments.length} segment${group.segments.length == 1 ? '' : 's'}',
    accentColor: group.color,
    rowSpecs: rows,
  );
}

_SegmentPanelConfig _buildConditionOverlayPanelConfig({
  required SegmentedTimeSeriesData segmented,
  required List<_SegmentLabelGroup> groups,
  required String channelMode,
  required String segmentMode,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
  required double rangeUv,
  required double spacingFactor,
}) {
  final int channelCount = groups.fold<int>(
    0,
    (int maxCount, _SegmentLabelGroup group) => math.max(
      maxCount,
      _segmentGroupChannelCount(segmented, group.segments),
    ),
  );
  final List<_SegmentRowSpec> rows = <_SegmentRowSpec>[];
  final double summaryRowHeight = _segmentRowHeight(
    rangeUv: rangeUv,
    spacingFactor: spacingFactor,
    naturalChannels: false,
  );

  if (channelMode == 'natural') {
    rows.add(
      _SegmentRowSpec(
        key: 'condition-overlay:stacked',
        title: 'Stacked channels',
        plotData: _buildStackedChannelsConditionOverlayPlotData(
          segmented: segmented,
          groups: groups,
          channelCount: channelCount,
          displayBaseline: displayBaseline,
          baselineStartMs: baselineStartMs,
          baselineStopMs: baselineStopMs,
          rangeUv: rangeUv,
          spacingFactor: spacingFactor,
        ),
        height: _segmentStackedChannelsRowHeight(
          channelCount: channelCount,
          rangeUv: rangeUv,
          spacingFactor: spacingFactor,
        ),
      ),
    );
  } else if (channelMode == 'butterfly') {
    final List<_SegmentSequencePlotData> conditionPlots = groups
        .map((_SegmentLabelGroup group) {
          final int groupChannelCount = _segmentGroupChannelCount(
            segmented,
            group.segments,
          );
          return switch (segmentMode) {
            'butterfly' => _buildSegmentButterflyChannelsAndSegmentsPlotData(
              segmented: segmented,
              segments: group.segments,
              color: group.color,
              displayBaseline: displayBaseline,
              baselineStartMs: baselineStartMs,
              baselineStopMs: baselineStopMs,
            ),
            'average' => _buildSegmentAggregatePlotData(
              List<_SegmentAggregateSeriesInput>.generate(
                groupChannelCount,
                (int channelIndex) => _SegmentAggregateSeriesInput(
                  traces: _alignedDisplayedSegmentTracesForChannel(
                    segmented: segmented,
                    segments: group.segments,
                    channelIndex: channelIndex,
                    displayBaseline: displayBaseline,
                    baselineStartMs: baselineStartMs,
                    baselineStopMs: baselineStopMs,
                  ),
                  lineColor: _channelOverlayColor(group.color, channelIndex),
                  fillColor: _channelOverlayColor(
                    group.color,
                    channelIndex,
                  ).withValues(alpha: 0.08),
                  showSpread: false,
                  barWidth: 1.5,
                ),
                growable: false,
              ),
            ),
            _ => _buildSegmentSequencePlotData(
              segmented: segmented,
              segments: group.segments,
              channelIndex: 0,
              color: group.color,
              overlayChannels: true,
              displayBaseline: displayBaseline,
              baselineStartMs: baselineStartMs,
              baselineStopMs: baselineStopMs,
            ),
          };
        })
        .toList(growable: false);
    rows.add(
      _SegmentRowSpec(
        key: 'condition-overlay:channels',
        title: 'Conditions x channels',
        plotData: _mergeSegmentPlotData(conditionPlots),
        height: summaryRowHeight,
      ),
    );
  } else {
    rows.add(
      _SegmentRowSpec(
        key: 'condition-overlay:mean',
        title: 'Conditions (mean across channels)',
        plotData: _buildSegmentAggregatePlotData(
          groups
              .map(
                (_SegmentLabelGroup group) => _SegmentAggregateSeriesInput(
                  traces: _alignedAverageChannelsTracesForSegments(
                    segmented: segmented,
                    segments: group.segments,
                    displayBaseline: displayBaseline,
                    baselineStartMs: baselineStartMs,
                    baselineStopMs: baselineStopMs,
                  ),
                  lineColor: group.color,
                  fillColor: group.color.withValues(alpha: 0.12),
                ),
              )
              .toList(growable: false),
        ),
        height: summaryRowHeight,
      ),
    );
  }

  return _SegmentPanelConfig(
    key: 'conditions-overlay',
    title: 'Conditions',
    subtitle: '${groups.length} label${groups.length == 1 ? '' : 's'} overlaid',
    accentColor: groups.isEmpty ? Colors.white70 : groups.first.color,
    rowSpecs: rows,
  );
}

_SegmentSequencePlotData _mergeSegmentPlotData(
  List<_SegmentSequencePlotData> plots,
) {
  final List<LineChartBarData> lineBars = <LineChartBarData>[];
  final List<BetweenBarsData> betweenBars = <BetweenBarsData>[];
  final List<VerticalRangeAnnotation> dividers = plots.isEmpty
      ? <VerticalRangeAnnotation>[]
      : plots.first.dividers;
  double? minX;
  double? maxX;
  double? minY;
  double? maxY;
  for (final _SegmentSequencePlotData plot in plots) {
    final int lineIndexOffset = lineBars.length;
    lineBars.addAll(plot.lineBars);
    betweenBars.addAll(
      plot.betweenBars.map(
        (BetweenBarsData fill) => BetweenBarsData(
          fromIndex: fill.fromIndex + lineIndexOffset,
          toIndex: fill.toIndex + lineIndexOffset,
          color: fill.color,
        ),
      ),
    );
    minX = minX == null ? plot.minX : math.min(minX, plot.minX);
    maxX = maxX == null ? plot.maxX : math.max(maxX, plot.maxX);
    minY = minY == null ? plot.minY : math.min(minY, plot.minY);
    maxY = maxY == null ? plot.maxY : math.max(maxY, plot.maxY);
  }
  return _SegmentSequencePlotData(
    lineBars: lineBars,
    betweenBars: betweenBars,
    dividers: dividers,
    minX: minX ?? 0,
    maxX: maxX ?? 1,
    minY: minY ?? -1,
    maxY: maxY ?? 1,
    stitchedSegments: plots.any(
      (_SegmentSequencePlotData plot) => plot.stitchedSegments,
    ),
    fitYToData: plots.any((_SegmentSequencePlotData plot) => plot.fitYToData),
  );
}

double _segmentRowHeight({
  required double rangeUv,
  required double spacingFactor,
  required bool naturalChannels,
}) {
  final double rangeFactor = (rangeUv / 100.0).clamp(0.75, 2.0);
  final double base = naturalChannels ? 116.0 : 168.0;
  return base * spacingFactor.clamp(0.5, 2.0) * (0.88 + (rangeFactor * 0.12));
}

double _segmentStackedChannelsRowHeight({
  required int channelCount,
  required double rangeUv,
  required double spacingFactor,
}) {
  final double rangeFactor = (rangeUv / 100.0).clamp(0.85, 1.5);
  final double perChannel = 28.0 * spacingFactor.clamp(0.5, 2.0) * rangeFactor;
  return math.max(180.0, math.min(900.0, 54.0 + channelCount * perChannel));
}

_SegmentSequencePlotData _buildStackedChannelsSegmentPlotData({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required int channelCount,
  required String segmentMode,
  required Color color,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
  required double rangeUv,
  required double spacingFactor,
}) {
  final List<_SegmentSequencePlotData> channelPlots =
      List<_SegmentSequencePlotData>.generate(channelCount, (int channelIndex) {
        return switch (segmentMode) {
          'butterfly' => _buildSegmentButterflySegmentsPlotData(
            segmented: segmented,
            segments: segments,
            channelIndex: channelIndex,
            color: color,
            displayBaseline: displayBaseline,
            baselineStartMs: baselineStartMs,
            baselineStopMs: baselineStopMs,
          ),
          'average' =>
            _buildSegmentAggregatePlotData(<_SegmentAggregateSeriesInput>[
              _SegmentAggregateSeriesInput(
                traces: _alignedDisplayedSegmentTracesForChannel(
                  segmented: segmented,
                  segments: segments,
                  channelIndex: channelIndex,
                  displayBaseline: displayBaseline,
                  baselineStartMs: baselineStartMs,
                  baselineStopMs: baselineStopMs,
                ),
                lineColor: _segmentTraceShade(color, channelIndex, 0),
                fillColor: _segmentTraceShade(
                  color,
                  channelIndex,
                  0,
                ).withValues(alpha: 0.14),
              ),
            ]),
          _ => _buildSegmentSequencePlotData(
            segmented: segmented,
            segments: segments,
            channelIndex: channelIndex,
            color: color,
            overlayChannels: false,
            displayBaseline: displayBaseline,
            baselineStartMs: baselineStartMs,
            baselineStopMs: baselineStopMs,
          ),
        };
      }, growable: false);
  return _stackSegmentChannelPlotData(
    channelPlots: channelPlots,
    channelLabels: List<String>.generate(
      channelCount,
      (int channelIndex) => _segmentChannelLabel(segmented, channelIndex),
      growable: false,
    ),
    rangeUv: rangeUv,
    spacingFactor: spacingFactor,
    stitchedSegments: segmentMode == 'natural',
  );
}

_SegmentSequencePlotData _buildStackedChannelsConditionOverlayPlotData({
  required SegmentedTimeSeriesData segmented,
  required List<_SegmentLabelGroup> groups,
  required int channelCount,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
  required double rangeUv,
  required double spacingFactor,
}) {
  final List<_SegmentSequencePlotData> channelPlots =
      List<_SegmentSequencePlotData>.generate(channelCount, (int channelIndex) {
        return _buildSegmentAggregatePlotData(
          groups
              .map(
                (_SegmentLabelGroup group) => _SegmentAggregateSeriesInput(
                  traces: _alignedDisplayedSegmentTracesForChannel(
                    segmented: segmented,
                    segments: group.segments,
                    channelIndex: channelIndex,
                    displayBaseline: displayBaseline,
                    baselineStartMs: baselineStartMs,
                    baselineStopMs: baselineStopMs,
                  ),
                  lineColor: group.color,
                  fillColor: group.color.withValues(alpha: 0.12),
                ),
              )
              .toList(growable: false),
        );
      }, growable: false);
  return _stackSegmentChannelPlotData(
    channelPlots: channelPlots,
    channelLabels: List<String>.generate(
      channelCount,
      (int channelIndex) => _segmentChannelLabel(segmented, channelIndex),
      growable: false,
    ),
    rangeUv: rangeUv,
    spacingFactor: spacingFactor,
    stitchedSegments: false,
  );
}

_SegmentSequencePlotData _stackSegmentChannelPlotData({
  required List<_SegmentSequencePlotData> channelPlots,
  required List<String> channelLabels,
  required double rangeUv,
  required double spacingFactor,
  required bool stitchedSegments,
}) {
  final List<LineChartBarData> shiftedBars = <LineChartBarData>[];
  final List<BetweenBarsData> shiftedBetweenBars = <BetweenBarsData>[];
  final List<VerticalRangeAnnotation> dividers = <VerticalRangeAnnotation>[];
  final List<_SegmentYAxisLabel> yAxisLabels = <_SegmentYAxisLabel>[];
  final double channelSpacing =
      math.max(1.0, rangeUv) * spacingFactor.clamp(0.5, 2.0);
  double? minXValue;
  double? maxXValue;
  double? minYValue;
  double? maxYValue;

  for (
    int channelIndex = 0;
    channelIndex < channelPlots.length;
    channelIndex++
  ) {
    final _SegmentSequencePlotData plot = channelPlots[channelIndex];
    if (plot.lineBars.isEmpty) {
      continue;
    }
    if (dividers.isEmpty && plot.dividers.isNotEmpty) {
      dividers.addAll(plot.dividers);
    }
    final double channelOffset =
        ((channelPlots.length - 1) / 2 - channelIndex) * channelSpacing;
    yAxisLabels.add(
      _SegmentYAxisLabel(
        position: channelOffset,
        label: channelIndex < channelLabels.length
            ? channelLabels[channelIndex]
            : 'Ch ${channelIndex + 1}',
      ),
    );
    final int lineIndexOffset = shiftedBars.length;
    for (final LineChartBarData bar in plot.lineBars) {
      final List<FlSpot> shiftedSpots = bar.spots
          .map((FlSpot spot) => FlSpot(spot.x, spot.y + channelOffset))
          .toList(growable: false);
      for (final FlSpot spot in shiftedSpots) {
        minXValue = minXValue == null ? spot.x : math.min(minXValue, spot.x);
        maxXValue = maxXValue == null ? spot.x : math.max(maxXValue, spot.x);
        minYValue = minYValue == null ? spot.y : math.min(minYValue, spot.y);
        maxYValue = maxYValue == null ? spot.y : math.max(maxYValue, spot.y);
      }
      shiftedBars.add(bar.copyWith(spots: shiftedSpots));
    }
    for (final BetweenBarsData betweenBar in plot.betweenBars) {
      shiftedBetweenBars.add(
        BetweenBarsData(
          fromIndex: betweenBar.fromIndex + lineIndexOffset,
          toIndex: betweenBar.toIndex + lineIndexOffset,
          color: betweenBar.color,
        ),
      );
    }
  }

  if (shiftedBars.isEmpty) {
    return _SegmentSequencePlotData(
      lineBars: const <LineChartBarData>[],
      betweenBars: const <BetweenBarsData>[],
      dividers: const <VerticalRangeAnnotation>[],
      minX: 0,
      maxX: 1,
      minY: -1,
      maxY: 1,
      stitchedSegments: stitchedSegments,
      fitYToData: true,
    );
  }

  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double padding = math.max(1.0, channelSpacing * 0.18);
  return _SegmentSequencePlotData(
    lineBars: shiftedBars,
    betweenBars: shiftedBetweenBars,
    dividers: dividers,
    minX: minXValue ?? 0,
    maxX: maxXValue ?? 1,
    minY: minY == maxY ? minY - 1 : minY - padding,
    maxY: minY == maxY ? maxY + 1 : maxY + padding,
    stitchedSegments: stitchedSegments,
    fitYToData: true,
    yAxisLabels: yAxisLabels,
  );
}

_SegmentSequencePlotData _buildSegmentSequencePlotData({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required int channelIndex,
  required Color color,
  required bool overlayChannels,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<LineChartBarData> bars = <LineChartBarData>[];
  final List<VerticalRangeAnnotation> dividers = <VerticalRangeAnnotation>[];
  double? minYValue;
  double? maxYValue;
  final double stepMs = segmented.sampleRate <= 0
      ? 1.0
      : 1000.0 / segmented.sampleRate;
  double cursorMs = 0;
  const double minX = 0;
  const double gapMs = 60;

  for (int segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
    final SignalSegmentData segment = segments[segmentIndex];
    final int segmentChannelCount = segmented.channelCountForSegment(segment);
    final int localChannelCount = overlayChannels
        ? segmentChannelCount
        : math.min(segmentChannelCount, channelIndex + 1);
    int longestSampleCount = 0;

    for (
      int localChannelIndex = overlayChannels ? 0 : channelIndex;
      localChannelIndex < localChannelCount;
      localChannelIndex++
    ) {
      if (localChannelIndex < 0 || localChannelIndex >= segmentChannelCount) {
        continue;
      }
      final List<double> values = _displaySegmentChannelValues(
        segmented: segmented,
        segment: segment,
        channelIndex: localChannelIndex,
        displayBaseline: displayBaseline,
        baselineStartMs: baselineStartMs,
        baselineStopMs: baselineStopMs,
      );
      if (values.isEmpty) {
        continue;
      }
      longestSampleCount = math.max(longestSampleCount, values.length);
      final List<FlSpot> spots = _decimatedSegmentSpots(
        values: values,
        startMs: cursorMs,
        stepMs: stepMs,
        maxPoints: overlayChannels ? 260 : _segmentPreviewMaxPoints,
      );
      for (final FlSpot spot in spots) {
        final double currentMinY = minYValue ?? spot.y;
        final double currentMaxY = maxYValue ?? spot.y;
        minYValue = math.min(currentMinY, spot.y);
        maxYValue = math.max(currentMaxY, spot.y);
      }
      final Color traceColor = overlayChannels
          ? _channelOverlayColor(color, localChannelIndex)
          : _segmentTraceShade(color, channelIndex, segmentIndex);
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          barWidth: overlayChannels ? 1.05 : 1.45,
          color: traceColor,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final double segmentWidthMs = math.max(stepMs, longestSampleCount * stepMs);
    cursorMs += segmentWidthMs;
    if (segmentIndex < segments.length - 1) {
      dividers.add(
        VerticalRangeAnnotation(
          x1: cursorMs,
          x2: cursorMs + gapMs,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      );
      cursorMs += gapMs;
    }
  }

  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double yPadding = math.max(0.001, (maxY - minY).abs() * 0.08);
  return _SegmentSequencePlotData(
    lineBars: bars,
    dividers: dividers,
    minX: minX,
    maxX: math.max(1, cursorMs),
    minY: minY == maxY ? minY - 1 : minY - yPadding,
    maxY: minY == maxY ? maxY + 1 : maxY + yPadding,
    stitchedSegments: true,
  );
}

_SegmentSequencePlotData _buildSegmentButterflySegmentsPlotData({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required int channelIndex,
  required Color color,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<LineChartBarData> bars = <LineChartBarData>[];
  double? minXValue;
  double? maxXValue;
  double? minYValue;
  double? maxYValue;
  for (int segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
    final SignalSegmentData segment = segments[segmentIndex];
    final List<double> values = _displaySegmentChannelValues(
      segmented: segmented,
      segment: segment,
      channelIndex: channelIndex,
      displayBaseline: displayBaseline,
      baselineStartMs: baselineStartMs,
      baselineStopMs: baselineStopMs,
    );
    final double stepMs = segmented.sampleRate <= 0
        ? 1.0
        : 1000.0 / segmented.sampleRate;
    final List<FlSpot> spots = _decimatedSegmentSpots(
      values: values,
      startMs: _relativeSegmentStartMs(segment),
      stepMs: stepMs,
      maxPoints: 300,
    );
    if (spots.isEmpty) {
      continue;
    }
    for (final FlSpot spot in spots) {
      final double currentMinX = minXValue ?? spot.x;
      final double currentMaxX = maxXValue ?? spot.x;
      final double currentMinY = minYValue ?? spot.y;
      final double currentMaxY = maxYValue ?? spot.y;
      minXValue = math.min(currentMinX, spot.x);
      maxXValue = math.max(currentMaxX, spot.x);
      minYValue = math.min(currentMinY, spot.y);
      maxYValue = math.max(currentMaxY, spot.y);
    }
    bars.add(
      LineChartBarData(
        spots: spots,
        isCurved: false,
        barWidth: 1.1,
        color: _segmentTraceShade(
          color,
          channelIndex,
          segmentIndex,
        ).withValues(alpha: segments.length == 1 ? 0.9 : 0.48),
        dotData: const FlDotData(show: false),
      ),
    );
  }
  final double minX = minXValue ?? 0;
  final double maxX = maxXValue ?? 1;
  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double yPadding = math.max(0.001, (maxY - minY).abs() * 0.08);
  return _SegmentSequencePlotData(
    lineBars: bars,
    dividers: const <VerticalRangeAnnotation>[],
    minX: minX == maxX ? minX - 1 : minX,
    maxX: minX == maxX ? maxX + 1 : maxX,
    minY: minY == maxY ? minY - 1 : minY - yPadding,
    maxY: minY == maxY ? maxY + 1 : maxY + yPadding,
  );
}

// ignore: unused_element
_SegmentSequencePlotData _buildSegmentAveragePlotData({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required int channelIndex,
  required Color color,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<List<double>> traces = <List<double>>[];
  final List<double> xValues = <double>[];
  for (final SignalSegmentData segment in segments) {
    final List<double> channel = _displaySegmentChannelValues(
      segmented: segmented,
      segment: segment,
      channelIndex: channelIndex,
      displayBaseline: displayBaseline,
      baselineStartMs: baselineStartMs,
      baselineStopMs: baselineStopMs,
    );
    if (channel.isEmpty) {
      continue;
    }
    traces.add(channel);
    if (xValues.isEmpty) {
      final double startMs = _relativeSegmentStartMs(segment);
      final double stepMs = segmented.sampleRate <= 0
          ? 1.0
          : 1000.0 / segmented.sampleRate;
      xValues.addAll(
        List<double>.generate(
          channel.length,
          (int index) => startMs + index * stepMs,
          growable: false,
        ),
      );
    }
  }
  if (traces.isEmpty || xValues.isEmpty) {
    return const _SegmentSequencePlotData(
      lineBars: <LineChartBarData>[],
      dividers: <VerticalRangeAnnotation>[],
      minX: 0,
      maxX: 1,
      minY: -1,
      maxY: 1,
    );
  }
  final int minLength = math.min(
    xValues.length,
    traces.map((List<double> trace) => trace.length).reduce(math.min),
  );
  final int step = math.max(1, (minLength / _segmentAverageMaxPoints).ceil());
  final List<FlSpot> spots = <FlSpot>[];
  double? minYValue;
  double? maxYValue;
  for (int sampleIndex = 0; sampleIndex < minLength; sampleIndex += step) {
    double sum = 0;
    for (final List<double> trace in traces) {
      sum += trace[sampleIndex];
    }
    final double y = _quantizeSegmentY(sum / traces.length);
    spots.add(FlSpot(_quantizeSegmentX(xValues[sampleIndex]), y));
    final double currentMinY = minYValue ?? y;
    final double currentMaxY = maxYValue ?? y;
    minYValue = math.min(currentMinY, y);
    maxYValue = math.max(currentMaxY, y);
  }
  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double yPadding = math.max(0.001, (maxY - minY).abs() * 0.08);
  return _SegmentSequencePlotData(
    lineBars: <LineChartBarData>[
      LineChartBarData(
        spots: spots,
        isCurved: false,
        barWidth: 2.2,
        color: _segmentTraceShade(color, channelIndex, 0),
        dotData: const FlDotData(show: false),
      ),
    ],
    dividers: const <VerticalRangeAnnotation>[],
    minX: spots.first.x,
    maxX: spots.last.x,
    minY: minY == maxY ? minY - 1 : minY - yPadding,
    maxY: minY == maxY ? maxY + 1 : maxY + yPadding,
  );
}

_SegmentSequencePlotData _buildSegmentAggregatePlotData(
  List<_SegmentAggregateSeriesInput> inputs, {
  bool fitYToData = false,
}) {
  final List<LineChartBarData> lineBars = <LineChartBarData>[];
  final List<BetweenBarsData> betweenBars = <BetweenBarsData>[];
  double? minXValue;
  double? maxXValue;
  double? minYValue;
  double? maxYValue;

  for (final _SegmentAggregateSeriesInput input in inputs) {
    if (input.traces.isEmpty) {
      continue;
    }
    final int minLength = input.traces
        .map((_AlignedTrace trace) => trace.values.length)
        .reduce(math.min);
    if (minLength <= 0) {
      continue;
    }
    final List<double> xValues = input.traces.first.xValues
        .take(minLength)
        .toList(growable: false);
    final AggregateSeriesStats? aggregateStats =
        computeAggregateSeriesStatsWithFallback(
          input.traces
              .map(
                (_AlignedTrace trace) =>
                    trace.values.take(minLength).toList(growable: false),
              )
              .toList(growable: false),
        );
    if (aggregateStats == null) {
      continue;
    }

    final List<FlSpot> meanSpots = List<FlSpot>.generate(
      minLength,
      (int sampleIndex) => FlSpot(
        _quantizeSegmentX(xValues[sampleIndex]),
        _quantizeSegmentY(aggregateStats.mean[sampleIndex]),
      ),
      growable: false,
    );
    final List<FlSpot> lowerSpots = List<FlSpot>.generate(
      minLength,
      (int sampleIndex) => FlSpot(
        _quantizeSegmentX(xValues[sampleIndex]),
        _quantizeSegmentY(
          aggregateStats.mean[sampleIndex] -
              aggregateStats.standardDeviation[sampleIndex],
        ),
      ),
      growable: false,
    );
    final List<FlSpot> upperSpots = List<FlSpot>.generate(
      minLength,
      (int sampleIndex) => FlSpot(
        _quantizeSegmentX(xValues[sampleIndex]),
        _quantizeSegmentY(
          aggregateStats.mean[sampleIndex] +
              aggregateStats.standardDeviation[sampleIndex],
        ),
      ),
      growable: false,
    );

    for (final List<FlSpot> series in <List<FlSpot>>[
      meanSpots,
      if (input.showSpread) lowerSpots,
      if (input.showSpread) upperSpots,
    ]) {
      for (final FlSpot spot in series) {
        final double currentMinX = minXValue ?? spot.x;
        final double currentMaxX = maxXValue ?? spot.x;
        final double currentMinY = minYValue ?? spot.y;
        final double currentMaxY = maxYValue ?? spot.y;
        minXValue = math.min(currentMinX, spot.x);
        maxXValue = math.max(currentMaxX, spot.x);
        minYValue = math.min(currentMinY, spot.y);
        maxYValue = math.max(currentMaxY, spot.y);
      }
    }

    int lowerIndex = -1;
    int upperIndex = -1;
    if (input.showSpread && input.traces.length > 1) {
      lowerIndex = lineBars.length;
      lineBars.add(
        LineChartBarData(
          spots: lowerSpots,
          isCurved: false,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        ),
      );
      upperIndex = lineBars.length;
      lineBars.add(
        LineChartBarData(
          spots: upperSpots,
          isCurved: false,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        ),
      );
      betweenBars.add(
        BetweenBarsData(
          fromIndex: lowerIndex,
          toIndex: upperIndex,
          color: input.fillColor,
        ),
      );
    }

    lineBars.add(
      LineChartBarData(
        spots: meanSpots,
        isCurved: false,
        color: input.lineColor,
        barWidth: input.barWidth,
        dotData: const FlDotData(show: false),
      ),
    );
  }

  if (lineBars.isEmpty) {
    return _SegmentSequencePlotData(
      lineBars: <LineChartBarData>[],
      betweenBars: <BetweenBarsData>[],
      dividers: <VerticalRangeAnnotation>[],
      minX: 0,
      maxX: 1,
      minY: -1,
      maxY: 1,
      fitYToData: fitYToData,
    );
  }

  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double yPadding = math.max(0.001, (maxY - minY).abs() * 0.08);
  return _SegmentSequencePlotData(
    lineBars: lineBars,
    betweenBars: betweenBars,
    dividers: const <VerticalRangeAnnotation>[],
    minX: minXValue ?? 0,
    maxX: maxXValue ?? 1,
    minY: minY == maxY ? minY - 1 : minY - yPadding,
    maxY: minY == maxY ? maxY + 1 : maxY + yPadding,
    fitYToData: fitYToData,
  );
}

_SegmentSequencePlotData _buildSegmentButterflyChannelsAndSegmentsPlotData({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required Color color,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<LineChartBarData> bars = <LineChartBarData>[];
  double? minXValue;
  double? maxXValue;
  double? minYValue;
  double? maxYValue;
  for (int segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
    final SignalSegmentData segment = segments[segmentIndex];
    final int channelCount = segmented.channelCountForSegment(segment);
    final double stepMs = segmented.sampleRate <= 0
        ? 1.0
        : 1000.0 / segmented.sampleRate;
    for (int channelIndex = 0; channelIndex < channelCount; channelIndex++) {
      final List<double> values = _displaySegmentChannelValues(
        segmented: segmented,
        segment: segment,
        channelIndex: channelIndex,
        displayBaseline: displayBaseline,
        baselineStartMs: baselineStartMs,
        baselineStopMs: baselineStopMs,
      );
      final List<FlSpot> spots = _decimatedSegmentSpots(
        values: values,
        startMs: _relativeSegmentStartMs(segment),
        stepMs: stepMs,
        maxPoints: 260,
      );
      if (spots.isEmpty) {
        continue;
      }
      for (final FlSpot spot in spots) {
        final double currentMinX = minXValue ?? spot.x;
        final double currentMaxX = maxXValue ?? spot.x;
        final double currentMinY = minYValue ?? spot.y;
        final double currentMaxY = maxYValue ?? spot.y;
        minXValue = math.min(currentMinX, spot.x);
        maxXValue = math.max(currentMaxX, spot.x);
        minYValue = math.min(currentMinY, spot.y);
        maxYValue = math.max(currentMaxY, spot.y);
      }
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          barWidth: 1.0,
          color: _channelOverlayColor(
            _segmentTraceShade(color, channelIndex, segmentIndex),
            channelIndex,
          ).withValues(alpha: 0.48),
          dotData: const FlDotData(show: false),
        ),
      );
    }
  }
  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double yPadding = math.max(0.001, (maxY - minY).abs() * 0.08);
  return _SegmentSequencePlotData(
    lineBars: bars,
    dividers: const <VerticalRangeAnnotation>[],
    minX: minXValue ?? 0,
    maxX: maxXValue ?? 1,
    minY: minY == maxY ? minY - 1 : minY - yPadding,
    maxY: minY == maxY ? maxY + 1 : maxY + yPadding,
  );
}

_SegmentSequencePlotData _buildAverageChannelsStitchedPlotData({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required Color color,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<LineChartBarData> bars = <LineChartBarData>[];
  final List<VerticalRangeAnnotation> dividers = <VerticalRangeAnnotation>[];
  double? minYValue;
  double? maxYValue;
  final double stepMs = segmented.sampleRate <= 0
      ? 1.0
      : 1000.0 / segmented.sampleRate;
  double cursorMs = 0;
  const double minX = 0;
  const double gapMs = 60;

  for (int segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
    final SignalSegmentData segment = segments[segmentIndex];
    final List<double> values = _averageAcrossChannelsForSegment(
      segmented: segmented,
      segment: segment,
      displayBaseline: displayBaseline,
      baselineStartMs: baselineStartMs,
      baselineStopMs: baselineStopMs,
    );
    final List<FlSpot> spots = _decimatedSegmentSpots(
      values: values,
      startMs: cursorMs,
      stepMs: stepMs,
      maxPoints: _segmentPreviewMaxPoints,
    );
    for (final FlSpot spot in spots) {
      final double currentMinY = minYValue ?? spot.y;
      final double currentMaxY = maxYValue ?? spot.y;
      minYValue = math.min(currentMinY, spot.y);
      maxYValue = math.max(currentMaxY, spot.y);
    }
    bars.add(
      LineChartBarData(
        spots: spots,
        isCurved: false,
        barWidth: 1.7,
        color: _segmentTraceShade(color, 0, segmentIndex),
        dotData: const FlDotData(show: false),
      ),
    );
    final double segmentWidthMs = math.max(stepMs, values.length * stepMs);
    cursorMs += segmentWidthMs;
    if (segmentIndex < segments.length - 1) {
      dividers.add(
        VerticalRangeAnnotation(
          x1: cursorMs,
          x2: cursorMs + gapMs,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      );
      cursorMs += gapMs;
    }
  }

  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double yPadding = math.max(0.001, (maxY - minY).abs() * 0.08);
  return _SegmentSequencePlotData(
    lineBars: bars,
    dividers: dividers,
    minX: minX,
    maxX: math.max(1, cursorMs),
    minY: minY == maxY ? minY - 1 : minY - yPadding,
    maxY: minY == maxY ? maxY + 1 : maxY + yPadding,
    stitchedSegments: true,
  );
}

_SegmentSequencePlotData _buildAverageChannelsButterflySegmentsPlotData({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required Color color,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<LineChartBarData> bars = <LineChartBarData>[];
  double? minXValue;
  double? maxXValue;
  double? minYValue;
  double? maxYValue;
  for (int segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
    final SignalSegmentData segment = segments[segmentIndex];
    final List<double> values = _averageAcrossChannelsForSegment(
      segmented: segmented,
      segment: segment,
      displayBaseline: displayBaseline,
      baselineStartMs: baselineStartMs,
      baselineStopMs: baselineStopMs,
    );
    final double stepMs = segmented.sampleRate <= 0
        ? 1.0
        : 1000.0 / segmented.sampleRate;
    final List<FlSpot> spots = _decimatedSegmentSpots(
      values: values,
      startMs: _relativeSegmentStartMs(segment),
      stepMs: stepMs,
      maxPoints: 300,
    );
    if (spots.isEmpty) {
      continue;
    }
    for (final FlSpot spot in spots) {
      final double currentMinX = minXValue ?? spot.x;
      final double currentMaxX = maxXValue ?? spot.x;
      final double currentMinY = minYValue ?? spot.y;
      final double currentMaxY = maxYValue ?? spot.y;
      minXValue = math.min(currentMinX, spot.x);
      maxXValue = math.max(currentMaxX, spot.x);
      minYValue = math.min(currentMinY, spot.y);
      maxYValue = math.max(currentMaxY, spot.y);
    }
    bars.add(
      LineChartBarData(
        spots: spots,
        isCurved: false,
        barWidth: 1.2,
        color: _segmentTraceShade(
          color,
          0,
          segmentIndex,
        ).withValues(alpha: segments.length == 1 ? 0.9 : 0.48),
        dotData: const FlDotData(show: false),
      ),
    );
  }
  final double minY = minYValue ?? -1;
  final double maxY = maxYValue ?? 1;
  final double yPadding = math.max(0.001, (maxY - minY).abs() * 0.08);
  return _SegmentSequencePlotData(
    lineBars: bars,
    dividers: const <VerticalRangeAnnotation>[],
    minX: minXValue ?? 0,
    maxX: maxXValue ?? 1,
    minY: minY == maxY ? minY - 1 : minY - yPadding,
    maxY: minY == maxY ? maxY + 1 : maxY + yPadding,
  );
}

Widget _segmentLineChart(
  _SegmentSequencePlotData plotData, {
  required double rangeUv,
}) {
  if (plotData.lineBars.isEmpty) {
    return const _ChartMessage(
      title: 'No samples',
      body: 'This segment/channel combination does not contain data.',
    );
  }
  final double yCenter = (plotData.minY + plotData.maxY) / 2;
  final double rawMinY = plotData.fitYToData
      ? plotData.minY
      : yCenter - math.max(0.001, rangeUv / 2);
  final double rawMaxY = plotData.fitYToData
      ? plotData.maxY
      : yCenter + math.max(0.001, rangeUv / 2);
  final double yInterval = _niceAxisStep(rawMaxY - rawMinY);
  final double minY = _floorToStep(rawMinY, yInterval);
  final double maxY = _ceilToStep(rawMaxY, yInterval);
  final double xInterval = _niceAxisStep(plotData.maxX - plotData.minX);
  final double minX = plotData.stitchedSegments
      ? _floorToStep(plotData.minX, xInterval)
      : plotData.minX;
  final double maxX = plotData.stitchedSegments
      ? _ceilToStep(plotData.maxX, xInterval)
      : plotData.maxX;
  final Widget chart = LineChart(
    LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        horizontalInterval: yInterval,
        verticalInterval: xInterval,
      ),
      rangeAnnotations: RangeAnnotations(
        verticalRangeAnnotations: <VerticalRangeAnnotation>[
          ...plotData.dividers,
          if (minX < 0 && maxX > 0)
            VerticalRangeAnnotation(
              x1: -math.max(0.5, xInterval * 0.006),
              x2: math.max(0.5, xInterval * 0.006),
              color: Colors.white.withValues(alpha: 0.16),
            ),
        ],
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      betweenBarsData: plotData.betweenBars,
      titlesData: _chartTitles(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        xAxisLabel: 'time (ms)',
        yAxisLabel: plotData.yAxisLabels.isEmpty ? 'μV' : '',
        showYValues: plotData.yAxisLabels.isEmpty,
        yAxisReservedSize: plotData.yAxisLabels.isEmpty ? 56 : 78,
        xAxisNameSize: 24,
        yAxisNameSize: 28,
        wholeNumberYLabels: true,
      ),
      clipData: const FlClipData.all(),
      lineBarsData: plotData.lineBars,
    ),
  );
  if (plotData.yAxisLabels.isEmpty) {
    return chart;
  }
  return Stack(
    children: <Widget>[
      chart,
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _SegmentYAxisLabelPainter(
              labels: plotData.yAxisLabels,
              minY: minY,
              maxY: maxY,
            ),
          ),
        ),
      ),
    ],
  );
}

class _SegmentYAxisLabelPainter extends CustomPainter {
  const _SegmentYAxisLabelPainter({
    required this.labels,
    required this.minY,
    required this.maxY,
  });

  final List<_SegmentYAxisLabel> labels;
  final double minY;
  final double maxY;

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || maxY <= minY) {
      return;
    }
    const double leftPadding = 4;
    final double drawableHeight = math.max(1.0, size.height - 42.0);
    for (final _SegmentYAxisLabel label in labels) {
      final double fraction = ((maxY - label.position) / (maxY - minY)).clamp(
        0.0,
        1.0,
      );
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: label.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        maxLines: 1,
        ellipsis: '...',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 68);
      final double y = (fraction * drawableHeight) - (painter.height / 2);
      painter.paint(canvas, Offset(leftPadding, y.clamp(0.0, size.height)));
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentYAxisLabelPainter oldDelegate) {
    return oldDelegate.labels != labels ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY;
  }
}

double _floorToStep(double value, double step) {
  if (step <= 0 || !value.isFinite) {
    return value;
  }
  return (value / step).floorToDouble() * step;
}

double _ceilToStep(double value, double step) {
  if (step <= 0 || !value.isFinite) {
    return value;
  }
  return (value / step).ceilToDouble() * step;
}

Color _segmentLabelColor(String label, int index) {
  const List<Color> palette = <Color>[
    Color(0xFFFFD23F),
    Color(0xFF2F80ED),
    Color(0xFF34D399),
    Color(0xFFFF5C8A),
    Color(0xFFFF8A3D),
    Color(0xFF8B5CF6),
    Color(0xFF00C2A8),
    Color(0xFFE84855),
    Color(0xFF7DD3FC),
    Color(0xFFA3E635),
  ];
  return palette[index % palette.length];
}

Color _channelOverlayColor(Color baseColor, int channelIndex) {
  final double opacity = channelIndex.isEven ? 0.7 : 0.45;
  return Color.lerp(
    baseColor,
    Colors.white,
    (channelIndex % 5) * 0.08,
  )!.withValues(alpha: opacity);
}

Color _segmentTraceShade(Color baseColor, int channelIndex, int segmentIndex) {
  const List<double> whiteMixes = <double>[
    0.00,
    0.10,
    0.18,
    0.05,
    0.24,
    0.14,
    0.30,
    0.08,
    0.20,
  ];
  const List<double> blackMixes = <double>[
    0.00,
    0.00,
    0.00,
    0.10,
    0.00,
    0.16,
    0.00,
    0.22,
    0.06,
  ];
  final int shadeIndex = (channelIndex * 3 + segmentIndex) % whiteMixes.length;
  final Color lifted = Color.lerp(
    baseColor,
    Colors.white,
    whiteMixes[shadeIndex],
  )!;
  return Color.lerp(
    lifted,
    Colors.black,
    blackMixes[shadeIndex],
  )!.withValues(alpha: segmentIndex.isEven ? 0.92 : 0.78);
}

String _segmentDisplayLabel(SignalSegmentData segment, int index) {
  final String label = segment.label.trim();
  return label.isEmpty ? 'Segment ${index + 1}' : '${index + 1}. $label';
}

String _segmentChannelLabel(SegmentedTimeSeriesData segmented, int index) {
  if (index >= 0 && index < segmented.channelLabels.length) {
    return segmented.channelLabels[index];
  }
  return 'Ch ${index + 1}';
}

List<FlSpot> _segmentChannelSpots(
  SegmentedTimeSeriesData segmented,
  SignalSegmentData segment,
  double sampleRate,
  int channelIndex,
) {
  final List<List<double>> channelSamples = segmented.channelSamplesForSegment(
    segment,
  );
  if (channelIndex < 0 || channelIndex >= channelSamples.length) {
    return const <FlSpot>[];
  }
  final List<double> values = channelSamples[channelIndex];
  final double startMs = _relativeSegmentStartMs(segment);
  final double stepMs = sampleRate <= 0 ? 1.0 : 1000.0 / sampleRate;
  return List<FlSpot>.generate(
    values.length,
    (int index) => FlSpot(startMs + (index * stepMs), values[index]),
    growable: false,
  );
}

List<double> _displaySegmentChannelValues({
  required SegmentedTimeSeriesData segmented,
  required SignalSegmentData segment,
  required int channelIndex,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<List<double>> samples = segmented.channelSamplesForSegment(
    segment,
  );
  if (channelIndex < 0 || channelIndex >= samples.length) {
    return const <double>[];
  }
  final List<double> channel = samples[channelIndex];
  if (!displayBaseline || samples.isEmpty || segmented.sampleRate <= 0) {
    return channel;
  }
  final Map<String, List<double>> cache = _segmentDisplayValueCache[segment] ??=
      <String, List<double>>{};
  final bool useConfiguredWindow = baselineStopMs > baselineStartMs;
  final String cacheKey = useConfiguredWindow
      ? '$channelIndex|${segmented.sampleRate}|$baselineStartMs|$baselineStopMs'
      : '$channelIndex|${segmented.sampleRate}|anchor';
  final List<double>? cached = cache[cacheKey];
  if (cached != null) {
    return cached;
  }
  double baselineMean;
  if (useConfiguredWindow) {
    final double anchorSeconds =
        segment.anchorTimeSeconds ?? segment.startSeconds;
    final double baselineStartSeconds =
        anchorSeconds + baselineStartMs / 1000.0;
    final double baselineStopSeconds = anchorSeconds + baselineStopMs / 1000.0;
    final int startIndex =
        ((baselineStartSeconds - segment.startSeconds) * segmented.sampleRate)
            .round();
    final int stopIndex =
        ((baselineStopSeconds - segment.startSeconds) * segmented.sampleRate)
            .round();
    final int sampleCount = channel.length;
    final int boundedStart = startIndex.clamp(0, sampleCount);
    final int boundedStop = stopIndex.clamp(0, sampleCount);
    if (boundedStop <= boundedStart) {
      return _baselineAtAnchorSample(
        channel: channel,
        segmented: segmented,
        segment: segment,
        cache: cache,
        cacheKey: cacheKey,
      );
    }
    double sum = 0;
    for (int index = boundedStart; index < boundedStop; index++) {
      sum += channel[index];
    }
    baselineMean = sum / (boundedStop - boundedStart);
  } else {
    return _baselineAtAnchorSample(
      channel: channel,
      segmented: segmented,
      segment: segment,
      cache: cache,
      cacheKey: cacheKey,
    );
  }
  final List<double> corrected = List<double>.generate(
    channel.length,
    (int index) => channel[index] - baselineMean,
    growable: false,
  );
  cache[cacheKey] = corrected;
  return corrected;
}

List<double> _baselineAtAnchorSample({
  required List<double> channel,
  required SegmentedTimeSeriesData segmented,
  required SignalSegmentData segment,
  required Map<String, List<double>> cache,
  required String cacheKey,
}) {
  if (channel.isEmpty) {
    return const <double>[];
  }
  final double anchorSeconds =
      segment.anchorTimeSeconds ?? segment.startSeconds;
  final int anchorIndex =
      ((anchorSeconds - segment.startSeconds) * segmented.sampleRate).round();
  final int boundedIndex = anchorIndex.clamp(0, channel.length - 1);
  final double baselineValue = channel[boundedIndex];
  final List<double> corrected = List<double>.generate(
    channel.length,
    (int index) => channel[index] - baselineValue,
    growable: false,
  );
  cache[cacheKey] = corrected;
  return corrected;
}

List<double> _averageAcrossChannelsForSegment({
  required SegmentedTimeSeriesData segmented,
  required SignalSegmentData segment,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<List<double>> samples = segmented.channelSamplesForSegment(
    segment,
  );
  if (samples.isEmpty) {
    return const <double>[];
  }
  final List<List<double>> channels = List<List<double>>.generate(
    samples.length,
    (int channelIndex) => _displaySegmentChannelValues(
      segmented: segmented,
      segment: segment,
      channelIndex: channelIndex,
      displayBaseline: displayBaseline,
      baselineStartMs: baselineStartMs,
      baselineStopMs: baselineStopMs,
    ),
    growable: false,
  ).where((List<double> values) => values.isNotEmpty).toList(growable: false);
  if (channels.isEmpty) {
    return const <double>[];
  }
  final int minLength = channels
      .map((List<double> values) => values.length)
      .reduce(math.min);
  if (minLength <= 0) {
    return const <double>[];
  }
  return List<double>.generate(minLength, (int sampleIndex) {
    double sum = 0.0;
    for (final List<double> channel in channels) {
      sum += channel[sampleIndex];
    }
    return sum / channels.length;
  }, growable: false);
}

List<FlSpot> _decimatedSegmentSpots({
  required List<double> values,
  required double startMs,
  required double stepMs,
  required int maxPoints,
}) {
  if (values.isEmpty) {
    return const <FlSpot>[];
  }
  final int stride = math.max(1, (values.length / maxPoints).ceil());
  final List<FlSpot> spots = <FlSpot>[];
  for (int index = 0; index < values.length; index += stride) {
    spots.add(
      FlSpot(
        _quantizeSegmentX(startMs + index * stepMs),
        _quantizeSegmentY(values[index]),
      ),
    );
  }
  if ((values.length - 1) % stride != 0) {
    final int index = values.length - 1;
    spots.add(
      FlSpot(
        _quantizeSegmentX(startMs + index * stepMs),
        _quantizeSegmentY(values[index]),
      ),
    );
  }
  return spots;
}

double _quantizeSegmentX(double valueMs) => (valueMs * 2).roundToDouble() / 2;

double _quantizeSegmentY(double valueUv) => (valueUv * 10).roundToDouble() / 10;

enum ViewerScrollIntent { timeZoom, amplitudeZoom, horizontalPan, verticalPan }

class ViewerScrollGesture {
  const ViewerScrollGesture({
    required this.intent,
    required this.primaryDelta,
    this.zoomingIn = false,
  });

  final ViewerScrollIntent intent;
  final double primaryDelta;
  final bool zoomingIn;
}

ViewerScrollGesture? viewerScrollGestureFromPointerSignal(
  PointerSignalEvent event,
) {
  if (event is! PointerScrollEvent) {
    return null;
  }
  final Set<LogicalKeyboardKey> pressed =
      HardwareKeyboard.instance.logicalKeysPressed;
  final bool ctrlPressed =
      pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight);
  final bool shiftPressed =
      pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight);
  if (ctrlPressed && shiftPressed) {
    return ViewerScrollGesture(
      intent: ViewerScrollIntent.timeZoom,
      primaryDelta: event.scrollDelta.dy,
      zoomingIn: event.scrollDelta.dy < 0,
    );
  }
  if (ctrlPressed) {
    return ViewerScrollGesture(
      intent: ViewerScrollIntent.amplitudeZoom,
      primaryDelta: event.scrollDelta.dy,
      zoomingIn: event.scrollDelta.dy < 0,
    );
  }
  if (shiftPressed) {
    return ViewerScrollGesture(
      intent: ViewerScrollIntent.horizontalPan,
      primaryDelta: event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()
          ? event.scrollDelta.dy
          : event.scrollDelta.dx,
    );
  }
  return ViewerScrollGesture(
    intent: ViewerScrollIntent.verticalPan,
    primaryDelta: event.scrollDelta.dy,
  );
}

double viewerZoomFactor({required bool zoomingIn}) {
  return zoomingIn ? 1 / 1.12 : 1.12;
}

void scrollControllerBy(ScrollController controller, double delta) {
  if (!controller.hasClients) {
    return;
  }
  final double target = (controller.offset + delta).clamp(
    controller.position.minScrollExtent,
    controller.position.maxScrollExtent,
  );
  if ((target - controller.offset).abs() > 0.5) {
    controller.jumpTo(target);
  }
}

double _relativeSegmentStartMs(SignalSegmentData segment) {
  final double anchor = segment.anchorTimeSeconds ?? segment.startSeconds;
  return (segment.startSeconds - anchor) * 1000.0;
}

List<_AlignedTrace> _alignedSegmentTracesForChannel({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required int channelIndex,
}) {
  final List<_AlignedTrace> traces = <_AlignedTrace>[];
  for (final SignalSegmentData segment in segments) {
    final List<FlSpot> spots = _segmentChannelSpots(
      segmented,
      segment,
      segmented.sampleRate,
      channelIndex,
    );
    if (spots.isEmpty) {
      continue;
    }
    traces.add(
      _AlignedTrace(
        values: spots.map((FlSpot spot) => spot.y).toList(growable: false),
        xValues: spots.map((FlSpot spot) => spot.x).toList(growable: false),
      ),
    );
  }
  return traces;
}

List<_AlignedTrace> _alignedChannelTracesForSegment({
  required SegmentedTimeSeriesData segmented,
  required SignalSegmentData segment,
}) {
  final List<_AlignedTrace> traces = <_AlignedTrace>[];
  for (
    int channelIndex = 0;
    channelIndex < segmented.channelCountForSegment(segment);
    channelIndex++
  ) {
    final List<FlSpot> spots = _segmentChannelSpots(
      segmented,
      segment,
      segmented.sampleRate,
      channelIndex,
    );
    if (spots.isEmpty) {
      continue;
    }
    traces.add(
      _AlignedTrace(
        values: spots.map((FlSpot spot) => spot.y).toList(growable: false),
        xValues: spots.map((FlSpot spot) => spot.x).toList(growable: false),
      ),
    );
  }
  return traces;
}

List<_AlignedTrace> _alignedChannelTracesForAllSegments(
  SegmentedTimeSeriesData segmented,
  List<SignalSegmentData> segments,
) {
  final List<_AlignedTrace> traces = <_AlignedTrace>[];
  for (final SignalSegmentData segment in segments) {
    traces.addAll(
      _alignedChannelTracesForSegment(segmented: segmented, segment: segment),
    );
  }
  return traces;
}

List<_AlignedTrace> _alignedAverageChannelsTracesForSegments({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<_AlignedTrace> traces = <_AlignedTrace>[];
  for (final SignalSegmentData segment in segments) {
    final List<double> values = _averageAcrossChannelsForSegment(
      segmented: segmented,
      segment: segment,
      displayBaseline: displayBaseline,
      baselineStartMs: baselineStartMs,
      baselineStopMs: baselineStopMs,
    );
    if (values.isEmpty) {
      continue;
    }
    final double startMs = _relativeSegmentStartMs(segment);
    final double stepMs = segmented.sampleRate <= 0
        ? 1.0
        : 1000.0 / segmented.sampleRate;
    traces.add(
      _AlignedTrace(
        values: values,
        xValues: List<double>.generate(
          values.length,
          (int index) => startMs + (index * stepMs),
          growable: false,
        ),
      ),
    );
  }
  return traces;
}

List<_AlignedTrace> _alignedDisplayedSegmentTracesForChannel({
  required SegmentedTimeSeriesData segmented,
  required List<SignalSegmentData> segments,
  required int channelIndex,
  required bool displayBaseline,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final List<_AlignedTrace> traces = <_AlignedTrace>[];
  for (final SignalSegmentData segment in segments) {
    final List<double> values = _displaySegmentChannelValues(
      segmented: segmented,
      segment: segment,
      channelIndex: channelIndex,
      displayBaseline: displayBaseline,
      baselineStartMs: baselineStartMs,
      baselineStopMs: baselineStopMs,
    );
    if (values.isEmpty) {
      continue;
    }
    final double startMs = _relativeSegmentStartMs(segment);
    final double stepMs = segmented.sampleRate <= 0
        ? 1.0
        : 1000.0 / segmented.sampleRate;
    traces.add(
      _AlignedTrace(
        values: values,
        xValues: List<double>.generate(
          values.length,
          (int index) => startMs + (index * stepMs),
          growable: false,
        ),
      ),
    );
  }
  return traces;
}

_AggregatePlotData? _buildAggregatePlotData(
  List<_AlignedTrace> traces, {
  required bool showMean,
  required bool showTraces,
  required bool showSpread,
}) {
  if (traces.isEmpty) {
    return null;
  }
  final int minLength = traces
      .map((_AlignedTrace trace) => trace.values.length)
      .reduce((int a, int b) => math.min(a, b));
  if (minLength <= 0) {
    return null;
  }

  final List<double> xValues = traces.first.xValues
      .take(minLength)
      .toList(growable: false);
  final bool needsAggregateStats = showMean || showSpread;
  final AggregateSeriesStats? aggregateStats = needsAggregateStats
      ? computeAggregateSeriesStatsWithFallback(
          traces
              .map(
                (_AlignedTrace trace) =>
                    trace.values.take(minLength).toList(growable: false),
              )
              .toList(growable: false),
        )
      : null;
  if (needsAggregateStats && aggregateStats == null) {
    return null;
  }

  final List<FlSpot> meanSpots = aggregateStats == null
      ? const <FlSpot>[]
      : List<FlSpot>.generate(
          minLength,
          (int sampleIndex) =>
              FlSpot(xValues[sampleIndex], aggregateStats.mean[sampleIndex]),
          growable: false,
        );
  final List<FlSpot> upperSpots = aggregateStats == null
      ? const <FlSpot>[]
      : List<FlSpot>.generate(
          minLength,
          (int sampleIndex) => FlSpot(
            xValues[sampleIndex],
            aggregateStats.mean[sampleIndex] +
                aggregateStats.standardDeviation[sampleIndex],
          ),
          growable: false,
        );
  final List<FlSpot> lowerSpots = aggregateStats == null
      ? const <FlSpot>[]
      : List<FlSpot>.generate(
          minLength,
          (int sampleIndex) => FlSpot(
            xValues[sampleIndex],
            aggregateStats.mean[sampleIndex] -
                aggregateStats.standardDeviation[sampleIndex],
          ),
          growable: false,
        );

  final List<double> allY = <double>[
    if (showTraces)
      ...traces.expand((_AlignedTrace trace) => trace.values.take(minLength)),
    if (showMean) ...meanSpots.map((FlSpot spot) => spot.y),
    if (showSpread) ...upperSpots.map((FlSpot spot) => spot.y),
    if (showSpread) ...lowerSpots.map((FlSpot spot) => spot.y),
  ];
  final double minX = xValues.isEmpty ? 0.0 : xValues.first;
  final double maxX = xValues.isEmpty ? 1.0 : xValues.last;
  final double minY = allY.isEmpty ? -1.0 : allY.reduce(math.min);
  final double maxY = allY.isEmpty ? 1.0 : allY.reduce(math.max);

  final List<LineChartBarData> lineBars = <LineChartBarData>[];
  final List<BetweenBarsData> betweenBars = <BetweenBarsData>[];
  if (showSpread) {
    lineBars.add(
      LineChartBarData(
        spots: lowerSpots,
        isCurved: false,
        color: Colors.transparent,
        barWidth: 0,
        dotData: const FlDotData(show: false),
      ),
    );
    lineBars.add(
      LineChartBarData(
        spots: upperSpots,
        isCurved: false,
        color: Colors.transparent,
        barWidth: 0,
        dotData: const FlDotData(show: false),
      ),
    );
    betweenBars.add(
      BetweenBarsData(
        fromIndex: 0,
        toIndex: 1,
        color: Colors.cyanAccent.withValues(alpha: 0.14),
      ),
    );
  }
  if (showTraces) {
    for (int index = 0; index < traces.length; index++) {
      final _AlignedTrace trace = traces[index];
      lineBars.add(
        LineChartBarData(
          spots: List<FlSpot>.generate(
            minLength,
            (int sampleIndex) =>
                FlSpot(xValues[sampleIndex], trace.values[sampleIndex]),
            growable: false,
          ),
          isCurved: false,
          color: _seriesColor(index).withValues(alpha: 0.24),
          barWidth: 1,
          dotData: const FlDotData(show: false),
        ),
      );
    }
  }
  if (showMean) {
    lineBars.add(
      LineChartBarData(
        spots: meanSpots,
        isCurved: false,
        color: Colors.cyanAccent,
        barWidth: 2.4,
        dotData: const FlDotData(show: false),
      ),
    );
  }

  return _AggregatePlotData(
    lineBars: lineBars,
    betweenBars: betweenBars,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
  );
}

Color _bridgeCorrelationColor(double value) {
  final double clamped = value.clamp(-1.0, 1.0);
  if (clamped < 0) {
    return Color.lerp(
          const Color(0xFF215DFF),
          const Color(0xFFF4F6FB),
          clamped + 1.0,
        ) ??
        const Color(0xFFF4F6FB);
  }
  return Color.lerp(
        const Color(0xFFF4F6FB),
        const Color(0xFFD62939),
        clamped,
      ) ??
      const Color(0xFFF4F6FB);
}

List<int> _computeCovarianceOrdering(BridgeDetectionData bridge) {
  final int channelCount = bridge.channelCount;
  if (channelCount <= 1) {
    return List<int>.generate(
      channelCount,
      (int index) => index,
      growable: false,
    );
  }

  final List<List<double>> similarity = List<List<double>>.generate(
    channelCount,
    (_) => List<double>.filled(channelCount, 0.0),
    growable: false,
  );

  for (final BridgeCorrelationFrameData frame in bridge.frames) {
    for (int row = 0; row < channelCount; row++) {
      final List<double> values = frame.correlationMatrix[row];
      for (
        int column = 0;
        column < math.min(channelCount, values.length);
        column++
      ) {
        similarity[row][column] += math.max(0.0, values[column]);
      }
    }
  }

  final double frameCount = math.max(1, bridge.frames.length).toDouble();
  for (int row = 0; row < channelCount; row++) {
    for (int column = 0; column < channelCount; column++) {
      similarity[row][column] /= frameCount;
    }
    similarity[row][row] = 1.0;
  }

  int seedIndex = 0;
  double bestMeanSimilarity = double.negativeInfinity;
  for (int row = 0; row < channelCount; row++) {
    double sum = 0.0;
    for (int column = 0; column < channelCount; column++) {
      if (row != column) {
        sum += similarity[row][column];
      }
    }
    final double mean = sum / math.max(1, channelCount - 1);
    if (mean > bestMeanSimilarity) {
      bestMeanSimilarity = mean;
      seedIndex = row;
    }
  }

  final List<int> ordered = <int>[seedIndex];
  final Set<int> remaining = Set<int>.from(
    List<int>.generate(channelCount, (int index) => index, growable: false),
  )..remove(seedIndex);

  while (remaining.isNotEmpty) {
    int bestCandidate = remaining.first;
    double bestSupport = double.negativeInfinity;
    for (final int candidate in remaining) {
      double support = 0.0;
      for (final int placed in ordered) {
        support += similarity[candidate][placed];
      }
      support /= ordered.length;
      if (support > bestSupport) {
        bestSupport = support;
        bestCandidate = candidate;
      }
    }

    final double leftAffinity = similarity[bestCandidate][ordered.first];
    final double rightAffinity = similarity[bestCandidate][ordered.last];
    if (leftAffinity > rightAffinity) {
      ordered.insert(0, bestCandidate);
    } else {
      ordered.add(bestCandidate);
    }
    remaining.remove(bestCandidate);
  }

  return ordered;
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.toolbar,
    this.legend = const <_SeriesData>[],
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? toolbar;
  final List<_SeriesData> legend;

  @override
  Widget build(BuildContext context) {
    final bool hasTitle = title.trim().isNotEmpty;
    final bool hasSubtitle = subtitle.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (hasTitle)
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (hasTitle && hasSubtitle) const SizedBox(height: 4),
            if (hasSubtitle)
              Text(subtitle, style: const TextStyle(color: Colors.white70)),
            if (toolbar != null) ...<Widget>[
              SizedBox(height: hasTitle || hasSubtitle ? 10 : 0),
              toolbar!,
            ],
            if (legend.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: legend
                    .map((_SeriesData series) => _LegendChip(series: series))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.series});

  final _SeriesData series;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: series.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(series.label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _SeriesData {
  const _SeriesData({
    required this.label,
    required this.color,
    required this.points,
    required this.subtitle,
  });

  final String label;
  final Color color;
  final List<FlSpot> points;
  final String subtitle;
}

const List<double> _continuousViewerWindowOptionsSec = <double>[
  1,
  2,
  5,
  10,
  20,
  30,
  60,
  120,
  300,
  600,
];
const List<double> _psdWindowOptionsHz = <double>[10, 20, 40, 80, 120];
const List<double> _psdMaxPowerOptions = <double>[
  0.1,
  0.5,
  1,
  2,
  5,
  10,
  20,
  50,
  100,
  200,
];

int _closestViewerOptionIndex(List<double> options, double value) {
  int bestIndex = 0;
  double bestDistance = (options.first - value).abs();
  for (int index = 1; index < options.length; index++) {
    final double distance = (options[index] - value).abs();
    if (distance < bestDistance) {
      bestIndex = index;
      bestDistance = distance;
    }
  }
  return bestIndex;
}

class _SharedZoomableChartViewport extends StatefulWidget {
  const _SharedZoomableChartViewport({
    required this.totalSpan,
    required this.windowSpan,
    required this.windowOptions,
    required this.onWindowSpanChanged,
    required this.builder,
    this.yScale,
    this.yScaleOptions,
    this.onYScaleChanged,
    this.yScaleEnabled = false,
  });

  final double totalSpan;
  final double windowSpan;
  final List<double> windowOptions;
  final ValueChanged<double> onWindowSpanChanged;
  final Widget Function(double chartWidth) builder;
  final double? yScale;
  final List<double>? yScaleOptions;
  final ValueChanged<double>? onYScaleChanged;
  final bool yScaleEnabled;

  @override
  State<_SharedZoomableChartViewport> createState() =>
      _SharedZoomableChartViewportState();
}

class _SharedZoomableChartViewportState
    extends State<_SharedZoomableChartViewport> {
  late final FocusNode _focusNode;
  late final ScrollController _horizontalController;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _horizontalController = ScrollController(keepScrollOffset: false);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool ctrlPressed = HardwareKeyboard.instance.isControlPressed;
    if (ctrlPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _stepWindow(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (ctrlPressed &&
        widget.yScaleEnabled &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      _stepYScale(key == LogicalKeyboardKey.arrowUp ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (!ctrlPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _nudgeHorizontalWindow(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final ViewerScrollGesture? gesture = viewerScrollGestureFromPointerSignal(
      event,
    );
    if (gesture == null) {
      return;
    }
    switch (gesture.intent) {
      case ViewerScrollIntent.horizontalPan:
        scrollControllerBy(_horizontalController, gesture.primaryDelta);
        return;
      case ViewerScrollIntent.timeZoom:
        final double factor = viewerZoomFactor(zoomingIn: gesture.zoomingIn);
        final double minOption = widget.windowOptions.isEmpty
            ? 1.0
            : widget.windowOptions.first;
        final double maxOption = widget.windowOptions.isEmpty
            ? widget.totalSpan
            : widget.windowOptions.last;
        widget.onWindowSpanChanged(
          (widget.windowSpan * factor).clamp(
            minOption,
            math.max(minOption, math.min(widget.totalSpan, maxOption)),
          ),
        );
        return;
      case ViewerScrollIntent.amplitudeZoom:
        if (widget.yScaleEnabled) {
          final double factor = viewerZoomFactor(zoomingIn: gesture.zoomingIn);
          final List<double> options =
              widget.yScaleOptions ?? const <double>[1, 2, 5, 10];
          final double current = widget.yScale ?? options.first;
          widget.onYScaleChanged?.call(
            (current * factor).clamp(options.first, options.last),
          );
        }
        return;
      case ViewerScrollIntent.verticalPan:
        return;
    }
  }

  void _stepWindow(int delta) {
    if (widget.windowOptions.isEmpty) {
      return;
    }
    final int currentIndex = _closestViewerOptionIndex(
      widget.windowOptions,
      widget.windowSpan,
    );
    final int nextIndex = (currentIndex + delta).clamp(
      0,
      widget.windowOptions.length - 1,
    );
    widget.onWindowSpanChanged(widget.windowOptions[nextIndex]);
  }

  void _stepYScale(int delta) {
    final List<double> options = widget.yScaleOptions ?? const <double>[];
    if (!widget.yScaleEnabled ||
        options.isEmpty ||
        widget.onYScaleChanged == null) {
      return;
    }
    final double current = widget.yScale ?? options.first;
    final int currentIndex = _closestViewerOptionIndex(options, current);
    final int nextIndex = (currentIndex + delta).clamp(0, options.length - 1);
    widget.onYScaleChanged!(options[nextIndex]);
  }

  void _nudgeHorizontalWindow(int direction) {
    if (!_horizontalController.hasClients) {
      return;
    }
    final double viewport = _horizontalController.position.viewportDimension;
    final double delta = viewport * 0.12 * direction;
    scrollControllerBy(_horizontalController, delta);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _focusNode.requestFocus(),
        child: Listener(
          onPointerSignal: _handlePointerSignal,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double viewportWidth = math.max(
                160.0,
                constraints.maxWidth,
              );
              final double safeWindowSpan = math.max(
                0.001,
                math.min(widget.windowSpan, widget.totalSpan),
              );
              final double widthFactor = math.max(
                1.0,
                widget.totalSpan / safeWindowSpan,
              );
              final double chartWidth = math.max(
                viewportWidth,
                viewportWidth * widthFactor,
              );
              return Scrollbar(
                controller: _horizontalController,
                thumbVisibility: widthFactor > 1.01,
                notificationPredicate: (ScrollNotification notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: widget.builder(chartWidth),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SegmentControlStripDivider extends StatelessWidget {
  const _SegmentControlStripDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 16,
        thickness: 2,
        color: Colors.white.withValues(alpha: 0.22),
      ),
    );
  }
}

class _SegmentViewerScaleControls extends StatelessWidget {
  const _SegmentViewerScaleControls({
    required this.timeSeconds,
    required this.timeOptionsSeconds,
    required this.onTimeSelected,
    required this.rangeUv,
    required this.rangeOptionsUv,
    required this.onRangeSelected,
    required this.spacingFactor,
    required this.spacingOptions,
    required this.onSpacingSelected,
  });

  final double timeSeconds;
  final List<double> timeOptionsSeconds;
  final ValueChanged<double> onTimeSelected;
  final double rangeUv;
  final List<double> rangeOptionsUv;
  final ValueChanged<double> onRangeSelected;
  final double spacingFactor;
  final List<double> spacingOptions;
  final ValueChanged<double> onSpacingSelected;

  @override
  Widget build(BuildContext context) {
    void step(
      List<double> options,
      double current,
      int direction,
      ValueChanged<double> onSelected,
    ) {
      final int currentIndex = _closestViewerOptionIndex(options, current);
      final int nextIndex = (currentIndex + direction).clamp(
        0,
        options.length - 1,
      );
      if (nextIndex != currentIndex) {
        onSelected(options[nextIndex]);
      }
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const Text('Scale:', style: TextStyle(color: Colors.white70)),
        _SegmentScaleZoomControl(
          zoomOutTooltip: 'Show more time',
          zoomInTooltip: 'Show less time',
          onZoomOut: () =>
              step(timeOptionsSeconds, timeSeconds, 1, onTimeSelected),
          onZoomIn: () =>
              step(timeOptionsSeconds, timeSeconds, -1, onTimeSelected),
          child: _SegmentScalePillMenu<double>(
            label: 'Time',
            currentValue: timeSeconds,
            valueText: _formatSegmentSeconds(timeSeconds),
            tooltip: 'Time span',
            options: timeOptionsSeconds,
            itemLabelBuilder: _formatSegmentSeconds,
            onSelected: onTimeSelected,
          ),
        ),
        _SegmentScaleZoomControl(
          zoomOutTooltip: 'Show more amplitude',
          zoomInTooltip: 'Show less amplitude',
          onZoomOut: () => step(rangeOptionsUv, rangeUv, 1, onRangeSelected),
          onZoomIn: () => step(rangeOptionsUv, rangeUv, -1, onRangeSelected),
          child: _SegmentScalePillMenu<double>(
            label: 'Range',
            currentValue: rangeUv,
            valueText: '${rangeUv.toStringAsFixed(0)} μV',
            tooltip: 'Signal range',
            options: rangeOptionsUv,
            itemLabelBuilder: (double option) =>
                '${option.toStringAsFixed(0)} μV',
            onSelected: onRangeSelected,
          ),
        ),
        _SegmentScalePillMenu<double>(
          label: 'Spacing',
          currentValue: spacingFactor,
          valueText:
              '${spacingFactor.toStringAsFixed(spacingFactor == spacingFactor.roundToDouble() ? 0 : 2)}x',
          tooltip: 'Channel spacing',
          options: spacingOptions,
          itemLabelBuilder: (double option) =>
              '${option.toStringAsFixed(option == option.roundToDouble() ? 0 : 2)}x',
          onSelected: onSpacingSelected,
        ),
      ],
    );
  }
}

class _SegmentModeTileRow extends StatelessWidget {
  const _SegmentModeTileRow({
    required this.groups,
    required this.selectedLabels,
    required this.includeBad,
    required this.conditionMode,
    required this.channelMode,
    required this.segmentMode,
    required this.selectedConditionCount,
    required this.totalConditionCount,
    required this.totalSegmentCount,
    required this.visibleSegmentCount,
    required this.onConditionLabelsChanged,
    required this.onConditionModeChanged,
    required this.onChannelModeChanged,
    required this.onSegmentModeChanged,
  });

  final List<_SegmentLabelGroup> groups;
  final Set<String> selectedLabels;
  final bool includeBad;
  final String conditionMode;
  final String channelMode;
  final String segmentMode;
  final int selectedConditionCount;
  final int totalConditionCount;
  final int totalSegmentCount;
  final int visibleSegmentCount;
  final ValueChanged<Set<String>> onConditionLabelsChanged;
  final ValueChanged<String> onConditionModeChanged;
  final ValueChanged<String> onChannelModeChanged;
  final ValueChanged<String> onSegmentModeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stackVertically = constraints.maxWidth < 1040;
        final List<Widget> tiles = <Widget>[
          Expanded(
            flex: 7,
            child: _SegmentConditionsModeTile(
              groups: groups,
              selectedLabels: selectedLabels,
              selectedConditionCount: selectedConditionCount,
              totalConditionCount: totalConditionCount,
              conditionMode: conditionMode,
              overlayEnabled: segmentMode == 'average',
              onLabelsChanged: onConditionLabelsChanged,
              onModeChanged: onConditionModeChanged,
            ),
          ),
          const SizedBox(width: 12, height: 12),
          Expanded(
            flex: 5,
            child: _SegmentSegmentsModeTile(
              includeBad: includeBad,
              segmentMode: segmentMode,
              totalSegmentCount: totalSegmentCount,
              visibleSegmentCount: visibleSegmentCount,
              onModeChanged: onSegmentModeChanged,
            ),
          ),
          const SizedBox(width: 12, height: 12),
          Expanded(
            flex: 4,
            child: _SegmentChannelsModeTile(
              channelMode: channelMode,
              onModeChanged: onChannelModeChanged,
            ),
          ),
        ];

        if (stackVertically) {
          return Column(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: _SegmentConditionsModeTile(
                  groups: groups,
                  selectedLabels: selectedLabels,
                  selectedConditionCount: selectedConditionCount,
                  totalConditionCount: totalConditionCount,
                  conditionMode: conditionMode,
                  overlayEnabled: segmentMode == 'average',
                  onLabelsChanged: onConditionLabelsChanged,
                  onModeChanged: onConditionModeChanged,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _SegmentSegmentsModeTile(
                      includeBad: includeBad,
                      segmentMode: segmentMode,
                      totalSegmentCount: totalSegmentCount,
                      visibleSegmentCount: visibleSegmentCount,
                      onModeChanged: onSegmentModeChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SegmentChannelsModeTile(
                      channelMode: channelMode,
                      onModeChanged: onChannelModeChanged,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: tiles,
          ),
        );
      },
    );
  }
}

class _SegmentModeTile extends StatelessWidget {
  const _SegmentModeTile({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            if (hasSubtitle) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SegmentConditionsModeTile extends StatelessWidget {
  const _SegmentConditionsModeTile({
    required this.groups,
    required this.selectedLabels,
    required this.selectedConditionCount,
    required this.totalConditionCount,
    required this.conditionMode,
    required this.overlayEnabled,
    required this.onLabelsChanged,
    required this.onModeChanged,
  });

  final List<_SegmentLabelGroup> groups;
  final Set<String> selectedLabels;
  final int selectedConditionCount;
  final int totalConditionCount;
  final String conditionMode;
  final bool overlayEnabled;
  final ValueChanged<Set<String>> onLabelsChanged;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final List<List<_SegmentLabelGroup>> columns = <List<_SegmentLabelGroup>>[];
    for (int index = 0; index < groups.length; index += 4) {
      columns.add(groups.sublist(index, math.min(groups.length, index + 4)));
    }

    return _SegmentModeTile(
      title: 'Conditions',
      subtitle: '$selectedConditionCount of $totalConditionCount shown',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: columns.isEmpty
                ? const SizedBox.shrink()
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: columns
                        .map((List<_SegmentLabelGroup> column) {
                          return ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: column
                                  .map((_SegmentLabelGroup group) {
                                    final bool selected = selectedLabels
                                        .contains(group.label);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _SegmentConditionChip(
                                        group: group,
                                        selected: selected,
                                        onPressed: () {
                                          final Set<String> nextLabels =
                                              Set<String>.from(selectedLabels);
                                          if (selected) {
                                            nextLabels.remove(group.label);
                                          } else {
                                            nextLabels.add(group.label);
                                          }
                                          onLabelsChanged(nextLabels);
                                        },
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 270,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _SegmentModeOptionButton(
                    label: 'Separate',
                    selected: conditionMode == 'natural',
                    previewKind: _SegmentModePreviewKind.conditionSeparate,
                    onPressed: () => onModeChanged('natural'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SegmentModeOptionButton(
                    label: 'Overlay',
                    selected: conditionMode == 'butterfly',
                    enabled: overlayEnabled,
                    previewKind: _SegmentModePreviewKind.conditionOverlay,
                    onPressed: () => onModeChanged('butterfly'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentSegmentsModeTile extends StatelessWidget {
  const _SegmentSegmentsModeTile({
    required this.includeBad,
    required this.segmentMode,
    required this.totalSegmentCount,
    required this.visibleSegmentCount,
    required this.onModeChanged,
  });

  final bool includeBad;
  final String segmentMode;
  final int totalSegmentCount;
  final int visibleSegmentCount;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return _SegmentModeTile(
      title: 'Segments',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _SegmentInfoPill(
                label: 'Total',
                value: totalSegmentCount.toString(),
              ),
              _SegmentInfoPill(
                label: 'Showing',
                value: visibleSegmentCount.toString(),
                accentColor: const Color(0xFF4DD9FF),
              ),
              _SegmentInfoPill(
                label: 'Bad',
                value: includeBad ? 'included' : 'hidden',
                accentColor: includeBad
                    ? const Color(0xFFFFD166)
                    : Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _SegmentModeOptionButton(
                  label: 'Stitched',
                  selected: segmentMode == 'natural',
                  previewKind: _SegmentModePreviewKind.segmentStitched,
                  onPressed: () => onModeChanged('natural'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegmentModeOptionButton(
                  label: 'Butterfly',
                  selected: segmentMode == 'butterfly',
                  previewKind: _SegmentModePreviewKind.segmentButterfly,
                  onPressed: () => onModeChanged('butterfly'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegmentModeOptionButton(
                  label: 'Average',
                  selected: segmentMode == 'average',
                  previewKind: _SegmentModePreviewKind.segmentAverage,
                  onPressed: () => onModeChanged('average'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentInfoPill extends StatelessWidget {
  const _SegmentInfoPill({
    required this.label,
    required this.value,
    this.accentColor,
  });

  final String label;
  final String value;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final Color color = accentColor ?? Colors.white70;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              '$label $value',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentChannelsModeTile extends StatelessWidget {
  const _SegmentChannelsModeTile({
    required this.channelMode,
    required this.onModeChanged,
  });

  final String channelMode;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return _SegmentModeTile(
      title: 'Channels',
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SegmentModeOptionButton(
              label: 'Stack',
              selected: channelMode == 'natural',
              previewKind: _SegmentModePreviewKind.channelStack,
              onPressed: () => onModeChanged('natural'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SegmentModeOptionButton(
              label: 'Butterfly',
              selected: channelMode == 'butterfly',
              previewKind: _SegmentModePreviewKind.channelButterfly,
              onPressed: () => onModeChanged('butterfly'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SegmentModeOptionButton(
              label: 'Average',
              selected: channelMode == 'average',
              previewKind: _SegmentModePreviewKind.channelAverage,
              onPressed: () => onModeChanged('average'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentConditionChip extends StatelessWidget {
  const _SegmentConditionChip({
    required this.group,
    required this.selected,
    required this.onPressed,
  });

  final _SegmentLabelGroup group;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? group.color.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? group.color.withValues(alpha: 0.82)
                  : Colors.white.withValues(alpha: 0.1),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: group.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${group.segments.length}',
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentModeOptionButton extends StatelessWidget {
  const _SegmentModeOptionButton({
    required this.label,
    required this.selected,
    required this.previewKind,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final _SegmentModePreviewKind previewKind;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = selected
        ? const Color(0xFF58D3FF)
        : Colors.white.withValues(alpha: 0.28);
    return Opacity(
      opacity: enabled ? 1.0 : 0.42,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onPressed : null,
          child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? accentColor.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.1),
                width: selected ? 1.5 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _SegmentModePreviewPainter(
                        kind: previewKind,
                        foregroundColor: accentColor,
                        secondaryColor: const Color(0xFFFFD166),
                        tertiaryColor: const Color(0xFFFF7B7B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SegmentModePreviewKind {
  conditionSeparate,
  conditionOverlay,
  channelStack,
  channelButterfly,
  channelAverage,
  segmentStitched,
  segmentButterfly,
  segmentAverage,
}

class _SegmentModePreviewPainter extends CustomPainter {
  const _SegmentModePreviewPainter({
    required this.kind,
    required this.foregroundColor,
    required this.secondaryColor,
    required this.tertiaryColor,
  });

  final _SegmentModePreviewKind kind;
  final Color foregroundColor;
  final Color secondaryColor;
  final Color tertiaryColor;

  static const List<double> _waveA = <double>[
    0.10,
    0.18,
    -0.04,
    -0.28,
    0.34,
    0.11,
    -0.08,
    0.16,
    0.06,
  ];

  static const List<double> _waveB = <double>[
    -0.08,
    0.04,
    0.25,
    -0.18,
    -0.02,
    0.24,
    -0.12,
    -0.08,
    0.14,
  ];

  static const List<double> _waveC = <double>[
    0.02,
    -0.08,
    0.16,
    0.10,
    -0.20,
    0.24,
    0.08,
    -0.14,
    0.02,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect frame = RRect.fromRectAndRadius(
      rect.deflate(1),
      const Radius.circular(10),
    );
    final Paint framePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(frame, framePaint);
    canvas.drawRRect(frame, borderPaint);

    switch (kind) {
      case _SegmentModePreviewKind.conditionSeparate:
        _paintConditionSeparate(canvas, rect.deflate(5));
        return;
      case _SegmentModePreviewKind.conditionOverlay:
        _paintOverlay(canvas, rect.deflate(5), <Color>[
          foregroundColor,
          secondaryColor,
          tertiaryColor,
        ], normalizeToSignalRange: true);
        return;
      case _SegmentModePreviewKind.channelStack:
        _paintStacked(canvas, rect.deflate(5), <Color>[
          foregroundColor,
          secondaryColor,
          tertiaryColor,
        ]);
        return;
      case _SegmentModePreviewKind.channelButterfly:
        _paintOverlay(canvas, rect.deflate(5), <Color>[
          foregroundColor,
          secondaryColor,
          tertiaryColor,
        ], normalizeToSignalRange: true);
        return;
      case _SegmentModePreviewKind.channelAverage:
        _paintAverage(canvas, rect.deflate(5), foregroundColor);
        return;
      case _SegmentModePreviewKind.segmentStitched:
        _paintStitched(canvas, rect.deflate(5));
        return;
      case _SegmentModePreviewKind.segmentButterfly:
        _paintOverlay(canvas, rect.deflate(5), <Color>[
          foregroundColor,
          foregroundColor.withValues(alpha: 0.75),
          secondaryColor.withValues(alpha: 0.8),
        ], normalizeToSignalRange: true);
        return;
      case _SegmentModePreviewKind.segmentAverage:
        _paintAverage(canvas, rect.deflate(5), foregroundColor);
        return;
    }
  }

  void _paintConditionSeparate(Canvas canvas, Rect rect) {
    final double gap = 6;
    final double panelWidth = (rect.width - gap) / 2;
    final Rect left = Rect.fromLTWH(
      rect.left,
      rect.top,
      panelWidth,
      rect.height,
    );
    final Rect right = Rect.fromLTWH(
      left.right + gap,
      rect.top,
      panelWidth,
      rect.height,
    );
    _paintMiniFrame(canvas, left);
    _paintMiniFrame(canvas, right);
    _drawTrace(canvas, left, _waveA, foregroundColor, amplitude: 0.62);
    _drawTrace(canvas, right, _waveB, secondaryColor, amplitude: 0.62);
  }

  void _paintOverlay(
    Canvas canvas,
    Rect rect,
    List<Color> colors, {
    bool normalizeToSignalRange = false,
  }) {
    _paintMiniFrame(canvas, rect);
    _drawTrace(
      canvas,
      rect,
      _waveA,
      colors[0],
      amplitude: normalizeToSignalRange ? 0.95 : 0.62,
      normalizeToSignalRange: normalizeToSignalRange,
    );
    _drawTrace(
      canvas,
      rect,
      _waveB,
      colors[1],
      amplitude: normalizeToSignalRange ? 0.95 : 0.54,
      normalizeToSignalRange: normalizeToSignalRange,
    );
    _drawTrace(
      canvas,
      rect,
      _waveC,
      colors[2],
      amplitude: normalizeToSignalRange ? 0.95 : 0.48,
      normalizeToSignalRange: normalizeToSignalRange,
    );
  }

  void _paintStacked(Canvas canvas, Rect rect, List<Color> colors) {
    _paintMiniFrame(canvas, rect);
    _drawTrace(
      canvas,
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height / 3),
      _waveA,
      colors[0],
      amplitude: 0.55,
      centerBias: 0.5,
    );
    _drawTrace(
      canvas,
      Rect.fromLTWH(
        rect.left,
        rect.top + (rect.height / 3),
        rect.width,
        rect.height / 3,
      ),
      _waveB,
      colors[1],
      amplitude: 0.55,
      centerBias: 0.5,
    );
    _drawTrace(
      canvas,
      Rect.fromLTWH(
        rect.left,
        rect.top + ((rect.height / 3) * 2),
        rect.width,
        rect.height / 3,
      ),
      _waveC,
      colors[2],
      amplitude: 0.55,
      centerBias: 0.5,
    );
  }

  void _paintAverage(Canvas canvas, Rect rect, Color color) {
    _paintMiniFrame(canvas, rect);
    final List<Offset> upperPoints = _tracePoints(
      rect,
      _waveA,
      amplitude: 0.48,
      offset: -0.14,
    );
    final List<Offset> lowerPoints = _tracePoints(
      rect,
      _waveA,
      amplitude: 0.48,
      offset: 0.14,
    );
    final Path area = Path()..addPolygon(upperPoints, false);
    for (final Offset point in lowerPoints.reversed) {
      area.lineTo(point.dx, point.dy);
    }
    area.close();
    canvas.drawPath(
      area,
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );
    _drawTrace(canvas, rect, _waveA, color, amplitude: 0.48);
  }

  void _paintStitched(Canvas canvas, Rect rect) {
    _paintMiniFrame(canvas, rect);
    final Paint dividerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final double sectionWidth = rect.width / 3;
    for (int index = 1; index < 3; index++) {
      final double x = rect.left + (sectionWidth * index);
      canvas.drawLine(
        Offset(x, rect.top + 2),
        Offset(x, rect.bottom - 2),
        dividerPaint,
      );
    }
    _drawTrace(
      canvas,
      Rect.fromLTWH(rect.left, rect.top, sectionWidth, rect.height),
      _waveA,
      foregroundColor,
      amplitude: 0.56,
    );
    _drawTrace(
      canvas,
      Rect.fromLTWH(
        rect.left + sectionWidth,
        rect.top,
        sectionWidth,
        rect.height,
      ),
      _waveB,
      foregroundColor,
      amplitude: 0.56,
    );
    _drawTrace(
      canvas,
      Rect.fromLTWH(
        rect.left + (sectionWidth * 2),
        rect.top,
        sectionWidth,
        rect.height,
      ),
      _waveC,
      foregroundColor,
      amplitude: 0.56,
    );
  }

  void _paintMiniFrame(Canvas canvas, Rect rect) {
    final RRect mini = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(
      mini,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      mini,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawTrace(
    Canvas canvas,
    Rect rect,
    List<double> wave,
    Color color, {
    double amplitude = 0.6,
    double centerBias = 0.0,
    bool normalizeToSignalRange = false,
  }) {
    canvas.drawPath(
      _tracePath(
        rect,
        wave,
        amplitude: amplitude,
        centerBias: centerBias,
        normalizeToSignalRange: normalizeToSignalRange,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _tracePath(
    Rect rect,
    List<double> wave, {
    double amplitude = 0.6,
    double offset = 0.0,
    double centerBias = 0.0,
    bool normalizeToSignalRange = false,
  }) {
    final List<Offset> points = _tracePoints(
      rect,
      wave,
      amplitude: amplitude,
      offset: offset,
      centerBias: centerBias,
      normalizeToSignalRange: normalizeToSignalRange,
    );
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int index = 1; index < points.length; index++) {
      path.lineTo(points[index].dx, points[index].dy);
    }
    return path;
  }

  List<Offset> _tracePoints(
    Rect rect,
    List<double> wave, {
    double amplitude = 0.6,
    double offset = 0.0,
    double centerBias = 0.0,
    bool normalizeToSignalRange = false,
  }) {
    final double centerY = rect.center.dy + (offset * rect.height);
    final double halfHeight = rect.height * 0.34 * amplitude;
    final double minValue = wave.reduce(math.min);
    final double maxValue = wave.reduce(math.max);
    final double span = math.max(0.001, maxValue - minValue);
    return List<Offset>.generate(wave.length, (int index) {
      final double t = wave.length == 1 ? 0.0 : index / (wave.length - 1);
      final double x = rect.left + (t * rect.width);
      final double value = normalizeToSignalRange
          ? (((wave[index] - minValue) / span) * 2.0 - 1.0)
          : wave[index] + centerBias;
      final double y = centerY - (value * halfHeight);
      return Offset(x, y);
    }, growable: false);
  }

  @override
  bool shouldRepaint(covariant _SegmentModePreviewPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.foregroundColor != foregroundColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.tertiaryColor != tertiaryColor;
  }
}

String _formatSegmentSeconds(double seconds) {
  final String value = seconds < 1
      ? seconds
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '')
      : seconds.toStringAsFixed(0);
  return '$value s';
}

class _SegmentScaleZoomControl extends StatelessWidget {
  const _SegmentScaleZoomControl({
    required this.child,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.zoomOutTooltip,
    required this.zoomInTooltip,
  });

  final Widget child;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final String zoomOutTooltip;
  final String zoomInTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        child,
        IconButton(
          tooltip: zoomOutTooltip,
          onPressed: onZoomOut,
          icon: const Icon(Icons.zoom_out, size: 18),
          color: Colors.white70,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          padding: EdgeInsets.zero,
        ),
        IconButton(
          tooltip: zoomInTooltip,
          onPressed: onZoomIn,
          icon: const Icon(Icons.zoom_in, size: 18),
          color: Colors.white70,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _SegmentScalePillMenu<T> extends StatelessWidget {
  const _SegmentScalePillMenu({
    required this.label,
    required this.currentValue,
    required this.valueText,
    required this.tooltip,
    required this.options,
    required this.itemLabelBuilder,
    required this.onSelected,
  });

  final String label;
  final T currentValue;
  final String valueText;
  final String tooltip;
  final List<T> options;
  final String Function(T value) itemLabelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    void stepByWheel(PointerSignalEvent event) {
      if (event is! PointerScrollEvent || options.isEmpty) {
        return;
      }
      final int currentIndex = options.indexOf(currentValue);
      if (currentIndex < 0) {
        return;
      }
      final int nextIndex = event.scrollDelta.dy > 0
          ? math.min(options.length - 1, currentIndex + 1)
          : math.max(0, currentIndex - 1);
      if (nextIndex != currentIndex) {
        onSelected(options[nextIndex]);
      }
    }

    return Tooltip(
      message: tooltip,
      child: Listener(
        onPointerSignal: stepByWheel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: PopupMenuButton<T>(
            tooltip: '',
            onSelected: onSelected,
            itemBuilder: (BuildContext context) {
              return options
                  .map(
                    (T option) => PopupMenuItem<T>(
                      value: option,
                      child: Text(itemLabelBuilder(option)),
                    ),
                  )
                  .toList(growable: false);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  '$label: $valueText',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentInlineToggleButton extends StatelessWidget {
  const _SegmentInlineToggleButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final double buttonWidth = painter.width + 40;
    return SizedBox(
      width: buttonWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size(buttonWidth, 34),
            backgroundColor: selected
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.04),
            foregroundColor: selected ? Colors.white : Colors.white70,
            side: BorderSide(
              color: selected
                  ? Colors.white.withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            shape: const StadiumBorder(),
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
            animationDuration: Duration.zero,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PsdMenuChip<T> extends StatelessWidget {
  const _PsdMenuChip({
    required this.label,
    required this.valueLabel,
    required this.options,
    required this.itemLabel,
    required this.onSelected,
  });

  final String label;
  final String valueLabel;
  final List<T> options;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (BuildContext context) {
        return options
            .map(
              (T option) => PopupMenuItem<T>(
                value: option,
                child: Text(itemLabel(option)),
              ),
            )
            .toList(growable: false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$label: $valueLabel',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class _BandRange {
  const _BandRange(this.startHz, this.endHz, this.color);

  final double startHz;
  final double endHz;
  final Color color;
}

List<VerticalRangeAnnotation> _canonicalBandAnnotations(double maxHz) {
  final List<_BandRange> bands = <_BandRange>[
    const _BandRange(0, 4, Color(0x223A86FF)),
    const _BandRange(4, 8, Color(0x2237C871)),
    const _BandRange(8, 12, Color(0x22FFD54F)),
    const _BandRange(12, 40, Color(0x22FF8A65)),
    _BandRange(40, maxHz, const Color(0x22CE93D8)),
  ];

  return bands
      .where(
        (_BandRange band) => band.startHz < maxHz && band.endHz > band.startHz,
      )
      .map(
        (_BandRange band) => VerticalRangeAnnotation(
          x1: band.startHz,
          x2: math.min(band.endHz, maxHz),
          color: band.color,
        ),
      )
      .toList(growable: false);
}

Color _seriesColor(int index) {
  const List<Color> palette = <Color>[
    Colors.cyanAccent,
    Colors.orangeAccent,
    Colors.lightGreenAccent,
    Colors.pinkAccent,
    Colors.amberAccent,
    Colors.deepPurpleAccent,
  ];

  return palette[index % palette.length];
}

Color _sleepStageColor(String stageLabel) {
  switch (stageLabel.trim().toUpperCase()) {
    case 'WAKE':
      return Colors.orangeAccent;
    case 'REM':
      return Colors.cyanAccent;
    case 'SWS':
      return Colors.deepPurpleAccent;
    default:
      return Colors.white70;
  }
}

Widget _emptyState(String title, String body) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );
}

class _ChartMessage extends StatelessWidget {
  const _ChartMessage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _emptyState(title, body);
  }
}

FlTitlesData _chartTitles({
  required double minX,
  required double maxX,
  required double minY,
  required double maxY,
  bool logY = false,
  String xAxisLabel = 'Hz',
  String? yAxisLabel,
  bool showYValues = true,
  double yAxisReservedSize = 56,
  double xAxisNameSize = 16,
  double yAxisNameSize = 16,
  bool wholeNumberYLabels = false,
}) {
  final double xInterval = _niceAxisStep(maxX - minX);
  final double yInterval = _niceAxisStep(maxY - minY);
  final String resolvedYAxisLabel =
      yAxisLabel ?? (logY ? 'log10(uV^2/Hz)' : 'uV^2/Hz');
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      axisNameSize: xAxisLabel.trim().isEmpty ? 0 : xAxisNameSize,
      axisNameWidget: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          xAxisLabel,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: xInterval,
        getTitlesWidget: (double value, TitleMeta meta) {
          if (value < minX - 0.001 || value > maxX + 0.001) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            axisSide: meta.axisSide,
            child: Text(
              value.toStringAsFixed(0),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          );
        },
      ),
    ),
    leftTitles: AxisTitles(
      axisNameSize: resolvedYAxisLabel.trim().isEmpty ? 0 : yAxisNameSize,
      axisNameWidget: resolvedYAxisLabel.trim().isEmpty
          ? const SizedBox.shrink()
          : RotatedBox(
              quarterTurns: 1,
              child: Text(
                resolvedYAxisLabel,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: yAxisReservedSize,
        interval: yInterval,
        getTitlesWidget: (double value, TitleMeta meta) {
          if (!showYValues || value < minY - 0.001 || value > maxY + 0.001) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            axisSide: meta.axisSide,
            child: Text(
              _formatAxisValue(
                value,
                logY: logY,
                wholeNumber: wholeNumberYLabels,
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          );
        },
      ),
    ),
  );
}

double _niceAxisStep(double range) {
  final double safeRange = range <= 0 ? 1.0 : range;
  final double roughStep = safeRange / 4.0;
  final double exponent = math
      .pow(10, (math.log(roughStep) / math.ln10).floor())
      .toDouble();
  final double fraction = roughStep / exponent;
  final double niceFraction = fraction <= 1
      ? 1
      : fraction <= 2
      ? 2
      : fraction <= 5
      ? 5
      : 10;
  return niceFraction * exponent;
}

String _formatAxisValue(
  double value, {
  required bool logY,
  bool wholeNumber = false,
}) {
  if (logY) {
    return '1e${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}';
  }
  if (wholeNumber) {
    return value.round().toString();
  }
  final double absolute = value.abs();
  if (absolute >= 100) {
    return value.toStringAsFixed(0);
  }
  if (absolute >= 10) {
    return value.toStringAsFixed(1);
  }
  if (absolute >= 1) {
    return value.toStringAsFixed(2);
  }
  return value.toStringAsFixed(3);
}
