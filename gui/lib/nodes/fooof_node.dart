import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class FooofNodeType extends NodeType {
  @override
  String get title => 'FOOOF';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Frequency Domain';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'fLow': 1.0,
        'fHigh': 40.0,
        'maxPeaks': 4,
        'minPeakAmplitude': 0.05,
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'psd', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'metadata', type: PortType.metadata),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('fLow', () => 1.0);
    params.putIfAbsent('fHigh', () => 40.0);
    params.putIfAbsent('maxPeaks', () => 4);
    params.putIfAbsent('minPeakAmplitude', () => 0.05);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Fits an aperiodic 1/f component to PSD output and extracts oscillatory peaks.',
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: NodeParamTextField(
                params: params,
                paramKey: 'fLow',
                labelText: 'Lowest frequency (Hz)',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                parser: (String value, dynamic previous) =>
                    double.tryParse(value) ?? previous,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodeParamTextField(
                params: params,
                paramKey: 'fHigh',
                labelText: 'Highest frequency (Hz)',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                parser: (String value, dynamic previous) =>
                    double.tryParse(value) ?? previous,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: NodeParamTextField(
                params: params,
                paramKey: 'maxPeaks',
                labelText: 'Max peaks',
                keyboardType: TextInputType.number,
                parser: (String value, dynamic previous) =>
                    int.tryParse(value) ?? previous,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodeParamTextField(
                params: params,
                paramKey: 'minPeakAmplitude',
                labelText: 'Min peak amplitude',
                helperText: 'Residual log-power above the aperiodic fit',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                parser: (String value, dynamic previous) =>
                    double.tryParse(value) ?? previous,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final FrequencySpectrumData? spectrum = dataset.spectrum;
    if (spectrum == null ||
        spectrum.frequencies.isEmpty ||
        spectrum.power.isEmpty) {
      dataset.fooofResult = null;
      return;
    }

    final double fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
    final double fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
    final int maxPeaks = ((params['maxPeaks'] as num?)?.toInt() ?? 4).clamp(1, 24);
    final double minPeakAmplitude =
        (params['minPeakAmplitude'] as num?)?.toDouble() ?? 0.05;

    final FooofResultData result = fitFooofModel(
      frequencies: spectrum.frequencies,
      power: spectrum.power,
      fLow: fLow,
      fHigh: fHigh,
      maxPeaks: maxPeaks,
      minPeakAmplitude: minPeakAmplitude,
      source: spectrum.source,
    );
    dataset.fooofResult = result;
    dataset.ram['fooof.params'] = <String, dynamic>{
      'fLow': fLow,
      'fHigh': fHigh,
      'maxPeaks': maxPeaks,
      'minPeakAmplitude': minPeakAmplitude,
    };
  }
}

FooofResultData fitFooofModel({
  required List<double> frequencies,
  required List<double> power,
  required double fLow,
  required double fHigh,
  required int maxPeaks,
  required double minPeakAmplitude,
  String source = '',
}) {
  final int count = math.min(frequencies.length, power.length);
  final List<double> fitFreqs = <double>[];
  final List<double> logFreqs = <double>[];
  final List<double> logPower = <double>[];

  for (int index = 0; index < count; index++) {
    final double frequency = frequencies[index];
    final double powerValue = power[index];
    if (frequency < fLow || frequency > fHigh || frequency <= 0 || powerValue <= 0) {
      continue;
    }
    fitFreqs.add(frequency);
    logFreqs.add(math.log(frequency) / math.ln10);
    logPower.add(math.log(powerValue) / math.ln10);
  }

  if (fitFreqs.length < 3) {
    return const FooofResultData(
      intercept: 0.0,
      exponent: 0.0,
      peaks: <FooofPeakData>[],
    );
  }

  final _LinearFit fit = _fitLine(logFreqs, logPower);
  final List<double> aperiodicFit = List<double>.generate(
    fitFreqs.length,
    (int index) => fit.intercept + (fit.slope * logFreqs[index]),
    growable: false,
  );
  final List<double> residual = List<double>.generate(
    fitFreqs.length,
    (int index) => logPower[index] - aperiodicFit[index],
    growable: false,
  );

  final List<FooofPeakData> peaks = _extractFooofPeaks(
    frequencies: fitFreqs,
    residual: residual,
    maxPeaks: maxPeaks,
    minPeakAmplitude: minPeakAmplitude,
  );

  return FooofResultData(
    intercept: fit.intercept,
    exponent: -fit.slope,
    peaks: peaks,
    fitFrequencies: fitFreqs,
    aperiodicFit: aperiodicFit,
    residual: residual,
    source: source,
  );
}

class _LinearFit {
  const _LinearFit({
    required this.slope,
    required this.intercept,
  });

  final double slope;
  final double intercept;
}

_LinearFit _fitLine(List<double> x, List<double> y) {
  final int n = math.min(x.length, y.length);
  if (n == 0) {
    return const _LinearFit(slope: 0.0, intercept: 0.0);
  }

  final double meanX = x.take(n).reduce((double a, double b) => a + b) / n;
  final double meanY = y.take(n).reduce((double a, double b) => a + b) / n;
  double numerator = 0.0;
  double denominator = 0.0;
  for (int i = 0; i < n; i++) {
    final double xDelta = x[i] - meanX;
    numerator += xDelta * (y[i] - meanY);
    denominator += xDelta * xDelta;
  }
  final double slope = denominator == 0 ? 0.0 : numerator / denominator;
  final double intercept = meanY - (slope * meanX);
  return _LinearFit(slope: slope, intercept: intercept);
}

List<FooofPeakData> _extractFooofPeaks({
  required List<double> frequencies,
  required List<double> residual,
  required int maxPeaks,
  required double minPeakAmplitude,
}) {
  final List<FooofPeakData> peaks = <FooofPeakData>[];
  for (int index = 1; index < residual.length - 1; index++) {
    final double current = residual[index];
    if (current < minPeakAmplitude) {
      continue;
    }
    if (current < residual[index - 1] || current < residual[index + 1]) {
      continue;
    }

    int left = index;
    while (left > 0 && residual[left - 1] > current / 2.0) {
      left--;
    }
    int right = index;
    while (right < residual.length - 1 && residual[right + 1] > current / 2.0) {
      right++;
    }
    final double bandwidth = frequencies[right] - frequencies[left];
    peaks.add(
      FooofPeakData(
        centerFrequencyHz: frequencies[index],
        amplitude: current,
        bandwidthHz: bandwidth <= 0 ? 0.0 : bandwidth,
      ),
    );
  }

  peaks.sort((FooofPeakData a, FooofPeakData b) {
    final int amplitudeOrder = b.amplitude.compareTo(a.amplitude);
    if (amplitudeOrder != 0) {
      return amplitudeOrder;
    }
    return a.centerFrequencyHz.compareTo(b.centerFrequencyHz);
  });
  final List<FooofPeakData> limited =
      peaks.take(maxPeaks).toList(growable: false)
        ..sort((FooofPeakData a, FooofPeakData b) {
          return a.centerFrequencyHz.compareTo(b.centerFrequencyHz);
        });
  return limited;
}
