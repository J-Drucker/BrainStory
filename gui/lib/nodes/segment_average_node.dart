import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class SegmentAverageNodeType extends NodeType {
  @override
  String get title => 'Average Segments';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Time Domain';

  @override
  Map<String, dynamic> get defaultParams => const <String, dynamic>{};

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
    return const Text(
      'Creates one average segment per condition while preserving channels '
      'and sample timing.',
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final SegmentedTimeSeriesData? segmented = dataset.segmentedTimeSeries;
    if (segmented == null || segmented.segments.isEmpty) {
      return;
    }

    final Map<String, List<SignalSegmentData>> grouped =
        <String, List<SignalSegmentData>>{};
    for (final SignalSegmentData segment in segmented.segments) {
      grouped
          .putIfAbsent(segment.label, () => <SignalSegmentData>[])
          .add(segment);
    }

    final List<SignalSegmentData> averages = <SignalSegmentData>[];
    for (final MapEntry<String, List<SignalSegmentData>> entry
        in grouped.entries) {
      final List<List<List<double>>> materialized = entry.value
          .map(segmented.channelSamplesForSegment)
          .where((List<List<double>> channels) => channels.isNotEmpty)
          .toList(growable: false);
      if (materialized.isEmpty) {
        continue;
      }
      final int channelCount = materialized
          .map((List<List<double>> channels) => channels.length)
          .reduce((int a, int b) => a < b ? a : b);
      final int sampleCount = materialized
          .map(
            (List<List<double>> channels) => channels
                .take(channelCount)
                .map((List<double> samples) => samples.length)
                .reduce((int a, int b) => a < b ? a : b),
          )
          .reduce((int a, int b) => a < b ? a : b);
      if (channelCount == 0 || sampleCount == 0) {
        continue;
      }
      final List<List<double>> meanChannels = List<List<double>>.generate(
        channelCount,
        (_) => List<double>.filled(sampleCount, 0.0),
        growable: false,
      );
      for (final List<List<double>> channels in materialized) {
        for (int channel = 0; channel < channelCount; channel++) {
          for (int sample = 0; sample < sampleCount; sample++) {
            meanChannels[channel][sample] += channels[channel][sample];
          }
        }
      }
      for (final List<double> channel in meanChannels) {
        for (int sample = 0; sample < channel.length; sample++) {
          channel[sample] /= materialized.length;
        }
      }
      final SignalSegmentData first = entry.value.first;
      averages.add(
        SignalSegmentData(
          channelSamples: meanChannels,
          startSeconds: first.startSeconds,
          stopSeconds:
              first.startSeconds + (sampleCount / segmented.sampleRate),
          label: entry.key,
          kind: 'average',
          anchorTimeSeconds: first.anchorTimeSeconds,
        ),
      );
    }

    dataset.segmentedTimeSeries = segmented.copyWith(
      segments: averages,
      clearSourceTimeSeries: true,
    );
  }
}
