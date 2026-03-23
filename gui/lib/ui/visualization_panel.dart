import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/node.dart';
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

  CanvasLogic get logic => widget.logic;

  @override
  void didUpdateWidget(covariant VisualizationSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      _selectedDatasetIds.clear();
      _activeDatasetId = null;
    }
    _syncSelectedDatasets();
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
    _syncSelectedDatasets();

      final List<Dataset> datasets = logic.datasetsForVisualizationNode(widget.nodeId);
    final String view = logic.visualizationViewForNode(node);
    final bool comparisonNode = logic.isVisualizationNode(node);

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
        if (datasets.isEmpty)
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
            children: datasets.map((Dataset dataset) {
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
          if (view == 'raw' && _selectedDatasets(datasets).length > 1)
            DropdownButtonFormField<String>(
              initialValue: _activeDatasetId ?? _selectedDatasets(datasets).first.id,
              decoration: const InputDecoration(
                labelText: 'Active dataset for raw browser',
              ),
              items: _selectedDatasets(datasets)
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
          if (view == 'raw' && _selectedDatasets(datasets).length > 1)
            const SizedBox(height: 12),
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
                setState(() {});
                widget.onChanged?.call();
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

  void _syncSelectedDatasets() {
    final List<Dataset> datasets = logic.datasetsForVisualizationNode(widget.nodeId);
    if (datasets.isEmpty) {
      _selectedDatasetIds.clear();
      return;
    }

    final Set<String> availableIds =
        datasets.map((Dataset dataset) => dataset.id).toSet();
    _selectedDatasetIds.removeWhere((String id) => !availableIds.contains(id));
    if (_activeDatasetId != null && !_selectedDatasetIds.contains(_activeDatasetId)) {
      _activeDatasetId = _selectedDatasetIds.isEmpty ? null : _selectedDatasetIds.first;
    }
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
      return _PsdChart(datasets: datasets);
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
      onChanged: onChanged,
    );
  }
}

class _PsdChart extends StatelessWidget {
  const _PsdChart({
    required this.datasets,
  });

  final List<Dataset> datasets;

  @override
  Widget build(BuildContext context) {
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
      final List<FlSpot> points = <FlSpot>[
        for (int i = 0; i < count; i++) FlSpot(freqs[i], power[i]),
      ];

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
    final double minY = allY.reduce(math.min);
    final double maxY = allY.reduce(math.max);
    final double amplitudePad = math.max(0.1, (maxY - minY) * 0.15);

    return _ChartCard(
      title: 'PSD',
      subtitle: '${series.length} overlay${series.length == 1 ? '' : 's'}',
      legend: series,
      child: LineChart(
        LineChartData(
          minX: allX.reduce(math.min),
          maxX: allX.reduce(math.max),
          minY: minY - amplitudePad,
          maxY: maxY + amplitudePad,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          titlesData: _chartTitles(
            bottomLabel: 'Hz',
            leftLabel: 'uV^2/Hz',
          ),
          lineBarsData: series
              .map(
                (_SeriesData seriesData) => LineChartBarData(
                  spots: seriesData.points,
                  isCurved: true,
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.legend = const <_SeriesData>[],
  });

  final String title;
  final String subtitle;
  final Widget child;
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
  required String bottomLabel,
  required String leftLabel,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      axisNameWidget: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          bottomLabel,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
      sideTitles: const SideTitles(showTitles: true, reservedSize: 28),
    ),
    leftTitles: AxisTitles(
      axisNameWidget: RotatedBox(
        quarterTurns: 3,
        child: Text(
          leftLabel,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
      sideTitles: const SideTitles(showTitles: true, reservedSize: 42),
    ),
  );
}
