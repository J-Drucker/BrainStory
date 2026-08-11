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
