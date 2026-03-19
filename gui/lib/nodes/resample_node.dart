import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class ResampleNodeType extends NodeType {
  @override
  String get title => 'Resample';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'newSampleRate': 256.0,
    'method': 'cubic_spline',
    'omitSpikes': false,
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('newSampleRate', () => 256.0);
    params.putIfAbsent('method', () => 'cubic_spline');
    params.putIfAbsent('omitSpikes', () => false);

    final List<double> visibleSampleRates = datasets.values
        .where((Dataset dataset) {
          final List<dynamic> selectedIds =
              params['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[];
          return selectedIds.isEmpty || selectedIds.contains(dataset.id);
        })
        .map((Dataset dataset) => dataset.timeSeries?.sampleRate)
        .whereType<double>()
        .toList(growable: false);

    final String currentRateLabel = _currentRateLabel(visibleSampleRates);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Current sample rate: $currentRateLabel',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: params['newSampleRate']?.toString() ?? '256.0',
          decoration: const InputDecoration(labelText: 'New sample rate (Hz)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (String value) {
            setState(() {
              params['newSampleRate'] =
                  double.tryParse(value) ?? params['newSampleRate'];
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: params['method']?.toString() ?? 'cubic_spline',
          decoration: const InputDecoration(labelText: 'Method'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'cubic_spline',
              child: Text('Cubic spline'),
            ),
            DropdownMenuItem<String>(
              value: 'linear',
              child: Text('Linear'),
            ),
            DropdownMenuItem<String>(
              value: 'nearest',
              child: Text('Nearest'),
            ),
          ],
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            setState(() {
              params['method'] = value;
            });
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Omit spikes'),
          value: (params['omitSpikes'] as bool?) ?? false,
          onChanged: (bool? value) {
            setState(() {
              params['omitSpikes'] = value ?? false;
            });
          },
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.primaryChannel.isEmpty) {
      return;
    }

    final double targetSampleRate =
        (params['newSampleRate'] as num?)?.toDouble() ?? 256.0;
    final String method = (params['method'] ?? 'cubic_spline').toString();
    final bool omitSpikes = (params['omitSpikes'] as bool?) ?? false;

    dataset.timeSeries = TimeSeriesData(
      channelSamples: timeSeries.channels.map((List<double> channel) {
        final List<double> preparedSamples = omitSpikes
            ? suppressSpikes(channel)
            : List<double>.from(channel);
        return resampleSignal(
          preparedSamples,
          sourceSampleRate: timeSeries.sampleRate,
          targetSampleRate: targetSampleRate,
          method: method,
        );
      }).toList(growable: false),
      sampleRate: targetSampleRate,
      channelLabels: timeSeries.channelLabels,
      markers: timeSeries.markers
          .map((TimeMarker marker) => marker.copyWith())
          .toList(growable: false),
      source: timeSeries.source,
    );
  }
}

String _currentRateLabel(List<double> sampleRates) {
  if (sampleRates.isEmpty) {
    return 'unavailable until an upstream signal has been run';
  }

  final List<double> uniqueRates = <double>[];
  for (final double rate in sampleRates) {
    final bool seen = uniqueRates.any((double value) => (value - rate).abs() < 0.001);
    if (!seen) {
      uniqueRates.add(rate);
    }
  }

  if (uniqueRates.length == 1) {
    return '${uniqueRates.first.toStringAsFixed(uniqueRates.first.truncateToDouble() == uniqueRates.first ? 0 : 2)} Hz';
  }

  return uniqueRates
      .map((double rate) => '${rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 2)} Hz')
      .join(', ');
}

List<double> resampleSignal(
  List<double> input, {
  required double sourceSampleRate,
  required double targetSampleRate,
  required String method,
}) {
  if (input.isEmpty || sourceSampleRate <= 0 || targetSampleRate <= 0) {
    return List<double>.from(input);
  }

  if ((sourceSampleRate - targetSampleRate).abs() < 0.0001) {
    return List<double>.from(input);
  }

  final double durationSeconds = input.length / sourceSampleRate;
  final int outputLength = math.max(1, (durationSeconds * targetSampleRate).round());

  return List<double>.generate(outputLength, (int index) {
    final double sourceIndex = index * sourceSampleRate / targetSampleRate;
    switch (method) {
      case 'nearest':
        return _nearestSample(input, sourceIndex);
      case 'linear':
        return _linearSample(input, sourceIndex);
      case 'cubic_spline':
      default:
        return _cubicSample(input, sourceIndex);
    }
  });
}

List<double> suppressSpikes(List<double> input) {
  if (input.length < 5) {
    return List<double>.from(input);
  }

  final List<double> output = List<double>.from(input);
  for (int index = 2; index < input.length - 2; index++) {
    final List<double> neighborhood = <double>[
      input[index - 2],
      input[index - 1],
      input[index + 1],
      input[index + 2],
    ]..sort();
    final double median = (neighborhood[1] + neighborhood[2]) / 2.0;
    final List<double> deviations = neighborhood
        .map((double value) => (value - median).abs())
        .toList()
      ..sort();
    final double mad = (deviations[1] + deviations[2]) / 2.0;
    final double threshold = math.max(1e-6, mad * 6.0);
    if ((input[index] - median).abs() > threshold) {
      output[index] = median;
    }
  }
  return output;
}

double _nearestSample(List<double> samples, double sourceIndex) {
  final int index = sourceIndex.round().clamp(0, samples.length - 1);
  return samples[index];
}

double _linearSample(List<double> samples, double sourceIndex) {
  final int leftIndex = sourceIndex.floor().clamp(0, samples.length - 1);
  final int rightIndex = math.min(leftIndex + 1, samples.length - 1);
  final double fraction = sourceIndex - leftIndex;
  return samples[leftIndex] * (1.0 - fraction) + samples[rightIndex] * fraction;
}

double _cubicSample(List<double> samples, double sourceIndex) {
  final int index1 = sourceIndex.floor();
  final double t = sourceIndex - index1;

  final double p0 = samples[_clampIndex(index1 - 1, samples.length)];
  final double p1 = samples[_clampIndex(index1, samples.length)];
  final double p2 = samples[_clampIndex(index1 + 1, samples.length)];
  final double p3 = samples[_clampIndex(index1 + 2, samples.length)];

  final double a = (-0.5 * p0) + (1.5 * p1) - (1.5 * p2) + (0.5 * p3);
  final double b = p0 - (2.5 * p1) + (2.0 * p2) - (0.5 * p3);
  final double c = (-0.5 * p0) + (0.5 * p2);
  final double d = p1;

  return ((a * t + b) * t + c) * t + d;
}

int _clampIndex(int index, int length) {
  return index.clamp(0, length - 1);
}
