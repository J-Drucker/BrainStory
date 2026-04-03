import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/node.dart';
import '../nodes/sleep_staging_node.dart';
import 'canvas_logic.dart';
import 'raw_signal_browser.dart';

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
        onOpenWindow: onOpenWindow,
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
                  onOpenWindow: null,
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
    required this.onOpenWindow,
  });

  final CanvasLogic logic;
  final String nodeId;
  final VoidCallback? onChanged;
  final VoidCallback? onOpenWindow;

  @override
  State<VisualizationSurface> createState() => _VisualizationSurfaceState();
}

class _VisualizationSurfaceState extends State<VisualizationSurface> {
  final Set<String> _selectedDatasetIds = <String>{};
  String? _activeDatasetId;
  Future<List<Dataset>>? _materializedDatasetsFuture;
  String _materializedDatasetsKey = '';

  CanvasLogic get logic => widget.logic;

  @override
  void didUpdateWidget(covariant VisualizationSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      _selectedDatasetIds.clear();
      _activeDatasetId = null;
      _materializedDatasetsFuture = null;
      _materializedDatasetsKey = '';
    }
    _syncSelectedDatasets(
      logic.sourceDatasetsForVisualizationNode(widget.nodeId),
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
    final List<Dataset> sourceDatasets =
        logic.sourceDatasetsForVisualizationNode(widget.nodeId);
    _syncSelectedDatasets(sourceDatasets);
    final bool comparisonNode = logic.isVisualizationNode(node);
    final List<Dataset> selectedSourceDatasets = _selectedDatasets(sourceDatasets);
    _refreshMaterializedDatasets(selectedSourceDatasets);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                node.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: widget.onOpenWindow == null
                  ? null
                  : () {
                      widget.logic.selectedNodeId = node.id;
                      widget.onOpenWindow!.call();
                    },
              icon: const Icon(Icons.open_in_full, size: 18),
              label: const Text('Pop Out'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (sourceDatasets.isEmpty)
          _emptyState(
            'No dataset',
            comparisonNode
                ? 'Connect this visualization node to an Import-backed path and choose datasets to compare.'
                : 'Run an Import-backed path into this node so there is output available to inspect.',
          )
        else ...<Widget>[
          Text(
            comparisonNode
                ? 'Select one or more datasets to compare'
                : 'Select one or more datasets to inspect',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sourceDatasets.map((Dataset dataset) {
              final bool selected = _selectedDatasetIds.contains(dataset.id);
              return FilterChip(
                label: Text(dataset.label),
                selected: selected,
                onSelected: (bool nextValue) {
                  setState(() {
                    if (nextValue) {
                      _selectedDatasetIds.add(dataset.id);
                      _activeDatasetId ??= dataset.id;
                    } else {
                      _selectedDatasetIds.remove(dataset.id);
                      if (_activeDatasetId == dataset.id) {
                        _activeDatasetId = _selectedDatasetIds.isEmpty
                            ? null
                            : _selectedDatasetIds.first;
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Dataset>>(
              future: _materializedDatasetsFuture,
              builder: (BuildContext context, AsyncSnapshot<List<Dataset>> snapshot) {
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
                final List<Dataset> datasets = snapshot.data ?? const <Dataset>[];
                final String view = logic.visualizationViewForNodeAndDatasets(
                  node,
                  datasets,
                );
                final bool needsActiveDatasetPicker =
                    (view == 'raw' || view == 'hypnogram' || view == 'bridge') &&
                    selectedSourceDatasets.length > 1;
                return Column(
                  children: <Widget>[
                    if (needsActiveDatasetPicker)
                      DropdownButtonFormField<String>(
                        initialValue: _activeDatasetId ?? selectedSourceDatasets.first.id,
                        decoration: const InputDecoration(
                          labelText: 'Active dataset',
                        ),
                        items: selectedSourceDatasets
                            .map(
                              (Dataset dataset) => DropdownMenuItem<String>(
                                value: dataset.id,
                                child: Text(dataset.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (String? value) {
                          setState(() {
                            _activeDatasetId = value;
                          });
                        },
                      ),
                    if (needsActiveDatasetPicker) const SizedBox(height: 12),
                    Expanded(
                      child: _VisualizationChart(
                        logic: logic,
                        nodeId: node.id,
                        datasets: _selectedDatasets(datasets),
                        activeDatasetId: _activeDatasetId,
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

  List<Dataset> _selectedDatasets(List<Dataset> datasets) {
    return datasets
        .where((Dataset dataset) => _selectedDatasetIds.contains(dataset.id))
        .toList(growable: false);
  }

  void _syncSelectedDatasets(List<Dataset> datasets) {
    if (datasets.isEmpty) {
      _selectedDatasetIds.clear();
      _materializedDatasetsFuture = Future<List<Dataset>>.value(const <Dataset>[]);
      _materializedDatasetsKey = '';
      return;
    }

    final Set<String> availableIds =
        datasets.map((Dataset dataset) => dataset.id).toSet();
    _selectedDatasetIds.removeWhere((String id) => !availableIds.contains(id));
    if (_activeDatasetId != null && !_selectedDatasetIds.contains(_activeDatasetId)) {
      _activeDatasetId = _selectedDatasetIds.isEmpty ? null : _selectedDatasetIds.first;
    }
  }

  void _refreshMaterializedDatasets(List<Dataset> selectedSourceDatasets) {
    final String key = <String>[
      widget.nodeId,
      ...selectedSourceDatasets.map((Dataset dataset) => dataset.id),
    ].join('|');
    if (_materializedDatasetsFuture != null && _materializedDatasetsKey == key) {
      return;
    }
    _materializedDatasetsKey = key;
    _materializedDatasetsFuture = logic.materializedDatasetViewsForNode(
      widget.nodeId,
      selectedSourceDatasets,
    );
  }
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
      return _HypnogramChart(dataset: activeDataset);
    }
    if (comparisonNode && datasets.length > 1) {
      return const _ChartMessage(
        title: 'Raw comparison is not ready yet',
        body: 'Select one dataset for the raw browser. PSD comparison overlays are inferred and rendered automatically when this node is fed from a PSD path.',
      );
    }
    final Dataset activeDataset = datasets.firstWhere(
      (Dataset dataset) => dataset.id == activeDatasetId,
      orElse: () => datasets.first,
    );
    return RawSignalBrowser(
      dataset: activeDataset,
      params: params,
      onMarkersChanged: (List<dynamic> rawMarkers) {
        logic.applyMarkersFromVisualization(
          nodeId: nodeId,
          dataset: activeDataset,
          rawMarkers: rawMarkers,
        );
      },
      onInteractiveArtifactDetectionSaved: () {
        logic.applyInteractiveArtifactDetectionFromVisualization(
          nodeId: nodeId,
          dataset: activeDataset,
        );
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
    );
  }
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
  required bool logY,
}) {
  final double xInterval = _niceAxisStep(maxX - minX);
  final double yInterval = _niceAxisStep(maxY - minY);
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      axisNameWidget: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: const Text(
          'Hz',
          style: TextStyle(color: Colors.white70),
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
      axisNameWidget: RotatedBox(
        quarterTurns: 3,
        child: Text(
          logY ? 'log10(uV^2/Hz)' : 'uV^2/Hz',
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
            child: Text(
              _formatAxisValue(value, logY: logY),
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

String _formatAxisValue(double value, {required bool logY}) {
  if (logY) {
    return '1e${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}';
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
