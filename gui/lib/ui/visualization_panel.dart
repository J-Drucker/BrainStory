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
      return _PsdChart(
        datasets: datasets,
        params: params,
        onChanged: onChanged,
      );
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
