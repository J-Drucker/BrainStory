import 'dart:math' as math;

import 'brainstory_engine_model.dart';
import 'brainstory_engine_stub.dart'
    if (dart.library.io) 'brainstory_engine_io.dart'
    as impl;

export 'brainstory_engine_model.dart';

AggregateSeriesStats? computeAggregateSeriesStats(List<List<double>> traces) {
  return impl.computeAggregateSeriesStats(traces);
}

String? readAntCntPayloadNative(String path) {
  return impl.readAntCntPayloadNative(path);
}

List<double>? applyBandpassFilterNative(
  List<double> input, {
  required double sampleRate,
  required double lowCutHz,
  required double highCutHz,
  required double steepness,
  double? notchHz,
}) {
  return impl.applyBandpassFilterNative(
    input,
    sampleRate: sampleRate,
    lowCutHz: lowCutHz,
    highCutHz: highCutHz,
    steepness: steepness,
    notchHz: notchHz,
  );
}

NativeSpectrumResult? computeSingleSidedSpectrumNative(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
}) {
  return impl.computeSingleSidedSpectrumNative(
    samples,
    sampleRate: sampleRate,
    lowHz: lowHz,
    highHz: highHz,
  );
}

AggregateSeriesStats? computeAggregateSeriesStatsWithFallback(
  List<List<double>> traces,
) {
  return computeAggregateSeriesStats(traces) ??
      computeAggregateSeriesStatsPure(traces);
}

AggregateSeriesStats? computeAggregateSeriesStatsPure(
  List<List<double>> traces,
) {
  if (traces.isEmpty) {
    return null;
  }
  final int sampleCount = traces.first.length;
  if (sampleCount == 0 ||
      traces.any((List<double> trace) => trace.length != sampleCount)) {
    return null;
  }

  final List<double> mean = List<double>.filled(
    sampleCount,
    0.0,
    growable: false,
  );
  final List<double> standardDeviation = List<double>.filled(
    sampleCount,
    0.0,
    growable: false,
  );

  for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    double sum = 0.0;
    for (final List<double> trace in traces) {
      sum += trace[sampleIndex];
    }
    final double meanValue = sum / traces.length;
    mean[sampleIndex] = meanValue;

    double variance = 0.0;
    for (final List<double> trace in traces) {
      final double delta = trace[sampleIndex] - meanValue;
      variance += delta * delta;
    }
    variance /= traces.length;
    standardDeviation[sampleIndex] = math.sqrt(variance);
  }

  return AggregateSeriesStats(mean: mean, standardDeviation: standardDeviation);
}
