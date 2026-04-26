import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class BridgeDetectorNodeType extends NodeType {
  @override
  String get title => 'Bridge Detector';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  String get subcategory => 'Quality Control';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'windowSamples': 1000,
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'metadata', type: PortType.metadata),
      ];

  @override
  bool get supportsBackgroundRun => true;

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('windowSamples', () => 1000);

    final List<dynamic> selectedIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final TimeSeriesData? visibleTimeSeries = datasets.values
        .where((Dataset dataset) => selectedIds.isEmpty || selectedIds.contains(dataset.id))
        .map((Dataset dataset) => dataset.timeSeries)
        .whereType<TimeSeriesData>()
        .cast<TimeSeriesData?>()
        .firstWhere((TimeSeriesData? value) => value != null, orElse: () => null);

    final double? sampleRate = visibleTimeSeries?.sampleRate;
    final int windowSamples = (params['windowSamples'] as num?)?.toInt() ?? 1000;
    final String exampleRange = sampleRate == null || sampleRate <= 0
        ? 'for example, the final $windowSamples samples of each minute'
        : _exampleWindowRange(sampleRate: sampleRate, windowSamples: windowSamples);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'For each full minute of data, BrainStory grabs the last $windowSamples samples ($exampleRange) from every channel and computes a channel-by-channel correlation matrix.',
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'windowSamples',
          labelText: 'Window size (samples)',
          keyboardType: TextInputType.number,
          parser: (String value, dynamic previous) =>
              int.tryParse(value) ?? previous,
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) {
      dataset.bridgeDetection = null;
      return;
    }

    final int windowSamples =
        math.max(1, (params['windowSamples'] as num?)?.toInt() ?? 1000);
    final BridgeDetectionData result = computeBridgeDetection(
      timeSeries,
      windowSamples: windowSamples,
    );
    dataset.bridgeDetection = result;
    dataset.ram['bridgeDetector.params'] = <String, dynamic>{
      'windowSamples': windowSamples,
    };
  }
}

BridgeDetectionData computeBridgeDetection(
  TimeSeriesData timeSeries, {
  required int windowSamples,
}) {
  final List<List<double>> channels = timeSeries.channels;
  if (channels.isEmpty || timeSeries.sampleRate <= 0 || windowSamples <= 0) {
    return BridgeDetectionData(
      channelLabels: timeSeries.channelLabels,
      windowSampleCount: windowSamples,
      sampleRate: timeSeries.sampleRate,
      frames: const <BridgeCorrelationFrameData>[],
      source: timeSeries.source,
    );
  }

  final int samplesPerMinute = (timeSeries.sampleRate * 60.0).round();
  if (samplesPerMinute <= 0) {
    return BridgeDetectionData(
      channelLabels: timeSeries.channelLabels,
      windowSampleCount: windowSamples,
      sampleRate: timeSeries.sampleRate,
      frames: const <BridgeCorrelationFrameData>[],
      source: timeSeries.source,
    );
  }

  final int fullMinutes = channels.first.length ~/ samplesPerMinute;
  final int usableWindowSamples = math.min(windowSamples, samplesPerMinute);
  final List<BridgeCorrelationFrameData> frames = <BridgeCorrelationFrameData>[];

  for (int minuteIndex = 0; minuteIndex < fullMinutes; minuteIndex++) {
    final int minuteEnd = (minuteIndex + 1) * samplesPerMinute;
    final int startSample = minuteEnd - usableWindowSamples;
    final List<List<double>> windowedChannels = channels
        .map(
          (List<double> channel) => channel.sublist(startSample, minuteEnd),
        )
        .toList(growable: false);
    frames.add(
      BridgeCorrelationFrameData(
        minuteIndex: minuteIndex + 1,
        startSample: startSample,
        endSampleExclusive: minuteEnd,
        correlationMatrix: _correlationMatrix(windowedChannels),
      ),
    );
  }

  final List<String> channelLabels = timeSeries.channelLabels.isEmpty
      ? List<String>.generate(
          channels.length,
          (int index) => 'Ch ${index + 1}',
          growable: false,
        )
      : timeSeries.channelLabels;

  return BridgeDetectionData(
    channelLabels: channelLabels,
    windowSampleCount: usableWindowSamples,
    sampleRate: timeSeries.sampleRate,
    frames: frames,
    source: timeSeries.source,
  );
}

List<List<double>> _correlationMatrix(List<List<double>> channels) {
  final int channelCount = channels.length;
  final List<List<double>> matrix = List<List<double>>.generate(
    channelCount,
    (_) => List<double>.filled(channelCount, 0.0),
    growable: false,
  );

  for (int i = 0; i < channelCount; i++) {
    for (int j = i; j < channelCount; j++) {
      final double correlation = _pearsonCorrelation(channels[i], channels[j]);
      matrix[i][j] = correlation;
      matrix[j][i] = correlation;
    }
  }

  return matrix;
}

double _pearsonCorrelation(List<double> a, List<double> b) {
  final int count = math.min(a.length, b.length);
  if (count == 0) {
    return 0.0;
  }
  double sumA = 0.0;
  double sumB = 0.0;
  for (int index = 0; index < count; index++) {
    sumA += a[index];
    sumB += b[index];
  }
  final double meanA = sumA / count;
  final double meanB = sumB / count;

  double numerator = 0.0;
  double denominatorA = 0.0;
  double denominatorB = 0.0;
  for (int index = 0; index < count; index++) {
    final double deltaA = a[index] - meanA;
    final double deltaB = b[index] - meanB;
    numerator += deltaA * deltaB;
    denominatorA += deltaA * deltaA;
    denominatorB += deltaB * deltaB;
  }

  if (denominatorA == 0.0 || denominatorB == 0.0) {
    return 0.0;
  }
  return numerator / math.sqrt(denominatorA * denominatorB);
}

String _exampleWindowRange({
  required double sampleRate,
  required int windowSamples,
}) {
  final double seconds = windowSamples / sampleRate;
  final double startSeconds = math.max(0.0, 60.0 - seconds);
  final int startMinute = (startSeconds ~/ 60).toInt();
  final int startSecondWhole = (startSeconds % 60).floor();
  final int endMinute = 1;
  return '${startMinute.toString().padLeft(2, '0')}:${startSecondWhole.toString().padLeft(2, '0')} - ${endMinute.toString().padLeft(2, '0')}:00 of each minute';
}
