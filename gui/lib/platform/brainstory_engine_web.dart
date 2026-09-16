import 'dart:convert';
import 'dart:js_interop';

import 'brainstory_engine_model.dart';

@JS('brainstoryEngine')
external JSString _run(JSString request);

dynamic _execute(Map<String, dynamic> request) {
  final Map<String, dynamic> response =
      jsonDecode(_run(jsonEncode(request).toJS).toDart) as Map<String, dynamic>;
  if (response.containsKey('error')) {
    throw StateError(response['error'].toString());
  }
  return response['result'];
}

List<double> _vector(dynamic values) =>
    (values as List).map((dynamic value) => (value as num).toDouble()).toList();

AggregateSeriesStats? computeAggregateSeriesStats(List<List<double>> traces) =>
    null;
String? readAntCntPayloadNative(String path) => null;

List<double>? applyBandpassFilterNative(
  List<double> input, {
  required double sampleRate,
  required double lowCutHz,
  required double highCutHz,
  required double steepness,
  double? notchHz,
}) => _vector(
  _execute(<String, dynamic>{
    'operation': 'filter',
    'samples': input,
    'rate': sampleRate,
    'low': lowCutHz,
    'high': highCutHz,
    'steepness': steepness,
    'notch': notchHz,
  }),
);

NativeSpectrumResult? computeSingleSidedSpectrumNative(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
}) {
  final dynamic result = _execute(<String, dynamic>{
    'operation': 'spectrum',
    'samples': samples,
    'rate': sampleRate,
    'low': lowHz,
    'high': highHz,
  });
  return NativeSpectrumResult(
    frequencies: _vector(result['frequencies']),
    power: _vector(result['power']),
  );
}

NativeIcaResult? computeIcaNative(
  List<List<double>> channels, {
  required int componentCount,
  required double tolerance,
  required int maxIterations,
  required int seed,
}) => NativeIcaResult.fromJson(
  _execute(<String, dynamic>{
        'operation': 'ica',
        'channels': channels,
        'components': componentCount,
        'tolerance': tolerance,
        'iterations': maxIterations,
        'seed': seed,
      })
      as Map<String, dynamic>,
);

List<List<double>>? applyIcaNative(
  List<List<double>> channels, {
  required List<List<double>> unmixingMatrix,
  required List<double> channelMeans,
}) =>
    (_execute(<String, dynamic>{
              'operation': 'applyIca',
              'channels': channels,
              'matrix': unmixingMatrix,
              'means': channelMeans,
            })
            as List)
        .map(_vector)
        .toList();

NativeWaveletResult? computeWaveletNative(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
  required int frequencyCount,
  required int timeCount,
  required double cycles,
}) => NativeWaveletResult.fromJson(
  Map<String, dynamic>.from(
    _execute(<String, dynamic>{
          'operation': 'wavelet',
          'samples': samples,
          'rate': sampleRate,
          'low': lowHz,
          'high': highHz,
          'frequencies': frequencyCount,
          'times': timeCount,
          'cycles': cycles,
        })
        as Map,
  ),
);

NativeGaussianMixtureResult? computeGaussianMixtureNative(
  List<List<double>> rows, {
  required int componentCount,
  required double tolerance,
  required int maxIterations,
  required double regularization,
  required bool standardize,
  required int seed,
}) => NativeGaussianMixtureResult.fromJson(
  Map<String, dynamic>.from(
    _execute(<String, dynamic>{
          'operation': 'gaussianMixture',
          'rows': rows,
          'components': componentCount,
          'tolerance': tolerance,
          'iterations': maxIterations,
          'regularization': regularization,
          'standardize': standardize,
          'seed': seed,
        })
        as Map,
  ),
);
