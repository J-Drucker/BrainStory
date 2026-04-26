import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class ResampleNodeType extends NodeType {
  @override
  String get title => 'Resample';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  String get subcategory => 'Subcategory 1';

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
  bool get supportsBackgroundRun => true;

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
        NodeParamTextField(
          params: params,
          paramKey: 'newSampleRate',
          labelText: 'New sample rate (Hz)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: (String value, dynamic previous) =>
              double.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'method',
          labelText: 'Method',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'cubic_spline',
              label: 'Cubic spline',
            ),
            NodeDropdownOption<String>(value: 'linear', label: 'Linear'),
            NodeDropdownOption<String>(value: 'nearest', label: 'Nearest'),
          ],
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
        final List<double> preparedSamples =
            omitSpikes ? suppressSpikes(channel) : channel;
        return resampleSignal(
          preparedSamples,
          sourceSampleRate: timeSeries.sampleRate,
          targetSampleRate: targetSampleRate,
          method: method,
        );
      }).toList(growable: false),
      sampleRate: targetSampleRate,
      channelLabels: timeSeries.channelLabels,
      channelCoordinates: timeSeries.channelCoordinates,
      markers: timeSeries.markers
          .map((TimeMarker marker) => marker.copyWith())
          .toList(growable: false),
      factors: timeSeries.factors,
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
  final double sourceStep = sourceSampleRate / targetSampleRate;

  switch (method) {
    case 'nearest':
      return _resampleNearest(
        input,
        outputLength: outputLength,
        sourceStep: sourceStep,
      );
    case 'linear':
      return _resampleLinear(
        input,
        outputLength: outputLength,
        sourceStep: sourceStep,
      );
    case 'cubic_spline':
    default:
      return _resampleCubic(
        input,
        outputLength: outputLength,
        sourceStep: sourceStep,
      );
  }
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

List<double> _resampleNearest(
  List<double> samples, {
  required int outputLength,
  required double sourceStep,
}) {
  final int maxIndex = samples.length - 1;
  final Float32List output = Float32List(outputLength);
  double sourceIndex = 0.0;
  for (int index = 0; index < outputLength; index++, sourceIndex += sourceStep) {
    output[index] = samples[sourceIndex.round().clamp(0, maxIndex)];
  }
  return output;
}

List<double> _resampleLinear(
  List<double> samples, {
  required int outputLength,
  required double sourceStep,
}) {
  final int maxIndex = samples.length - 1;
  final Float32List output = Float32List(outputLength);
  double sourceIndex = 0.0;
  for (int index = 0; index < outputLength; index++, sourceIndex += sourceStep) {
    final int leftIndex = sourceIndex.floor().clamp(0, maxIndex);
    final int rightIndex = math.min(leftIndex + 1, maxIndex);
    final double fraction = sourceIndex - leftIndex;
    output[index] =
        samples[leftIndex] * (1.0 - fraction) + samples[rightIndex] * fraction;
  }
  return output;
}

List<double> _resampleCubic(
  List<double> samples, {
  required int outputLength,
  required double sourceStep,
}) {
  final int length = samples.length;
  final Float32List output = Float32List(outputLength);
  double sourceIndex = 0.0;
  for (int index = 0; index < outputLength; index++, sourceIndex += sourceStep) {
    final int index1 = sourceIndex.floor();
    final double t = sourceIndex - index1;

    final double p0 = samples[_clampIndex(index1 - 1, length)];
    final double p1 = samples[_clampIndex(index1, length)];
    final double p2 = samples[_clampIndex(index1 + 1, length)];
    final double p3 = samples[_clampIndex(index1 + 2, length)];

    final double a = (-0.5 * p0) + (1.5 * p1) - (1.5 * p2) + (0.5 * p3);
    final double b = p0 - (2.5 * p1) + (2.0 * p2) - (0.5 * p3);
    final double c = (-0.5 * p0) + (0.5 * p2);
    final double d = p1;

    output[index] = ((a * t + b) * t + c) * t + d;
  }
  return output;
}

int _clampIndex(int index, int length) {
  return index.clamp(0, length - 1);
}
