import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/node.dart';
import '../platform/brainstory_engine.dart';
import '../nodes/sleep_staging_node.dart';
import 'canvas_logic.dart';
import 'raw_signal_browser.dart';
import 'viewer_interaction.dart';

class VisualizationPanel extends StatelessWidget {
  const VisualizationPanel({
    super.key,
    required this.logic,
    required this.onChanged,
    required this.onOpenWindow,
  });

  final CanvasLogic logic;
  final VoidCallback onChanged;
  final VoidCallback onOpenWindow;

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

    if (!logic.canVisualizeNode(node)) {
      return _panelShell(
        child: _emptyState(
          'No visual output',
          '${node.title} does not produce a time-domain or spectrum view to render here.',
        ),
      );
    }

    if (logic.isVisualizationNode(node) &&
        logic.visualizationDisplayMode(node) == 'window') {
      return _panelShell(
        child: _WindowModeMessage(
          title: node.title,
          onOpenWindow: onOpenWindow,
        ),
      );
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
  Future<List<_VisualizationSourceView>>? _materializedDatasetsFuture;
  String _materializedDatasetsKey = '';

  CanvasLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _syncSelectedDatasets(
      logic.visualizationSourceRefsForNode(widget.nodeId),
    );
  }

  @override
  void didUpdateWidget(covariant VisualizationSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      _selectedSourceKeys.clear();
      _activeSourceKey = null;
      _materializedDatasetsFuture = null;
      _materializedDatasetsKey = '';
    }
    _syncSelectedDatasets(
      logic.visualizationSourceRefsForNode(widget.nodeId),
    );
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
    final List<VisualizationSourceRef> sourceRefs =
        logic.visualizationSourceRefsForNode(widget.nodeId);
    _syncSelectedDatasets(sourceRefs);
    final bool comparisonNode = logic.isVisualizationNode(node);
    final List<VisualizationSourceRef> selectedSourceRefs =
        _selectedSourceRefs(sourceRefs);
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
              style: const TextStyle(
                color: Colors.white70,
                height: 1.2,
              ),
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
            child: FutureBuilder<List<_VisualizationSourceView>>(
              future: _materializedDatasetsFuture,
              builder: (BuildContext context, AsyncSnapshot<List<_VisualizationSourceView>> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
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
                final List<_VisualizationSourceView> sourceViews =
                    snapshot.data ?? const <_VisualizationSourceView>[];
                final List<Dataset> datasets = sourceViews
                    .map((_VisualizationSourceView view) => view.dataset)
                    .toList(growable: false);
                final String view = logic.visualizationViewForNodeAndDatasets(
                  node,
                  datasets,
                );
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
                        initialValue: _activeSourceKey ?? selectedSourceRefs.first.key,
                        decoration: const InputDecoration(
                          labelText: 'Active pathway',
                        ),
                        items: selectedSourceRefs
                            .map(
                              (VisualizationSourceRef source) => DropdownMenuItem<String>(
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
                    if (needsActiveDatasetPicker) const SizedBox(height: 12),
                    Expanded(
                      child: _VisualizationChart(
                        logic: logic,
                        nodeId: node.id,
                        datasets: _selectedDatasets(sourceViews),
                        activeDatasetId: _activeSourceKey,
                        view: view,
                        params: node.params,
                        comparisonNode: comparisonNode,
                        onChanged: () {
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

  List<VisualizationSourceRef> _selectedSourceRefs(
    List<VisualizationSourceRef> sources,
  ) {
    return sources
        .where((VisualizationSourceRef source) => _selectedSourceKeys.contains(source.key))
        .toList(growable: false);
  }

  List<Dataset> _selectedDatasets(List<_VisualizationSourceView> views) {
    return views
        .where(
          (_VisualizationSourceView view) =>
              _selectedSourceKeys.contains(view.source.key),
        )
        .map((_VisualizationSourceView view) => view.dataset)
        .toList(growable: false);
  }

  void _syncSelectedDatasets(List<VisualizationSourceRef> sources) {
    if (sources.isEmpty) {
      _selectedSourceKeys.clear();
      _activeSourceKey = null;
      _materializedDatasetsFuture =
          Future<List<_VisualizationSourceView>>.value(const <_VisualizationSourceView>[]);
      _materializedDatasetsKey = '';
      return;
    }

    final Set<String> availableKeys =
        sources.map((VisualizationSourceRef source) => source.key).toSet();
    _selectedSourceKeys.removeWhere((String key) => !availableKeys.contains(key));
    if (_selectedSourceKeys.isEmpty) {
      _selectedSourceKeys.addAll(
        sources.map((VisualizationSourceRef source) => source.key),
      );
    }
    if (_activeSourceKey == null || !_selectedSourceKeys.contains(_activeSourceKey)) {
      _activeSourceKey = _selectedSourceKeys.isEmpty ? null : _selectedSourceKeys.first;
    }
    if (_activeSourceKey != null && !_selectedSourceKeys.contains(_activeSourceKey)) {
      _activeSourceKey = _selectedSourceKeys.isEmpty ? null : _selectedSourceKeys.first;
    }
  }

  void _refreshMaterializedDatasets(List<VisualizationSourceRef> selectedSourceRefs) {
    final String key = <String>[
      widget.nodeId,
      ...selectedSourceRefs.map((VisualizationSourceRef source) => source.key),
    ].join('|');
    if (_materializedDatasetsFuture != null && _materializedDatasetsKey == key) {
      return;
    }
    _materializedDatasetsKey = key;
    _materializedDatasetsFuture = _materializeSourceViews(selectedSourceRefs);
  }

  Future<List<_VisualizationSourceView>> _materializeSourceViews(
    List<VisualizationSourceRef> selectedSourceRefs,
  ) async {
    final List<_VisualizationSourceView> views = <_VisualizationSourceView>[];
    for (final VisualizationSourceRef source in selectedSourceRefs) {
      views.add(
        _VisualizationSourceView(
          source: source,
          dataset: await logic.materializedDatasetViewForSourceRef(source),
        ),
      );
    }
    return views;
  }
}

class _VisualizationSourceView {
  const _VisualizationSourceView({
    required this.source,
    required this.dataset,
  });

  final VisualizationSourceRef source;
  final Dataset dataset;
}

class _WindowModeMessage extends StatelessWidget {
  const _WindowModeMessage({
    required this.title,
    required this.onOpenWindow,
  });

  final String title;
  final VoidCallback onOpenWindow;

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
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onOpenWindow,
            child: const Text('Open Window'),
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
  });

  final CanvasLogic logic;
  final String nodeId;
  final List<Dataset> datasets;
  final String? activeDatasetId;
  final String view;
  final Map<String, dynamic> params;
  final bool comparisonNode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Dataset resolveActiveDataset() {
      return datasets.firstWhere(
        (Dataset dataset) => dataset.ram['viewer.sourceKey'] == activeDatasetId,
        orElse: () => datasets.first,
      );
    }

    Widget withPendingStructurePreview(
      Widget child,
      List<_PendingViewerNode> pendingNodes,
    ) {
      if (pendingNodes.isEmpty) {
        return child;
      }
      return Stack(
        children: <Widget>[
          Positioned.fill(child: child),
          Positioned(
            right: 12,
            bottom: 12,
            child: _PendingViewerStructurePreview(
              sourceLabel: 'Viewer',
              nodes: pendingNodes,
            ),
          ),
        ],
      );
    }

    if (datasets.isEmpty) {
      return const _ChartMessage(
        title: 'No dataset selected',
        body: 'Choose one or more datasets above to render the visualization.',
      );
    }

    if (view == 'time_frequency') {
      return const _ChartMessage(
        title: 'Time-frequency view is not implemented yet',
        body: 'This visualizer can already infer the upstream output type, but the time-frequency renderer still needs to be built.',
      );
    }

    if (view == 'psd') {
      return _PsdChart(
        datasets: datasets,
        params: params,
        onChanged: onChanged,
      );
    }
    if (view == 'bridge') {
      final Dataset activeDataset = resolveActiveDataset();
      return _BridgeHeatmapChart(
        dataset: activeDataset,
        params: params,
        onChanged: onChanged,
      );
    }
    if (view == 'hypnogram') {
      final Dataset activeDataset = resolveActiveDataset();
      return _HypnogramChart(dataset: activeDataset);
    }
    if (view == 'topomap') {
      final Dataset activeDataset = resolveActiveDataset();
      return _TopomapChart(
        dataset: activeDataset,
        params: params,
      );
    }
    if (view == 'segments') {
      final Dataset activeDataset = resolveActiveDataset();
      return withPendingStructurePreview(
        _SegmentedChart(
          dataset: activeDataset,
          params: params,
        ),
        _pendingSegmentViewerNodes(params),
      );
    }
    if (comparisonNode && datasets.length > 1) {
      return const _ChartMessage(
        title: 'Raw comparison is not ready yet',
        body: 'Select one dataset for the raw browser. PSD comparison overlays are inferred and rendered automatically when this node is fed from a PSD path.',
      );
    }
    final Dataset activeDataset = resolveActiveDataset();
    return withPendingStructurePreview(
      RawSignalBrowser(
        dataset: activeDataset,
        params: params,
        onMarkersChanged: (List<dynamic> rawMarkers) {
          logic.applyMarkersFromVisualization(
            nodeId: nodeId,
            dataset: activeDataset,
            rawMarkers: rawMarkers,
          );
        },
        onChannelEditsSaved: (Map<String, dynamic> config) {
          logic.applyChannelEditsFromVisualization(
            nodeId: nodeId,
            dataset: activeDataset,
            datasetConfig: config,
          );
        },
        onInteractiveArtifactDetectionSaved: () {
          final String message =
              logic.applyInteractiveArtifactDetectionFromVisualization(
            nodeId: nodeId,
            dataset: activeDataset,
          );
          onChanged();
          return message;
        },
        onSaveAndQuit: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          logic.selectedNodeId = null;
          onChanged();
        },
        onChanged: onChanged,
      ),
      _pendingRawViewerNodes(params),
    );
  }
}

class _PendingViewerNode {
  const _PendingViewerNode({
    required this.label,
    required this.detail,
    required this.color,
  });

  final String label;
  final String detail;
  final Color color;
}

List<_PendingViewerNode> _pendingSegmentViewerNodes(
  Map<String, dynamic> params,
) {
  final List<_PendingViewerNode> nodes = <_PendingViewerNode>[];
  final bool displayBaseline =
      params['segmented_display_baseline'] as bool? ?? true;
  final bool bakedBaseline = params['eventBaselineEnabled'] as bool? ?? false;
  if (displayBaseline && !bakedBaseline) {
    final double startMs =
        (params['eventBaselineStartMs'] as num?)?.toDouble() ?? -200.0;
    final double stopMs =
        (params['eventBaselineStopMs'] as num?)?.toDouble() ?? 0.0;
    nodes.add(
      _PendingViewerNode(
        label: 'Baseline',
        detail: '${startMs.toStringAsFixed(0)} to ${stopMs.toStringAsFixed(0)} ms',
        color: Colors.yellowAccent,
      ),
    );
  }
  if (params['segmented_display_average'] as bool? ?? false) {
    nodes.add(
      const _PendingViewerNode(
        label: 'Average',
        detail: 'Across visible segments',
        color: Colors.orangeAccent,
      ),
    );
  }
  return nodes;
}

List<_PendingViewerNode> _pendingRawViewerNodes(Map<String, dynamic> params) {
  if ((params['interaction_mode']?.toString() ?? 'view') == 'interactive') {
    return const <_PendingViewerNode>[
      _PendingViewerNode(
        label: 'Interactive Artifact Detection',
        detail: 'Templates, exemplars, and candidate matches',
        color: Colors.orangeAccent,
      ),
    ];
  }
  return const <_PendingViewerNode>[];
}

class _PendingViewerStructurePreview extends StatelessWidget {
  const _PendingViewerStructurePreview({
    required this.sourceLabel,
    required this.nodes,
  });

  final String sourceLabel;
  final List<_PendingViewerNode> nodes;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Will add to story',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _MiniPipelineNode(
                    label: sourceLabel,
                    detail: 'current output',
                    color: Colors.blueAccent,
                    filled: false,
                  ),
                  for (final _PendingViewerNode node in nodes) ...<Widget>[
                    const _MiniPipelineEdge(),
                    _MiniPipelineNode(
                      label: node.label,
                      detail: node.detail,
                      color: node.color,
                      filled: true,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPipelineEdge extends StatelessWidget {
  const _MiniPipelineEdge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: Center(
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _MiniPipelineNode extends StatelessWidget {
  const _MiniPipelineNode({
    required this.label,
    required this.detail,
    required this.color,
    required this.filled,
  });

  final String label;
  final String detail;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: filled ? 0.8 : 0.48),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopomapChart extends StatelessWidget {
  const _TopomapChart({
    required this.dataset,
    required this.params,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;

  @override
  Widget build(BuildContext context) {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) {
      return const _ChartMessage(
        title: 'No signal available',
        body: 'Connect this topomap node to a time-domain dataset.',
      );
    }
    if (timeSeries.channelCoordinates.isEmpty) {
      return const _ChartMessage(
        title: 'No channel positions',
        body: 'Run Channel Positions upstream first, then connect that path to the topomap.',
      );
    }

    final List<_TopomapPoint> points = _topomapPointsForTimeSeries(timeSeries);
    if (points.length < 3) {
      return const _ChartMessage(
        title: 'Not enough mapped channels',
        body: 'Topomap rendering needs at least three channels with coordinates.',
      );
    }

    final bool showElectrodes = params['show_electrodes'] as bool? ?? true;
    final bool showLabels = params['show_labels'] as bool? ?? true;
    final double minValue = points.map((_TopomapPoint point) => point.value).reduce(math.min);
    final double maxValue = points.map((_TopomapPoint point) => point.value).reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              'Preview RMS topomap • ${points.length}/${timeSeries.channelCount} channels mapped',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${minValue.toStringAsFixed(1)} to ${maxValue.toStringAsFixed(1)} uV',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                child: CustomPaint(
                  painter: _TopomapPainter(
                    points: points,
                    minValue: minValue,
                    maxValue: maxValue,
                    showElectrodes: showElectrodes,
                    showLabels: showLabels,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 54,
                child: _TopomapColorbar(
                  minValue: minValue,
                  maxValue: maxValue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopomapPoint {
  const _TopomapPoint({
    required this.label,
    required this.position,
    required this.value,
  });

  final String label;
  final Offset position;
  final double value;
}

List<_TopomapPoint> _topomapPointsForTimeSeries(TimeSeriesData timeSeries) {
  final List<List<double>> channels = timeSeries.channels;
  if (channels.isEmpty) {
    return const <_TopomapPoint>[];
  }

  double maxRadius = 1.0;
  for (final ChannelCoordinate coordinate in timeSeries.channelCoordinates.values) {
    maxRadius = math.max(
      maxRadius,
      math.sqrt((coordinate.x * coordinate.x) + (coordinate.y * coordinate.y)),
    );
  }

  final List<_TopomapPoint> points = <_TopomapPoint>[];
  for (int index = 0; index < channels.length; index++) {
    final String label = index < timeSeries.channelLabels.length
        ? timeSeries.channelLabels[index]
        : 'Ch ${index + 1}';
    final ChannelCoordinate? coordinate =
        timeSeries.channelCoordinates[label] ??
            _coordinateForDecoratedChannelLabel(timeSeries.channelCoordinates, label);
    if (coordinate == null) {
      continue;
    }
    points.add(
      _TopomapPoint(
        label: label,
        position: Offset(coordinate.x / maxRadius, -coordinate.y / maxRadius),
        value: _rmsPreviewValue(channels[index]),
      ),
    );
  }
  return points;
}

ChannelCoordinate? _coordinateForDecoratedChannelLabel(
  Map<String, ChannelCoordinate> coordinates,
  String label,
) {
  final String normalizedLabel = _normalizeTopomapLabel(label);
  for (final MapEntry<String, ChannelCoordinate> entry in coordinates.entries) {
    final String normalizedCoordinateLabel = _normalizeTopomapLabel(entry.key);
    if (normalizedCoordinateLabel == normalizedLabel ||
        normalizedLabel.startsWith('$normalizedCoordinateLabel-')) {
      return entry.value;
    }
  }
  return null;
}

String _normalizeTopomapLabel(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');
}

double _rmsPreviewValue(List<double> samples) {
  if (samples.isEmpty) {
    return 0.0;
  }
  final int stride = math.max(1, (samples.length / 2000).ceil());
  double sumSquares = 0.0;
  int count = 0;
  for (int index = 0; index < samples.length; index += stride) {
    final double value = samples[index];
    sumSquares += value * value;
    count++;
  }
  return count == 0 ? 0.0 : math.sqrt(sumSquares / count);
}

class _TopomapPainter extends CustomPainter {
  const _TopomapPainter({
    required this.points,
    required this.minValue,
    required this.maxValue,
    required this.showElectrodes,
    required this.showLabels,
  });

  final List<_TopomapPoint> points;
  final double minValue;
  final double maxValue;
  final bool showElectrodes;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = side * 0.42;
    final Rect headRect = Rect.fromCircle(center: center, radius: radius);

    canvas.save();
    canvas.clipPath(Path()..addOval(headRect));
    final int grid = math.max(44, math.min(84, (side / 7).round()));
    final double cell = (radius * 2) / grid;
    for (int row = 0; row < grid; row++) {
      for (int column = 0; column < grid; column++) {
        final Offset point = Offset(
          center.dx - radius + (column + 0.5) * cell,
          center.dy - radius + (row + 0.5) * cell,
        );
        final Offset normalized = Offset(
          (point.dx - center.dx) / radius,
          (point.dy - center.dy) / radius,
        );
        if (normalized.distance > 1.0) {
          continue;
        }
        final double value = _interpolatedValue(normalized);
        canvas.drawRect(
          Rect.fromLTWH(point.dx - cell / 2, point.dy - cell / 2, cell + 0.6, cell + 0.6),
          Paint()..color = _topomapColor(value, minValue, maxValue),
        );
      }
    }
    canvas.restore();

    final Paint outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawOval(headRect, outlinePaint);
    _drawHeadLandmarks(canvas, center, radius, outlinePaint);

    if (showElectrodes || showLabels) {
      for (final _TopomapPoint point in points) {
        final Offset projected = center + point.position * radius;
        if (showElectrodes) {
          canvas.drawCircle(
            projected,
            4.2,
            Paint()
              ..color = Colors.black.withValues(alpha: 0.74)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(
            projected,
            4.2,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
        if (showLabels) {
          final TextPainter textPainter = TextPainter(
            text: TextSpan(
              text: point.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                shadows: <Shadow>[Shadow(blurRadius: 6, color: Colors.black)],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          textPainter.paint(
            canvas,
            projected + Offset(5, -textPainter.height / 2),
          );
        }
      }
    }
  }

  double _interpolatedValue(Offset normalized) {
    double weightedSum = 0.0;
    double weightTotal = 0.0;
    for (final _TopomapPoint point in points) {
      final double distance = (normalized - point.position).distance;
      if (distance < 0.001) {
        return point.value;
      }
      final double weight = 1.0 / math.pow(distance, 2.4);
      weightedSum += point.value * weight;
      weightTotal += weight;
    }
    return weightTotal == 0.0 ? 0.0 : weightedSum / weightTotal;
  }

  void _drawHeadLandmarks(
    Canvas canvas,
    Offset center,
    double radius,
    Paint outlinePaint,
  ) {
    final Path nose = Path()
      ..moveTo(center.dx - radius * 0.10, center.dy - radius * 0.98)
      ..lineTo(center.dx, center.dy - radius * 1.12)
      ..lineTo(center.dx + radius * 0.10, center.dy - radius * 0.98);
    canvas.drawPath(nose, outlinePaint);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx - radius * 1.02, center.dy),
        width: radius * 0.22,
        height: radius * 0.46,
      ),
      math.pi / 2,
      math.pi,
      false,
      outlinePaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx + radius * 1.02, center.dy),
        width: radius * 0.22,
        height: radius * 0.46,
      ),
      -math.pi / 2,
      math.pi,
      false,
      outlinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TopomapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.showElectrodes != showElectrodes ||
        oldDelegate.showLabels != showLabels;
  }
}

class _TopomapColorbar extends StatelessWidget {
  const _TopomapColorbar({
    required this.minValue,
    required this.maxValue,
  });

  final double minValue;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          maxValue.toStringAsFixed(1),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: CustomPaint(
            painter: _TopomapColorbarPainter(
              minValue: minValue,
              maxValue: maxValue,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          minValue.toStringAsFixed(1),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _TopomapColorbarPainter extends CustomPainter {
  const _TopomapColorbarPainter({
    required this.minValue,
    required this.maxValue,
  });

  final double minValue;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[
          _topomapColor(minValue, minValue, maxValue),
          _topomapColor((minValue + maxValue) / 2, minValue, maxValue),
          _topomapColor(maxValue, minValue, maxValue),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(999)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(999)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _TopomapColorbarPainter oldDelegate) {
    return oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue;
  }
}

Color _topomapColor(double value, double minValue, double maxValue) {
  final double normalized = maxValue <= minValue
      ? 0.5
      : ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
  const List<Color> stops = <Color>[
    Color(0xFF153B7A),
    Color(0xFF2EB8C7),
    Color(0xFFF4E86C),
    Color(0xFFE85D3D),
  ];
  final double scaled = normalized * (stops.length - 1);
  final int index = scaled.floor().clamp(0, stops.length - 2);
  final double t = scaled - index;
  return Color.lerp(stops[index], stops[index + 1], t)!;
}

class _SegmentedChart extends StatefulWidget {
  const _SegmentedChart({
    required this.dataset,
    required this.params,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;

  @override
  State<_SegmentedChart> createState() => _SegmentedChartState();
}

class _SegmentedChartState extends State<_SegmentedChart> {
  final Map<String, ScrollController> _segmentScrollControllers =
      <String, ScrollController>{};
  bool _syncingSegmentScroll = false;
  double _sharedSegmentScrollOffset = 0;

  @override
  void dispose() {
    for (final ScrollController controller in _segmentScrollControllers.values) {
      controller.dispose();
    }
    _segmentScrollControllers.clear();
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

  @override
  Widget build(BuildContext context) {
    final SegmentedTimeSeriesData? segmented = widget.dataset.segmentedTimeSeries;
    if (segmented == null || segmented.segments.isEmpty) {
      return const _ChartMessage(
        title: 'No segmented data',
        body: 'Run a Segmentation-backed path before opening the segmented viewer.',
      );
    }

    final Map<String, dynamic> params = widget.params;
    params.putIfAbsent('segmented_view_mode', () => 'default');
    params.putIfAbsent('segmented_include_bad', () => false);
    params.putIfAbsent('segmented_visible_marker_labels', () => <String>[]);
    params.putIfAbsent('segmented_marker_filter_initialized', () => false);
    params.putIfAbsent('segmented_time_zoom', () => 1.0);
    params.putIfAbsent('segmented_y_zoom', () => 1.0);
    params.putIfAbsent('segmented_display_baseline', () => true);
    params.putIfAbsent('segmented_display_average', () => false);

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
        .where((SignalSegmentData segment) => includeBad || !_segmentIsBad(segment))
        .toList(growable: false);
    if (visibleSegments.isEmpty) {
      return const _ChartMessage(
        title: 'No visible segments',
        body: 'All segments are currently excluded as bad. Enable "Include bad segments" to inspect them.',
      );
    }

    final String mode = (params['segmented_view_mode'] ?? 'default').toString();
    final bool displayBaseline =
        params['segmented_display_baseline'] as bool? ?? true;
    final bool displayAverage =
        params['segmented_display_average'] as bool? ?? false;
    final double baselineStartMs =
        (params['eventBaselineStartMs'] as num?)?.toDouble() ?? -200.0;
    final double baselineStopMs =
        (params['eventBaselineStopMs'] as num?)?.toDouble() ?? 0.0;
    final double timeZoom =
        ((params['segmented_time_zoom'] as num?)?.toDouble() ?? 1.0).clamp(1.0, 8.0);
    final double yZoom =
        ((params['segmented_y_zoom'] as num?)?.toDouble() ?? 1.0).clamp(0.25, 6.0);
    final List<_SegmentLabelGroup> allGroups =
        _segmentGroupsByLabel(segmented, visibleSegments);
    final Set<String> availableLabels =
        allGroups.map((_SegmentLabelGroup group) => group.label).toSet();
    final bool markerFilterInitialized =
        params['segmented_marker_filter_initialized'] as bool? ?? false;
    final List<String> rawSelectedLabels =
        (params['segmented_visible_marker_labels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .where(availableLabels.contains)
            .toList(growable: false);
    final Set<String> selectedLabels = markerFilterInitialized
        ? rawSelectedLabels.toSet()
        : Set<String>.from(availableLabels);
    params['segmented_visible_marker_labels'] =
        selectedLabels.toList(growable: false);
    params['segmented_marker_filter_initialized'] = true;
    final List<_SegmentLabelGroup> groups = allGroups
        .where((_SegmentLabelGroup group) => selectedLabels.contains(group.label))
        .toList(growable: false);
    _pruneSegmentScrollControllers(
      groups.map((_SegmentLabelGroup group) => group.label).toSet(),
    );

    final String subtitle =
        '${widget.dataset.label} • ${visibleSegments.length}/${segmented.segmentCount} visible segment${visibleSegments.length == 1 ? '' : 's'} • ${groups.length}/${allGroups.length} label${allGroups.length == 1 ? '' : 's'} shown';

    return _ChartCard(
      title: 'Segments by marker label',
      subtitle: subtitle,
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'default', label: Text('Default')),
              ButtonSegment<String>(
                value: 'butterfly_segments',
                label: Text('Butterfly Segments'),
              ),
              ButtonSegment<String>(
                value: 'butterfly_channels',
                label: Text('Butterfly Channels'),
              ),
              ButtonSegment<String>(
                value: 'butterfly_both',
                label: Text('Both'),
                enabled: false,
              ),
            ],
            selected: <String>{
              mode == 'butterfly_both' ? 'default' : mode,
            },
            onSelectionChanged: (Set<String> selection) {
              if (selection.isEmpty) {
                return;
              }
              setState(() {
                params['segmented_view_mode'] = selection.first;
              });
            },
          ),
          FilterChip(
            label: const Text('Baseline'),
            selected: displayBaseline,
            selectedColor: Colors.yellowAccent.withValues(alpha: 0.18),
            onSelected: (bool value) {
              setState(() {
                params['segmented_display_baseline'] = value;
              });
            },
          ),
          FilterChip(
            label: const Text('Average'),
            selected: displayAverage,
            selectedColor: Colors.yellowAccent.withValues(alpha: 0.18),
            onSelected: (bool value) {
              setState(() {
                params['segmented_display_average'] = value;
              });
            },
          ),
          FilterChip(
            label: const Text('Include bad segments'),
            selected: includeBad,
            onSelected: (bool value) {
              setState(() {
                params['segmented_include_bad'] = value;
                params['segmented_individual_page_start'] = 0;
                params['segmented_focus_segment_index'] = 0;
              });
            },
          ),
          if (allGroups.isNotEmpty)
            const SizedBox(
              height: 24,
              child: VerticalDivider(
                color: Colors.white24,
                thickness: 1,
              ),
            ),
          ...allGroups.map((_SegmentLabelGroup group) {
            final bool selected = selectedLabels.contains(group.label);
            return FilterChip(
              label: Text('${group.label} (${group.segments.length})'),
              selected: selected,
              showCheckmark: false,
              backgroundColor: group.color.withValues(alpha: 0.08),
              selectedColor: group.color.withValues(alpha: 0.28),
              avatar: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: group.color,
                  shape: BoxShape.circle,
                ),
              ),
              onSelected: (bool value) {
                setState(() {
                  final Set<String> nextLabels = Set<String>.from(selectedLabels);
                  if (value) {
                    nextLabels.add(group.label);
                  } else {
                    nextLabels.remove(group.label);
                  }
                  params['segmented_visible_marker_labels'] =
                      nextLabels.toList(growable: false);
                  params['segmented_marker_filter_initialized'] = true;
                });
              },
            );
          }),
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (groups.isEmpty) {
            return const _ChartMessage(
              title: 'No selected markers',
              body: 'Select one or more marker labels above to show segmented data.',
            );
          }
          const double gapWidth = 12;
          const double minPanelWidth = 360;
          final double availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : groups.length * minPanelWidth;
          final double filledPanelWidth = groups.isEmpty
              ? minPanelWidth
              : (availableWidth - (gapWidth * (groups.length - 1))) /
                  groups.length;
          final double panelWidth = math.max(minPanelWidth, filledPanelWidth);
          return Scrollbar(
            thumbVisibility: groups.length * panelWidth > availableWidth,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: gapWidth),
              itemBuilder: (BuildContext context, int index) {
                final _SegmentLabelGroup group = groups[index];
                return SizedBox(
                  width: panelWidth,
                  child: _SegmentLabelPanel(
                    segmented: segmented,
                    group: group,
                    scrollController:
                        _segmentScrollControllerFor(group.label),
                    mode: mode,
                    timeZoom: timeZoom,
                    yZoom: yZoom,
                    displayBaseline: displayBaseline,
                    displayAverage: displayAverage,
                    baselineStartMs: baselineStartMs,
                    baselineStopMs: baselineStopMs,
                    onTimeZoomChanged: (double value) {
                      setState(() {
                        params['segmented_time_zoom'] = value.clamp(1.0, 8.0);
                      });
                    },
                    onYZoomChanged: (double value) {
                      setState(() {
                        params['segmented_y_zoom'] = value.clamp(0.25, 6.0);
                      });
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SegmentLabelPanel extends StatelessWidget {
  const _SegmentLabelPanel({
    required this.segmented,
    required this.group,
    required this.scrollController,
    required this.mode,
    required this.timeZoom,
    required this.yZoom,
    required this.displayBaseline,
    required this.displayAverage,
    required this.baselineStartMs,
    required this.baselineStopMs,
    required this.onTimeZoomChanged,
    required this.onYZoomChanged,
  });

  final SegmentedTimeSeriesData segmented;
  final _SegmentLabelGroup group;
  final ScrollController scrollController;
  final String mode;
  final double timeZoom;
  final double yZoom;
  final bool displayBaseline;
  final bool displayAverage;
  final double baselineStartMs;
  final double baselineStopMs;
  final ValueChanged<double> onTimeZoomChanged;
  final ValueChanged<double> onYZoomChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: group.color.withValues(alpha: 0.55),
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
                    color: group.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        group.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${group.segments.length} segment${group.segments.length == 1 ? '' : 's'}',
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
              child: switch (mode) {
                'butterfly_segments' => _SegmentButterflySegmentsPanel(
                    segmented: segmented,
                    group: group,
                    scrollController: scrollController,
                    timeZoom: timeZoom,
                    yZoom: yZoom,
                    displayBaseline: displayBaseline,
                    baselineStartMs: baselineStartMs,
                    baselineStopMs: baselineStopMs,
                    onTimeZoomChanged: onTimeZoomChanged,
                    onYZoomChanged: onYZoomChanged,
                  ),
                'butterfly_channels' => _SegmentButterflyChannelsPanel(
                    segmented: segmented,
                    group: group,
                    scrollController: scrollController,
                    timeZoom: timeZoom,
                    yZoom: yZoom,
                    displayBaseline: displayBaseline,
                    baselineStartMs: baselineStartMs,
                    baselineStopMs: baselineStopMs,
                    onTimeZoomChanged: onTimeZoomChanged,
                    onYZoomChanged: onYZoomChanged,
                  ),
                _ => _SegmentDefaultPanel(
                    segmented: segmented,
                    group: group,
                    scrollController: scrollController,
                    timeZoom: timeZoom,
                    yZoom: yZoom,
                    displayBaseline: displayBaseline,
                    displayAverage: displayAverage,
                    baselineStartMs: baselineStartMs,
                    baselineStopMs: baselineStopMs,
                    onTimeZoomChanged: onTimeZoomChanged,
                    onYZoomChanged: onYZoomChanged,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentDefaultPanel extends StatelessWidget {
  const _SegmentDefaultPanel({
    required this.segmented,
    required this.group,
    required this.scrollController,
    required this.timeZoom,
    required this.yZoom,
    required this.displayBaseline,
    required this.displayAverage,
    required this.baselineStartMs,
    required this.baselineStopMs,
    required this.onTimeZoomChanged,
    required this.onYZoomChanged,
  });

  final SegmentedTimeSeriesData segmented;
  final _SegmentLabelGroup group;
  final ScrollController scrollController;
  final double timeZoom;
  final double yZoom;
  final bool displayBaseline;
  final bool displayAverage;
  final double baselineStartMs;
  final double baselineStopMs;
  final ValueChanged<double> onTimeZoomChanged;
  final ValueChanged<double> onYZoomChanged;

  @override
  Widget build(BuildContext context) {
    final int channelCount = _segmentGroupChannelCount(segmented, group.segments);
    return ListView.separated(
      controller: scrollController,
      itemCount: channelCount,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int channelIndex) {
        final _SegmentSequencePlotData plotData = displayAverage
            ? _buildSegmentAveragePlotData(
                segmented: segmented,
                segments: group.segments,
                channelIndex: channelIndex,
                color: group.color,
                displayBaseline: displayBaseline,
                baselineStartMs: baselineStartMs,
                baselineStopMs: baselineStopMs,
              )
            : _buildSegmentSequencePlotData(
                segmented: segmented,
                segments: group.segments,
                channelIndex: channelIndex,
                color: group.color,
                overlayChannels: false,
                displayBaseline: displayBaseline,
                baselineStartMs: baselineStartMs,
                baselineStopMs: baselineStopMs,
              );
        return _SegmentPlotTile(
          title: displayAverage
              ? '${_segmentChannelLabel(segmented, channelIndex)} mean'
              : _segmentChannelLabel(segmented, channelIndex),
          height: 132,
          timeZoom: timeZoom,
          yZoom: yZoom,
          onTimeZoomChanged: onTimeZoomChanged,
          onYZoomChanged: onYZoomChanged,
          chart: _segmentLineChart(plotData, yZoom: yZoom),
        );
      },
    );
  }
}

class _SegmentButterflySegmentsPanel extends StatelessWidget {
  const _SegmentButterflySegmentsPanel({
    required this.segmented,
    required this.group,
    required this.scrollController,
    required this.timeZoom,
    required this.yZoom,
    required this.displayBaseline,
    required this.baselineStartMs,
    required this.baselineStopMs,
    required this.onTimeZoomChanged,
    required this.onYZoomChanged,
  });

  final SegmentedTimeSeriesData segmented;
  final _SegmentLabelGroup group;
  final ScrollController scrollController;
  final double timeZoom;
  final double yZoom;
  final bool displayBaseline;
  final double baselineStartMs;
  final double baselineStopMs;
  final ValueChanged<double> onTimeZoomChanged;
  final ValueChanged<double> onYZoomChanged;

  @override
  Widget build(BuildContext context) {
    final int channelCount = _segmentGroupChannelCount(segmented, group.segments);
    return ListView.separated(
      controller: scrollController,
      itemCount: channelCount,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int channelIndex) {
        final _SegmentSequencePlotData plotData =
            _buildSegmentButterflySegmentsPlotData(
          segmented: segmented,
          segments: group.segments,
          channelIndex: channelIndex,
          color: group.color,
          displayBaseline: displayBaseline,
          baselineStartMs: baselineStartMs,
          baselineStopMs: baselineStopMs,
        );
        return _SegmentPlotTile(
          title: _segmentChannelLabel(segmented, channelIndex),
          height: 132,
          timeZoom: timeZoom,
          yZoom: yZoom,
          onTimeZoomChanged: onTimeZoomChanged,
          onYZoomChanged: onYZoomChanged,
          chart: _segmentLineChart(plotData, yZoom: yZoom),
        );
      },
    );
  }
}

class _SegmentButterflyChannelsPanel extends StatelessWidget {
  const _SegmentButterflyChannelsPanel({
    required this.segmented,
    required this.group,
    required this.scrollController,
    required this.timeZoom,
    required this.yZoom,
    required this.displayBaseline,
    required this.baselineStartMs,
    required this.baselineStopMs,
    required this.onTimeZoomChanged,
    required this.onYZoomChanged,
  });

  final SegmentedTimeSeriesData segmented;
  final _SegmentLabelGroup group;
  final ScrollController scrollController;
  final double timeZoom;
  final double yZoom;
  final bool displayBaseline;
  final double baselineStartMs;
  final double baselineStopMs;
  final ValueChanged<double> onTimeZoomChanged;
  final ValueChanged<double> onYZoomChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      itemCount: group.segments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int segmentIndex) {
        final SignalSegmentData segment = group.segments[segmentIndex];
        final _SegmentSequencePlotData plotData =
            _buildSegmentSequencePlotData(
          segmented: segmented,
          segments: <SignalSegmentData>[segment],
          channelIndex: 0,
          color: group.color,
          overlayChannels: true,
          displayBaseline: displayBaseline,
          baselineStartMs: baselineStartMs,
          baselineStopMs: baselineStopMs,
        );
        return _SegmentPlotTile(
          title: _segmentDisplayLabel(segment, segmentIndex),
          height: 132,
          timeZoom: timeZoom,
          yZoom: yZoom,
          onTimeZoomChanged: onTimeZoomChanged,
          onYZoomChanged: onYZoomChanged,
          chart: _segmentLineChart(plotData, yZoom: yZoom),
        );
      },
    );
  }
}

class _SegmentPlotTile extends StatefulWidget {
  const _SegmentPlotTile({
    required this.title,
    required this.height,
    required this.chart,
    required this.timeZoom,
    required this.yZoom,
    required this.onTimeZoomChanged,
    required this.onYZoomChanged,
  });

  final String title;
  final double height;
  final Widget chart;
  final double timeZoom;
  final double yZoom;
  final ValueChanged<double> onTimeZoomChanged;
  final ValueChanged<double> onYZoomChanged;

  @override
  State<_SegmentPlotTile> createState() => _SegmentPlotTileState();
}

class _SegmentPlotTileState extends State<_SegmentPlotTile> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final ViewerScrollGesture? gesture =
        viewerScrollGestureFromPointerSignal(event);
    if (gesture == null) {
      return;
    }
    switch (gesture.intent) {
      case ViewerScrollIntent.timeZoom:
        final double factor = viewerZoomFactor(zoomingIn: gesture.zoomingIn);
        widget.onTimeZoomChanged((widget.timeZoom * factor).clamp(1.0, 8.0));
        return;
      case ViewerScrollIntent.amplitudeZoom:
        final double factor = viewerZoomFactor(zoomingIn: gesture.zoomingIn);
        widget.onYZoomChanged((widget.yZoom * factor).clamp(0.25, 6.0));
        return;
      case ViewerScrollIntent.horizontalPan:
        scrollControllerBy(_horizontalController, gesture.primaryDelta);
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: widget.height,
              child: Listener(
                onPointerSignal: _handlePointerSignal,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double chartWidth =
                        math.max(constraints.maxWidth, constraints.maxWidth * widget.timeZoom);
                    return Scrollbar(
                      controller: _horizontalController,
                      thumbVisibility: widget.timeZoom > 1.01,
                      notificationPredicate:
                          (ScrollNotification notification) =>
                              notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: chartWidth,
                          height: widget.height,
                          child: widget.chart,
                        ),
                      ),
                    );
                  },
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
              segmented.channelCountForSegment(visibleSegments[focusSegmentIndex]) -
                  pageStart,
            ),
            (int index) => pageStart + index,
            growable: false,
          )
            .take(pageSize)
            .map((int channelIndex) => _MiniTraceData(
                  title: _segmentChannelLabel(segmented, channelIndex),
                  points: _segmentChannelSpots(
                    segmented,
                    visibleSegments[focusSegmentIndex],
                    segmented.sampleRate,
                    channelIndex,
                  ),
                  color: _seriesColor(channelIndex),
                ))
            .toList(growable: false);

    if (traces.isEmpty) {
      return const _ChartMessage(
        title: 'Nothing to show',
        body: 'There are no segments or channels in the selected page.',
      );
    }

    final List<double> allX =
        traces.expand((_MiniTraceData trace) => trace.points.map((FlSpot spot) => spot.x)).toList();
    final List<double> allY =
        traces.expand((_MiniTraceData trace) => trace.points.map((FlSpot spot) => spot.y)).toList();
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
                        yAxisLabel: 'uV',
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
        body: 'This aggregate selection did not produce any traces to summarize.',
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
      'channels' => 'channels in ${_segmentDisplayLabel(visibleSegments[focusSegmentIndex], focusSegmentIndex)}',
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
                horizontalInterval: _niceAxisStep(plotData.maxY - plotData.minY),
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
                yAxisLabel: 'uV',
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
                        horizontalInterval: _niceAxisStep(plotData.maxY - plotData.minY),
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
                        yAxisLabel: 'uV',
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
  const _AlignedTrace({
    required this.values,
    required this.xValues,
  });

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
  });

  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return const _ChartMessage(
        title: 'No time-domain data',
        body: 'Run an import-backed signal path before viewing sleep stages.',
      );
    }

    final List<TimeMarker> stageMarkers = timeSeries.markers
        .where(isSleepStageMarker)
        .toList(growable: false)
      ..sort((TimeMarker a, TimeMarker b) => a.onsetMicros.compareTo(b.onsetMicros));
    if (stageMarkers.isEmpty) {
      return const _ChartMessage(
        title: 'No sleep stages yet',
        body: 'Run the Sleep Staging node to generate WAKE, REM, and SWS markers.',
      );
    }

    final List<String> stageLabels = sleepStagePatternFromTimeSeries(timeSeries);
    const List<String> preferredOrder = <String>['WAKE', 'REM', 'SWS'];
    final List<String> orderedStages = preferredOrder
        .where(stageLabels.contains)
        .followedBy(stageLabels.where((String label) => !preferredOrder.contains(label)))
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
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(totalSeconds, spots.last.x),
          minY: -0.25,
          maxY: math.max(0.0, orderedStages.length - 1 + 0.25),
          gridData: FlGridData(
            show: true,
            horizontalInterval: 1,
            verticalInterval: _niceAxisStep(math.max(totalSeconds, 1.0)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                interval: _niceAxisStep(math.max(totalSeconds, 1.0)),
                reservedSize: 28,
                getTitlesWidget: (double value, TitleMeta meta) {
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
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: 1,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final String label = yByStage.entries
                      .firstWhere(
                        (MapEntry<String, double> entry) =>
                            (entry.value - value).abs() < 0.001,
                        orElse: () => const MapEntry<String, double>('', -999),
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
  }
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
    params.putIfAbsent('psd_view_log_y', () => false);

    final double maxHz =
        (params['psd_view_max_hz'] as num?)?.toDouble() ?? 40.0;
    final bool logY = params['psd_view_log_y'] as bool? ?? false;
    final List<_SeriesData> series = <_SeriesData>[];
    for (int datasetIndex = 0; datasetIndex < datasets.length; datasetIndex++) {
      final Dataset dataset = datasets[datasetIndex];
      final FrequencySpectrumData? spectrum = dataset.spectrum;
      final List<double>? freqs = spectrum?.frequencies;
      final List<double>? power = spectrum?.power;
      if (freqs == null || power == null || freqs.isEmpty || power.isEmpty) {
        continue;
      }

      final int count = math.min(freqs.length, power.length);
      final List<FlSpot> points = <FlSpot>[];
      for (int i = 0; i < count; i++) {
        if (freqs[i] <= maxHz) {
          final double sourcePower = power[i];
          final double plotPower = logY
              ? math.log((sourcePower <= 0 ? 1.0e-12 : sourcePower)) / math.ln10
              : sourcePower;
          points.add(FlSpot(freqs[i], plotPower));
        }
      }
      if (points.isEmpty) {
        continue;
      }

      series.add(
        _SeriesData(
          label: dataset.label,
          color: _seriesColor(datasetIndex),
          points: points,
          subtitle: '$count bins',
        ),
      );
    }

    if (series.isEmpty) {
      return const _ChartMessage(
        title: 'No PSD data',
        body: 'Run a PSD node upstream, then run the visualization node again.',
      );
    }

    final List<double> allY =
        series.expand((_SeriesData s) => s.points.map((FlSpot p) => p.y)).toList();
    final List<double> allX =
        series.expand((_SeriesData s) => s.points.map((FlSpot p) => p.x)).toList();
    final String scaleMode = (params['psd_view_scale_mode'] ?? 'auto').toString();
    final double configuredMaxPower =
        (params['psd_view_max_power'] as num?)?.toDouble() ?? 10.0;
    final double dataMinY = allY.reduce(math.min);
    final double dataMaxY = allY.reduce(math.max);
    final double minY = math.min(0.0, dataMinY);
    final double maxY = scaleMode == 'fixed'
        ? math.max(configuredMaxPower, minY + 0.001)
        : math.max(dataMaxY * 1.1, minY + 0.001);
    final double maxX = allX.reduce(math.max);

    return _ChartCard(
      title: 'PSD',
      subtitle: '${series.length} overlay${series.length == 1 ? '' : 's'}',
      legend: series,
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _PsdMenuChip<double>(
            label: 'Range',
            valueLabel: '${maxHz.toStringAsFixed(0)} Hz',
            options: const <double>[10, 20, 40, 80, 120],
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
        ],
      ),
      child: LineChart(
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
          ),
          clipData: const FlClipData.all(),
          lineBarsData: series
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
        body: 'Run Bridge Detector upstream to compute minute-by-minute channel correlations.',
      );
    }

    final int resolvedMinuteIndex = _resolveMinuteIndex(bridge);
    final BridgeCorrelationFrameData frame = bridge.frames[resolvedMinuteIndex];
    final String minuteLabel = 'Minute ${frame.minuteIndex + 1}';
    final double startSeconds = frame.startSample / bridge.sampleRate;
    final double stopSeconds = frame.endSampleExclusive / bridge.sampleRate;
    final List<int> channelOrder = _channelOrderMode == 'covariance'
        ? _covarianceOrderForBridge(widget.dataset.id, bridge)
        : List<int>.generate(bridge.channelCount, (int index) => index, growable: false);

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
              ButtonSegment<String>(
                value: 'data',
                label: Text('Data Order'),
              ),
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
            itemLabel: (int index) => 'Minute ${bridge.frames[index].minuteIndex + 1}',
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

  List<int> _covarianceOrderForBridge(String datasetId, BridgeDetectionData bridge) {
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
        body: 'This bridge-detection frame does not contain a correlation matrix.',
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
        final double availableWidth = math.max(120.0, constraints.maxWidth - axisLabelSpace);
        final double availableHeight = math.max(120.0, constraints.maxHeight - axisLabelSpace);
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
  const _BridgeTopLabels({
    required this.labels,
    required this.cellExtent,
  });

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
  const _BridgeSideLabels({
    required this.labels,
    required this.cellExtent,
  });

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
            Text(
              '-1',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Text(
              '0',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Text(
              '1',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

// ignore: unused_element
int _clampIndex(int value, int length) {
  if (length <= 0) {
    return 0;
  }
  return value.clamp(0, length - 1);
}

// ignore: unused_element
int _clampPageStart(int start, int totalCount, int pageSize) {
  if (totalCount <= 0) {
    return 0;
  }
  final int safePageSize = math.max(1, pageSize);
  final int maxStart = math.max(0, totalCount - safePageSize);
  return start.clamp(0, maxStart);
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
    required this.dividers,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final List<LineChartBarData> lineBars;
  final List<VerticalRangeAnnotation> dividers;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

List<_SegmentLabelGroup> _segmentGroupsByLabel(
  SegmentedTimeSeriesData segmented,
  List<SignalSegmentData> segments,
) {
  final Map<String, List<SignalSegmentData>> grouped =
      <String, List<SignalSegmentData>>{};
  for (final SignalSegmentData segment in segments) {
    final String label =
        segment.label.trim().isEmpty ? 'Unlabeled' : segment.label.trim();
    grouped.putIfAbsent(label, () => <SignalSegmentData>[]).add(segment);
  }
  int index = 0;
  return grouped.entries.map((MapEntry<String, List<SignalSegmentData>> entry) {
    return _SegmentLabelGroup(
      label: entry.key,
      segments: entry.value,
      color: _segmentLabelColor(entry.key, index++),
    );
  }).toList(growable: false);
}

Set<String> _excludedSegmentationMarkerLabels(dynamic rawIncludedMarkers) {
  final Map<String, dynamic> includedMarkers =
      Map<String, dynamic>.from(rawIncludedMarkers as Map? ?? const <String, dynamic>{});
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
    channelCount = math.max(channelCount, segmented.channelCountForSegment(segment));
  }
  return math.max(1, channelCount);
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
  final double stepMs = segmented.sampleRate <= 0 ? 1.0 : 1000.0 / segmented.sampleRate;
  double cursorMs = segments.isEmpty ? 0 : _relativeSegmentStartMs(segments.first);
  final double minX = cursorMs;
  const double gapMs = 60;

  for (int segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
    final SignalSegmentData segment = segments[segmentIndex];
    final int segmentChannelCount = segmented.channelCountForSegment(segment);
    final int localChannelCount =
        overlayChannels ? segmentChannelCount : math.min(segmentChannelCount, channelIndex + 1);
    int longestSampleCount = 0;

    for (int localChannelIndex = overlayChannels ? 0 : channelIndex;
        localChannelIndex < localChannelCount;
        localChannelIndex++) {
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
    final double stepMs =
        segmented.sampleRate <= 0 ? 1.0 : 1000.0 / segmented.sampleRate;
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
        color: _segmentTraceShade(color, channelIndex, segmentIndex)
            .withValues(alpha: segments.length == 1 ? 0.9 : 0.48),
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
      final double stepMs =
          segmented.sampleRate <= 0 ? 1.0 : 1000.0 / segmented.sampleRate;
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

Widget _segmentLineChart(
  _SegmentSequencePlotData plotData, {
  required double yZoom,
}) {
  if (plotData.lineBars.isEmpty) {
    return const _ChartMessage(
      title: 'No samples',
      body: 'This segment/channel combination does not contain data.',
    );
  }
  final double yCenter = (plotData.minY + plotData.maxY) / 2;
  final double yHalfRange =
      math.max(0.001, (plotData.maxY - plotData.minY) / (2 * yZoom));
  final double rawMinY = yCenter - yHalfRange;
  final double rawMaxY = yCenter + yHalfRange;
  final double yInterval = _niceAxisStep(rawMaxY - rawMinY);
  final double minY = _floorToStep(rawMinY, yInterval);
  final double maxY = _ceilToStep(rawMaxY, yInterval);
  final double xInterval = _niceAxisStep(plotData.maxX - plotData.minX);
  final double minX = _floorToStep(plotData.minX, xInterval);
  final double maxX = _ceilToStep(plotData.maxX, xInterval);
  return LineChart(
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
      titlesData: _chartTitles(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        xAxisLabel: 'ms',
        yAxisLabel: 'uV',
      ),
      clipData: const FlClipData.all(),
      lineBarsData: plotData.lineBars,
    ),
  );
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
  return Color.lerp(baseColor, Colors.white, (channelIndex % 5) * 0.08)!
      .withValues(alpha: opacity);
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
  final Color lifted = Color.lerp(baseColor, Colors.white, whiteMixes[shadeIndex])!;
  return Color.lerp(lifted, Colors.black, blackMixes[shadeIndex])!
      .withValues(alpha: segmentIndex.isEven ? 0.92 : 0.78);
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
  final List<List<double>> channelSamples =
      segmented.channelSamplesForSegment(segment);
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
  final List<List<double>> samples = segmented.channelSamplesForSegment(segment);
  if (channelIndex < 0 || channelIndex >= samples.length) {
    return const <double>[];
  }
  final List<double> channel = samples[channelIndex];
  if (!displayBaseline ||
      samples.isEmpty ||
      segmented.sampleRate <= 0 ||
      baselineStopMs <= baselineStartMs) {
    return channel;
  }
  final Map<String, List<double>> cache =
      _segmentDisplayValueCache[segment] ??= <String, List<double>>{};
  final String cacheKey =
      '$channelIndex|${segmented.sampleRate}|$baselineStartMs|$baselineStopMs';
  final List<double>? cached = cache[cacheKey];
  if (cached != null) {
    return cached;
  }
  final double anchorSeconds = segment.anchorTimeSeconds ?? segment.startSeconds;
  final double baselineStartSeconds = anchorSeconds + baselineStartMs / 1000.0;
  final double baselineStopSeconds = anchorSeconds + baselineStopMs / 1000.0;
  final int startIndex =
      ((baselineStartSeconds - segment.startSeconds) * segmented.sampleRate).round();
  final int stopIndex =
      ((baselineStopSeconds - segment.startSeconds) * segmented.sampleRate).round();
  final int sampleCount = channel.length;
  final int boundedStart = startIndex.clamp(0, sampleCount);
  final int boundedStop = stopIndex.clamp(0, sampleCount);
  if (boundedStop <= boundedStart) {
    return channel;
  }
  double sum = 0;
  for (int index = boundedStart; index < boundedStop; index++) {
    sum += channel[index];
  }
  final double baselineMean = sum / (boundedStop - boundedStart);
  final List<double> corrected =
      List<double>.generate(
        channel.length,
        (int index) => channel[index] - baselineMean,
        growable: false,
      );
  cache[cacheKey] = corrected;
  return corrected;
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
    final List<double> values = _displaySegmentChannelValues(
      segmented: segmented,
      segment: segment,
      channelIndex: channelIndex,
      displayBaseline: false,
      baselineStartMs: 0,
      baselineStopMs: 0,
    );
    if (values.isEmpty) {
      continue;
    }
    final double startMs = _relativeSegmentStartMs(segment);
    final double stepMs =
        segmented.sampleRate <= 0 ? 1.0 : 1000.0 / segmented.sampleRate;
    final List<double> xValues = List<double>.generate(
      values.length,
      (int index) => startMs + (index * stepMs),
      growable: false,
    );
    traces.add(
      _AlignedTrace(
        values: values,
        xValues: xValues,
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
  for (int channelIndex = 0;
      channelIndex < segmented.channelCountForSegment(segment);
      channelIndex++) {
    final List<double> values = _displaySegmentChannelValues(
      segmented: segmented,
      segment: segment,
      channelIndex: channelIndex,
      displayBaseline: false,
      baselineStartMs: 0,
      baselineStopMs: 0,
    );
    if (values.isEmpty) {
      continue;
    }
    final double startMs = _relativeSegmentStartMs(segment);
    final double stepMs =
        segmented.sampleRate <= 0 ? 1.0 : 1000.0 / segmented.sampleRate;
    final List<double> xValues = List<double>.generate(
      values.length,
      (int index) => startMs + (index * stepMs),
      growable: false,
    );
    traces.add(
      _AlignedTrace(
        values: values,
        xValues: xValues,
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
      _alignedChannelTracesForSegment(
        segmented: segmented,
        segment: segment,
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

  final _AlignedTrace firstTrace = traces.first;
  final List<double> xValues = firstTrace.xValues.length == minLength
      ? firstTrace.xValues
      : firstTrace.xValues.sublist(0, minLength);
  final bool needsAggregateStats = showMean || showSpread;
  final List<List<double>> statsInput = traces
      .map(
        (_AlignedTrace trace) => trace.values.length == minLength
            ? trace.values
            : trace.values.sublist(0, minLength),
      )
      .toList(growable: false);
  final AggregateSeriesStats? aggregateStats = needsAggregateStats
      ? computeAggregateSeriesStatsWithFallback(
          statsInput,
        )
      : null;
  if (needsAggregateStats && aggregateStats == null) {
    return null;
  }

  final List<FlSpot> meanSpots = aggregateStats == null
      ? const <FlSpot>[]
      : List<FlSpot>.generate(
          minLength,
          (int sampleIndex) => FlSpot(
            xValues[sampleIndex],
            aggregateStats.mean[sampleIndex],
          ),
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

  double? minYValue;
  double? maxYValue;
  void includeY(double value) {
    minYValue = minYValue == null ? value : math.min(minYValue!, value);
    maxYValue = maxYValue == null ? value : math.max(maxYValue!, value);
  }
  if (showTraces) {
    for (final _AlignedTrace trace in traces) {
      for (int sampleIndex = 0; sampleIndex < minLength; sampleIndex++) {
        includeY(trace.values[sampleIndex]);
      }
    }
  }
  if (showMean) {
    for (final FlSpot spot in meanSpots) {
      includeY(spot.y);
    }
  }
  if (showSpread) {
    for (final FlSpot spot in upperSpots) {
      includeY(spot.y);
    }
    for (final FlSpot spot in lowerSpots) {
      includeY(spot.y);
    }
  }
  final double minX = xValues.isEmpty ? 0.0 : xValues.first;
  final double maxX = xValues.isEmpty ? 1.0 : xValues.last;
  final double minY = minYValue ?? -1.0;
  final double maxY = maxYValue ?? 1.0;

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
            (int sampleIndex) => FlSpot(
              xValues[sampleIndex],
              trace.values[sampleIndex],
            ),
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
    return List<int>.generate(channelCount, (int index) => index, growable: false);
  }

  final List<List<double>> similarity = List<List<double>>.generate(
    channelCount,
    (_) => List<double>.filled(channelCount, 0.0),
    growable: false,
  );

  for (final BridgeCorrelationFrameData frame in bridge.frames) {
    for (int row = 0; row < channelCount; row++) {
      final List<double> values = frame.correlationMatrix[row];
      for (int column = 0; column < math.min(channelCount, values.length); column++) {
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
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70),
            ),
            if (toolbar != null) ...<Widget>[
              const SizedBox(height: 10),
              toolbar!,
            ],
            if (legend.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: legend
                    .map(
                      (_SeriesData series) => _LegendChip(series: series),
                    )
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
  const _LegendChip({
    required this.series,
  });

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
            Text(
              series.label,
              style: const TextStyle(color: Colors.white),
            ),
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
      .where((_BandRange band) => band.startHz < maxHz && band.endHz > band.startHz)
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
  const _ChartMessage({
    required this.title,
    required this.body,
  });

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
}) {
  final double xInterval = _niceAxisStep(maxX - minX);
  final double yInterval = _niceAxisStep(maxY - minY);
  final String resolvedYAxisLabel =
      yAxisLabel ?? (logY ? 'log10(uV^2/Hz)' : 'uV^2/Hz');
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      axisNameWidget: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          xAxisLabel,
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
            fitInside: SideTitleFitInsideData(
              enabled: true,
              axisPosition: meta.axisPosition,
              parentAxisSize: meta.parentAxisSize,
              distanceFromEdge: 0,
            ),
            child: Text(
              _formatChartXAxisValue(value),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    ),
    leftTitles: AxisTitles(
      axisNameWidget: RotatedBox(
        quarterTurns: 1,
        child: Text(
          resolvedYAxisLabel,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 56,
        interval: yInterval,
        getTitlesWidget: (double value, TitleMeta meta) {
          if (value < minY - 0.001 || value > maxY + 0.001) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            axisSide: meta.axisSide,
            fitInside: SideTitleFitInsideData(
              enabled: true,
              axisPosition: meta.axisPosition,
              parentAxisSize: meta.parentAxisSize,
              distanceFromEdge: 0,
            ),
            child: Text(
              _formatAxisValue(value, logY: logY),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    ),
  );
}

String _formatChartXAxisValue(double value) {
  final double rounded = value.abs() < 0.0005 ? 0.0 : value;
  return rounded.toStringAsFixed(0);
}

double _niceAxisStep(double range) {
  final double safeRange = range <= 0 ? 1.0 : range;
  final double roughStep = safeRange / 4.0;
  final double exponent =
      math.pow(10, (math.log(roughStep) / math.ln10).floor()).toDouble();
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

String _formatAxisValue(double value, {required bool logY}) {
  if (logY) {
    return '1e${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}';
  }
  final double absolute = value.abs();
  if (absolute >= 100) {
    return value.toStringAsFixed(0);
  }
  if (absolute >= 10) {
    return _trimFixed(value, 1);
  }
  if (absolute >= 1) {
    return _trimFixed(value, 2);
  }
  return _trimFixed(value, 3);
}

String _trimFixed(double value, int fractionDigits) {
  String text = value.toStringAsFixed(fractionDigits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text == '-0' ? '0' : text;
}
