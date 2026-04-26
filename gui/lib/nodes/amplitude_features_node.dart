import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class AmplitudeFeaturesNodeType extends NodeType {
  @override
  String get title => 'Amplitude Features';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Time Domain';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'amplitudeFeatures': <String, dynamic>{
          'peak_amplitude': true,
          'peak_latency': true,
          'auc': false,
          'variance': false,
        },
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'table', type: PortType.metadata),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent(
      'amplitudeFeatures',
      () => Map<String, dynamic>.from(defaultParams['amplitudeFeatures'] as Map),
    );

    final Map<String, dynamic> amplitudeFeatures = Map<String, dynamic>.from(
      params['amplitudeFeatures'] as Map? ?? <String, dynamic>{},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Computes a feature table from time-domain signal data. The output is stored as a table artifact so it can be exported to CSV later.',
        ),
        const SizedBox(height: 12),
        _AmplitudeFeatureGroupSection(
          title: 'Amplitude',
          entries: const <MapEntry<String, String>>[
            MapEntry<String, String>('peak_amplitude', 'Peak Amplitude'),
            MapEntry<String, String>('peak_latency', 'Peak Latency'),
            MapEntry<String, String>('auc', 'Area Under the Curve (AUC)'),
            MapEntry<String, String>('variance', 'Variance'),
          ],
          selected: amplitudeFeatures,
          onChanged: (String key, bool value) {
            setState(() {
              final Map<String, dynamic> next = Map<String, dynamic>.from(
                params['amplitudeFeatures'] as Map? ?? <String, dynamic>{},
              );
              next[key] = value;
              params['amplitudeFeatures'] = next;
            });
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'More time-domain feature groups can be added later without changing the output format.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    final List<double> samples = timeSeries?.primaryChannel ?? const <double>[];
    if (timeSeries == null || samples.isEmpty) {
      dataset.featureTable = null;
      return;
    }

    final Map<String, dynamic> amplitudeFeatures = Map<String, dynamic>.from(
      params['amplitudeFeatures'] as Map? ?? <String, dynamic>{},
    );
    final Map<String, String> row = <String, String>{
      'dataset': dataset.label,
    };
    final List<String> columns = <String>['dataset'];

    void addFeature(String column, double value) {
      columns.add(column);
      row[column] = value.toStringAsFixed(6);
    }

    final int peakIndex = _peakIndex(samples);
    if (amplitudeFeatures['peak_amplitude'] == true) {
      addFeature('peak_amplitude', samples[peakIndex]);
    }
    if (amplitudeFeatures['peak_latency'] == true) {
      addFeature('peak_latency_ms', (peakIndex / timeSeries.sampleRate) * 1000.0);
    }
    if (amplitudeFeatures['auc'] == true) {
      addFeature('auc', _auc(samples, timeSeries.sampleRate));
    }
    if (amplitudeFeatures['variance'] == true) {
      addFeature('variance', _variance(samples));
    }

    dataset.featureTable = FeatureTableData(
      columns: columns,
      rows: <Map<String, String>>[row],
      source: timeSeries.source,
    );
    dataset.ram['amplitudeFeatures.params'] = <String, dynamic>{
      'amplitudeFeatures': amplitudeFeatures,
    };
  }
}

class _AmplitudeFeatureGroupSection extends StatelessWidget {
  const _AmplitudeFeatureGroupSection({
    required this.title,
    required this.entries,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<MapEntry<String, String>> entries;
  final Map<String, dynamic> selected;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...entries.map((MapEntry<String, String> entry) {
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                value: selected[entry.key] == true,
                title: Text(entry.value),
                onChanged: (bool? value) => onChanged(entry.key, value ?? false),
              );
            }),
          ],
        ),
      ),
    );
  }
}

int _peakIndex(List<double> samples) {
  int peakIndex = 0;
  double peakValue = samples.first;
  for (int index = 1; index < samples.length; index++) {
    if (samples[index] > peakValue) {
      peakValue = samples[index];
      peakIndex = index;
    }
  }
  return peakIndex;
}

double _auc(List<double> samples, double sampleRate) {
  if (samples.length < 2 || sampleRate <= 0) {
    return 0.0;
  }
  double total = 0.0;
  final double dt = 1.0 / sampleRate;
  for (int index = 1; index < samples.length; index++) {
    total += ((samples[index - 1] + samples[index]) * 0.5) * dt;
  }
  return total;
}

double _variance(List<double> samples) {
  if (samples.isEmpty) {
    return 0.0;
  }
  final double mean =
      samples.reduce((double a, double b) => a + b) / samples.length;
  double total = 0.0;
  for (final double sample in samples) {
    final double delta = sample - mean;
    total += delta * delta;
  }
  return total / samples.length;
}
