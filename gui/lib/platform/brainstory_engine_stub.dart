import 'brainstory_engine_model.dart';

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
}) => null;

NativeSpectrumResult? computeSingleSidedSpectrumNative(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
}) => null;

NativeIcaResult? computeIcaNative(
  List<List<double>> channels, {
  required int componentCount,
  required double tolerance,
  required int maxIterations,
  required int seed,
}) => null;

List<List<double>>? applyIcaNative(
  List<List<double>> channels, {
  required List<List<double>> unmixingMatrix,
  required List<double> channelMeans,
}) => null;

NativeWaveletResult? computeWaveletNative(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
  required int frequencyCount,
  required int timeCount,
  required double cycles,
}) => null;

NativeGaussianMixtureResult? computeGaussianMixtureNative(
  List<List<double>> rows, {
  required int componentCount,
  required double tolerance,
  required int maxIterations,
  required double regularization,
  required bool standardize,
  required int seed,
}) => null;
