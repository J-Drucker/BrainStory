import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../model/dataset.dart';
import '../model/node.dart';
import 'canvas_logic.dart';

class VisualizationPanel extends StatefulWidget {
  const VisualizationPanel({
    super.key,
    required this.logic,
    required this.onChanged,
  });

  final CanvasLogic logic;
  final VoidCallback onChanged;

  @override
  State<VisualizationPanel> createState() => _VisualizationPanelState();
}

class _VisualizationPanelState extends State<VisualizationPanel> {
  String? _selectedDatasetId;

  CanvasLogic get logic => widget.logic;

  @override
  void didUpdateWidget(covariant VisualizationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelectedDataset();
  }

  @override
  Widget build(BuildContext context) {
    _syncSelectedDataset();

    final NodeModel? node = logic.selectedVisualizationNode;
    final List<Dataset> datasets = logic.datasetsForSelectedVisualizationNode;

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(12),
      child: node == null
          ? _emptyState(
              'Visualization',
              'Select an EEG Visualization node to inspect its output.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                if (datasets.isEmpty)
                  _emptyState(
                    'No dataset',
                    'Connect this node to an Import path and choose a dataset in the Import node settings.',
                  )
                else ...<Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDatasetId,
                    decoration: const InputDecoration(
                      labelText: 'Dataset',
                      filled: true,
                    ),
                    dropdownColor: Colors.grey[850],
                    items: datasets
                        .map(
                          (Dataset dataset) => DropdownMenuItem<String>(
                            value: dataset.id,
                            child: Text(dataset.label),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      setState(() {
                        _selectedDatasetId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _VisualizationChart(
                      dataset: _selectedDataset(datasets),
                      params: node.params,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Dataset? _selectedDataset(List<Dataset> datasets) {
    if (datasets.isEmpty) {
      return null;
    }
    return datasets.firstWhere(
      (Dataset dataset) => dataset.id == _selectedDatasetId,
      orElse: () => datasets.first,
    );
  }

  void _syncSelectedDataset() {
    final List<Dataset> datasets = logic.datasetsForSelectedVisualizationNode;
    if (datasets.isEmpty) {
      _selectedDatasetId = null;
      return;
    }

    final bool stillPresent = datasets.any(
      (Dataset dataset) => dataset.id == _selectedDatasetId,
    );
    if (!stillPresent) {
      _selectedDatasetId = datasets.first.id;
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
}

class _VisualizationChart extends StatelessWidget {
  const _VisualizationChart({
    required this.dataset,
    required this.params,
  });

  final Dataset? dataset;
  final Map<String, dynamic> params;

  @override
  Widget build(BuildContext context) {
    if (dataset == null) {
      return const SizedBox.shrink();
    }

    final String view = (params['view'] ?? 'raw').toString();

    if (view == 'psd') {
      return _PsdChart(dataset: dataset!);
    }
    return _RawSignalChart(
      dataset: dataset!,
      windowSec: (params['window_sec'] as num?)?.toDouble() ?? 5.0,
    );
  }
}

class _RawSignalChart extends StatelessWidget {
  const _RawSignalChart({
    required this.dataset,
    required this.windowSec,
  });

  final Dataset dataset;
  final double windowSec;

  @override
  Widget build(BuildContext context) {
    final List<double>? samples = dataset.ram['signal.samples'] as List<double>?;
    final double? fs = dataset.ram['signal.fs'] as double?;

    if (samples == null || samples.isEmpty || fs == null) {
      return _ChartMessage(
        title: 'No raw signal',
        body: 'Run an Import node upstream of the visualization node first.',
      );
    }

    final int maxSamples = math.max(64, (windowSec * fs).round());
    final List<double> visibleSamples = samples.length > maxSamples
        ? samples.sublist(samples.length - maxSamples)
        : samples;

    final List<FlSpot> points = <FlSpot>[
      for (int i = 0; i < visibleSamples.length; i++)
        FlSpot(i / fs, visibleSamples[i]),
    ];

    final double minY = visibleSamples.reduce(math.min);
    final double maxY = visibleSamples.reduce(math.max);
    final double amplitudePad = math.max(0.1, (maxY - minY) * 0.15);

    return _ChartCard(
      title: '${dataset.label} · Raw Signal',
      subtitle: '${visibleSamples.length} samples at ${fs.toStringAsFixed(1)} Hz',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: points.isEmpty ? 1 : points.last.x,
          minY: minY - amplitudePad,
          maxY: maxY + amplitudePad,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          titlesData: _chartTitles(
            bottomLabel: 'Time (s)',
            leftLabel: 'Amp',
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: points,
              isCurved: false,
              barWidth: 2,
              color: Colors.cyanAccent,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _PsdChart extends StatelessWidget {
  const _PsdChart({
    required this.dataset,
  });

  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final List<double>? freqs = dataset.ram['psd.freqs'] as List<double>?;
    final List<double>? power = dataset.ram['psd.power'] as List<double>?;

    if (freqs == null || power == null || freqs.isEmpty || power.isEmpty) {
      return _ChartMessage(
        title: 'No PSD data',
        body: 'Run a PSD node upstream, then run the visualization node again.',
      );
    }

    final int count = math.min(freqs.length, power.length);
    final List<double> visibleFreqs = freqs.sublist(0, count);
    final List<double> visiblePower = power.sublist(0, count);
    final List<FlSpot> points = <FlSpot>[
      for (int i = 0; i < count; i++) FlSpot(visibleFreqs[i], visiblePower[i]),
    ];

    final double minY = visiblePower.reduce(math.min);
    final double maxY = visiblePower.reduce(math.max);
    final double amplitudePad = math.max(0.1, (maxY - minY) * 0.15);

    return _ChartCard(
      title: '${dataset.label} · PSD',
      subtitle: '$count bins',
      child: LineChart(
        LineChartData(
          minX: points.isEmpty ? 0 : points.first.x,
          maxX: points.isEmpty ? 1 : points.last.x,
          minY: minY - amplitudePad,
          maxY: maxY + amplitudePad,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          titlesData: _chartTitles(
            bottomLabel: 'Hz',
            leftLabel: 'Power',
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: points,
              isCurved: true,
              barWidth: 2,
              color: Colors.orangeAccent,
              dotData: const FlDotData(show: false),
            ),
          ],
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
  });

  final String title;
  final String subtitle;
  final Widget child;

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
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
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
