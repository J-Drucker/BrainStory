import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';
import 'resample_node.dart';

class RealignNodeType extends NodeType {
  @override
  String get title => 'Realign';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'upsampleRateHz': 100000.0,
        'method': 'cubic_spline',
        'maxShiftMs': 5.0,
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'segments', type: PortType.metadata),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'segments', type: PortType.metadata),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('upsampleRateHz', () => 100000.0);
    params.putIfAbsent('method', () => 'cubic_spline');
    params.putIfAbsent('maxShiftMs', () => 5.0);

    final List<dynamic> selectedIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[];
    final List<SegmentedTimeSeriesData> visibleSegmentSets = datasets.values
        .where((Dataset dataset) {
          return selectedIds.isEmpty || selectedIds.contains(dataset.id);
        })
        .map((Dataset dataset) => dataset.segmentedTimeSeries)
        .whereType<SegmentedTimeSeriesData>()
        .toList(growable: false);

    final String sampleRateLabel = _segmentRateLabel(visibleSegmentSets);
    final String segmentCountLabel = visibleSegmentSets.isEmpty
        ? 'unavailable until a Segmentation node has been run upstream'
        : visibleSegmentSets
            .map((SegmentedTimeSeriesData data) => data.segmentCount.toString())
            .toSet()
            .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Current segmented sample rate: $sampleRateLabel',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Current segment count: $segmentCountLabel',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        const Text(
          'Realign temporarily upsamples each segment, estimates the best time shift by cross-correlation, then downsamples back to the original segmented sample rate. This is intended for artifact alignment after segmentation.',
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'upsampleRateHz',
          labelText: 'Temporary upsample rate (Hz)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: (String value, dynamic previous) =>
              double.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'method',
          labelText: 'Resampling method',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'cubic_spline',
              label: 'Cubic spline',
            ),
            NodeDropdownOption<String>(value: 'linear', label: 'Linear'),
            NodeDropdownOption<String>(value: 'nearest', label: 'Nearest'),
          ],
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'maxShiftMs',
          labelText: 'Maximum shift (ms)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: (String value, dynamic previous) =>
              double.tryParse(value) ?? previous,
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final SegmentedTimeSeriesData? segmented = dataset.segmentedTimeSeries;
    if (segmented == null || segmented.segments.isEmpty) {
      throw StateError(
        'Realign requires segmented data from an upstream Segmentation node.',
      );
    }

    if (segmented.segments.length == 1) {
      dataset.segmentedTimeSeries = segmented.copyWith(
        segments: segmented.segments
            .map(
              (SignalSegmentData segment) => segment.copyWith(appliedShiftMs: 0.0),
            )
            .toList(growable: false),
      );
      return;
    }

    final double targetSampleRate =
        (params['upsampleRateHz'] as num?)?.toDouble() ?? 100000.0;
    final String method = (params['method'] ?? 'cubic_spline').toString();
    final double maxShiftMs =
        (params['maxShiftMs'] as num?)?.toDouble() ?? 5.0;
    final int maxShiftSamples = math.max(
      0,
      ((maxShiftMs / 1000.0) * targetSampleRate).round(),
    );

    final List<SignalSegmentData> segments = segmented.segments;
    final List<List<double>> referenceChannels =
        segmented.channelSamplesForSegment(segments.first);
    final List<List<double>> referenceUpsampled = referenceChannels
        .map(
          (List<double> channel) => resampleSignal(
            channel,
            sourceSampleRate: segmented.sampleRate,
            targetSampleRate: targetSampleRate,
            method: method,
          ),
        )
        .toList(growable: false);
    final List<double> referenceTemplate = _alignmentTemplate(referenceUpsampled);

    final List<SignalSegmentData> alignedSegments = <SignalSegmentData>[];
    for (final SignalSegmentData segment in segments) {
      final List<List<double>> segmentChannels =
          segmented.channelSamplesForSegment(segment);
      final List<List<double>> upsampledChannels = segmentChannels
          .map(
            (List<double> channel) => resampleSignal(
              channel,
              sourceSampleRate: segmented.sampleRate,
              targetSampleRate: targetSampleRate,
              method: method,
            ),
          )
          .toList(growable: false);

      final List<double> segmentTemplate = _alignmentTemplate(upsampledChannels);
      final int shiftSamples = _bestShiftSamples(
        reference: referenceTemplate,
        target: segmentTemplate,
        maxShiftSamples: maxShiftSamples,
      );

      final List<List<double>> shiftedChannels = upsampledChannels
          .map((List<double> channel) => _shiftSamples(channel, shiftSamples))
          .map(
            (List<double> channel) => _resizeToLength(
              resampleSignal(
                channel,
                sourceSampleRate: targetSampleRate,
                targetSampleRate: segmented.sampleRate,
                method: method,
              ),
              segmented.sampleCountForSegment(segment),
            ),
          )
          .toList(growable: false);

      alignedSegments.add(
        segment.copyWith(
          channelSamples: shiftedChannels,
          clearSourceWindow: true,
          appliedShiftMs: shiftSamples / targetSampleRate * 1000.0,
        ),
      );
    }

    dataset.segmentedTimeSeries = segmented.copyWith(
      segments: alignedSegments,
    );
    dataset.ram['realign.params'] = <String, dynamic>{
      'upsampleRateHz': targetSampleRate,
      'method': method,
      'maxShiftMs': maxShiftMs,
    };
  }
}

String _segmentRateLabel(List<SegmentedTimeSeriesData> segmentSets) {
  if (segmentSets.isEmpty) {
    return 'unavailable until an upstream segmentation has been run';
  }

  final List<double> uniqueRates = <double>[];
  for (final SegmentedTimeSeriesData data in segmentSets) {
    final bool seen = uniqueRates.any(
      (double value) => (value - data.sampleRate).abs() < 0.001,
    );
    if (!seen) {
      uniqueRates.add(data.sampleRate);
    }
  }

  return uniqueRates
      .map(
        (double value) => value.truncateToDouble() == value
            ? '${value.toStringAsFixed(0)} Hz'
            : '${value.toStringAsFixed(2)} Hz',
      )
      .join(', ');
}

List<double> _alignmentTemplate(List<List<double>> channels) {
  if (channels.isEmpty) {
    return const <double>[];
  }
  final int sampleCount = channels.first.length;
  final List<double> template = List<double>.filled(sampleCount, 0.0);
  for (final List<double> channel in channels) {
    for (int index = 0; index < sampleCount && index < channel.length; index++) {
      template[index] += channel[index];
    }
  }
  for (int index = 0; index < sampleCount; index++) {
    template[index] /= channels.length;
  }

  final double mean =
      template.fold<double>(0.0, (double sum, double value) => sum + value) /
          math.max(1, template.length);
  return template
      .map((double value) => value - mean)
      .toList(growable: false);
}

int _bestShiftSamples({
  required List<double> reference,
  required List<double> target,
  required int maxShiftSamples,
}) {
  if (reference.isEmpty || target.isEmpty) {
    return 0;
  }

  int bestShift = 0;
  double bestScore = double.negativeInfinity;
  for (int shift = -maxShiftSamples; shift <= maxShiftSamples; shift++) {
    double score = 0.0;
    for (int index = 0; index < reference.length; index++) {
      final int targetIndex = index - shift;
      if (targetIndex < 0 || targetIndex >= target.length) {
        continue;
      }
      score += reference[index] * target[targetIndex];
    }
    if (score > bestScore) {
      bestScore = score;
      bestShift = shift;
    }
  }
  return bestShift;
}

List<double> _shiftSamples(List<double> samples, int shiftSamples) {
  if (samples.isEmpty || shiftSamples == 0) {
    return List<double>.from(samples);
  }

  final List<double> output = List<double>.filled(samples.length, 0.0);
  for (int index = 0; index < samples.length; index++) {
    final int sourceIndex = index - shiftSamples;
    if (sourceIndex < 0 || sourceIndex >= samples.length) {
      continue;
    }
    output[index] = samples[sourceIndex];
  }
  return output;
}

List<double> _resizeToLength(List<double> input, int length) {
  if (input.length == length) {
    return input;
  }
  if (input.length > length) {
    return input.sublist(0, length);
  }
  return <double>[
    ...input,
    ...List<double>.filled(length - input.length, 0.0),
  ];
}
