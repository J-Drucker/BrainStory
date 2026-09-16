import 'dart:math' as math;

import 'brainstory_engine_model.dart';
import 'engine_background.dart';
import 'brainstory_engine_stub.dart'
    if (dart.library.io) 'brainstory_engine_io.dart'
    if (dart.library.js_interop) 'brainstory_engine_web.dart'
    as impl;

export 'brainstory_engine_model.dart';

Future<List<double>?> filterBackground(
  List<double> samples, {
  required double sampleRate,
  required double lowCutHz,
  required double highCutHz,
  required double steepness,
  double? notchHz,
}) async {
  final dynamic result = await executeBrowserEngine(<String, dynamic>{
    'operation': 'filter',
    'samples': samples,
    'rate': sampleRate,
    'low': lowCutHz,
    'high': highCutHz,
    'steepness': steepness,
    'notch': notchHz,
  });
  return result == null
      ? null
      : (result as List).map((dynamic v) => (v as num).toDouble()).toList();
}

Future<List<List<double>>?> applyIcaBackground(
  List<List<double>> channels, {
  required List<List<double>> unmixingMatrix,
  required List<double> channelMeans,
}) async {
  final dynamic result = await executeBrowserEngine(<String, dynamic>{
    'operation': 'applyIca',
    'channels': channels,
    'matrix': unmixingMatrix,
    'means': channelMeans,
  });
  if (result == null) {
    return applyIcaNative(
      channels,
      unmixingMatrix: unmixingMatrix,
      channelMeans: channelMeans,
    );
  }
  if (result is List<List<double>>) {
    return result;
  }
  return (result as List)
      .map(
        (dynamic row) =>
            (row as List).map((dynamic v) => (v as num).toDouble()).toList(),
      )
      .toList();
}

Future<NativeIcaResult?> computeIcaBackground(
  List<List<double>> channels, {
  required int componentCount,
  required double tolerance,
  required int maxIterations,
  required int seed,
}) async {
  final dynamic result = await executeBrowserEngine(<String, dynamic>{
    'operation': 'ica',
    'channels': channels,
    'components': componentCount,
    'tolerance': tolerance,
    'iterations': maxIterations,
    'seed': seed,
  });
  if (result is NativeIcaResult) {
    return result;
  }
  if (result != null) {
    return NativeIcaResult.fromJson(result as Map<String, dynamic>);
  }
  return computeIcaNative(
    channels,
    componentCount: componentCount,
    tolerance: tolerance,
    maxIterations: maxIterations,
    seed: seed,
  );
}

Future<NativeWaveletResult?> computeWaveletBackground(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
  required int frequencyCount,
  required int timeCount,
  required double cycles,
}) async {
  final dynamic result = await executeBrowserEngine(<String, dynamic>{
    'operation': 'wavelet',
    'samples': samples,
    'rate': sampleRate,
    'low': lowHz,
    'high': highHz,
    'frequencies': frequencyCount,
    'times': timeCount,
    'cycles': cycles,
  });
  if (result is NativeWaveletResult) return result;
  if (result != null) {
    return NativeWaveletResult.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }
  return computeWaveletNative(
    samples,
    sampleRate: sampleRate,
    lowHz: lowHz,
    highHz: highHz,
    frequencyCount: frequencyCount,
    timeCount: timeCount,
    cycles: cycles,
  );
}

NativeWaveletResult? computeWaveletNative(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
  required int frequencyCount,
  required int timeCount,
  required double cycles,
}) => impl.computeWaveletNative(
  samples,
  sampleRate: sampleRate,
  lowHz: lowHz,
  highHz: highHz,
  frequencyCount: frequencyCount,
  timeCount: timeCount,
  cycles: cycles,
);

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

NativeIcaResult? computeIcaNative(
  List<List<double>> channels, {
  required int componentCount,
  required double tolerance,
  required int maxIterations,
  required int seed,
}) {
  return impl.computeIcaNative(
    channels,
    componentCount: componentCount,
    tolerance: tolerance,
    maxIterations: maxIterations,
    seed: seed,
  );
}

List<List<double>>? applyIcaNative(
  List<List<double>> channels, {
  required List<List<double>> unmixingMatrix,
  required List<double> channelMeans,
}) {
  return impl.applyIcaNative(
    channels,
    unmixingMatrix: unmixingMatrix,
    channelMeans: channelMeans,
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
