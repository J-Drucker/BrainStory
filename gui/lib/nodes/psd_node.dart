import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class PSDNodeType extends NodeType {
  @override
  String get title => 'PSD';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Frequency Domain';

  @override
  Map<String, dynamic> get defaultParams => {
    'fLow': 1.0,
    'fHigh': 40.0,
    'outputMode': 'averaged', // 'segments' or 'averaged'
  };

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const [
    PortSpec(name: 'psd', type: PortType.signal),
  ];

  @override
  bool get supportsBackgroundRun => true;

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    params.putIfAbsent('fLow', () => 1.0);
    params.putIfAbsent('fHigh', () => 40.0);
    params.putIfAbsent('outputMode', () => 'averaged');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Frequency range (Hz)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: NodeParamTextField(
                params: params,
                paramKey: 'fLow',
                labelText: 'Lowest',
                keyboardType: TextInputType.number,
                parser: (String value, dynamic previous) =>
                    double.tryParse(value) ?? previous,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodeParamTextField(
                params: params,
                paramKey: 'fHigh',
                labelText: 'Highest',
                keyboardType: TextInputType.number,
                parser: (String value, dynamic previous) =>
                    double.tryParse(value) ?? previous,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Output', style: TextStyle(fontWeight: FontWeight.bold)),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'outputMode',
          labelText: 'Mode',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'segments',
              label: 'As segments',
            ),
            NodeDropdownOption<String>(
              value: 'averaged',
              label: 'Averaged',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      // No signal loaded yet
      return;
    }
    final List<double> samples = timeSeries.primaryChannel;
    if (samples.isEmpty) {
      dataset.spectrum = null;
      return;
    }
    final double fs = timeSeries.sampleRate;

    final fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
    final fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
    final mode = (params['outputMode'] ?? 'averaged').toString();
    final SpectrumResult spectrum = computeSpectrum(
      samples,
      sampleRate: fs,
      fLow: fLow,
      fHigh: fHigh,
      averageSegments: mode != 'segments',
    );

    dataset.spectrum = FrequencySpectrumData(
      frequencies: spectrum.freqs,
      power: spectrum.power,
      segmentCount: spectrum.segmentCount,
      source: timeSeries.source,
    );
  }
}

class SpectrumResult {
  const SpectrumResult({
    required this.freqs,
    required this.power,
    required this.segmentCount,
  });

  final List<double> freqs;
  final List<double> power;
  final int segmentCount;
}

SpectrumResult computeSpectrum(
  List<double> samples, {
  required double sampleRate,
  required double fLow,
  required double fHigh,
  required bool averageSegments,
}) {
  if (samples.isEmpty) {
    return const SpectrumResult(freqs: <double>[], power: <double>[], segmentCount: 0);
  }

  final int segmentLength = _largestPowerOfTwo(
    math.max(32, math.min(samples.length, 256)),
  );
  final int hopLength = math.max(1, segmentLength ~/ 2);

  final List<List<double>> spectra = <List<double>>[];
  final List<double> freqs = <double>[];

  for (int start = 0; start + segmentLength <= samples.length; start += hopLength) {
    final List<double> windowed = _hannWindow(
      samples.sublist(start, start + segmentLength),
    );
    final SpectrumResult segmentSpectrum = _singleSidedSpectrum(
      windowed,
      sampleRate: sampleRate,
      fLow: fLow,
      fHigh: fHigh,
    );

    if (freqs.isEmpty) {
      freqs.addAll(segmentSpectrum.freqs);
    }
    spectra.add(segmentSpectrum.power);

    if (!averageSegments) {
      break;
    }
  }

  if (spectra.isEmpty) {
    final List<double> padded = List<double>.filled(segmentLength, 0.0);
    for (int i = 0; i < samples.length && i < segmentLength; i++) {
      padded[i] = samples[i];
    }
    final SpectrumResult single = _singleSidedSpectrum(
      _hannWindow(padded),
      sampleRate: sampleRate,
      fLow: fLow,
      fHigh: fHigh,
    );
    return SpectrumResult(
      freqs: single.freqs,
      power: single.power,
      segmentCount: 1,
    );
  }

  if (!averageSegments) {
    return SpectrumResult(
      freqs: freqs,
      power: spectra.first,
      segmentCount: 1,
    );
  }

  final List<double> averagedPower = List<double>.filled(freqs.length, 0.0);
  for (final List<double> spectrum in spectra) {
    for (int i = 0; i < averagedPower.length; i++) {
      averagedPower[i] += spectrum[i];
    }
  }
  for (int i = 0; i < averagedPower.length; i++) {
    averagedPower[i] /= spectra.length;
  }

  return SpectrumResult(
    freqs: freqs,
    power: averagedPower,
    segmentCount: spectra.length,
  );
}

SpectrumResult _singleSidedSpectrum(
  List<double> samples, {
  required double sampleRate,
  required double fLow,
  required double fHigh,
}) {
  final int n = samples.length;
  final List<double> freqs = <double>[];
  final List<double> power = <double>[];

  for (int k = 0; k <= n ~/ 2; k++) {
    final double frequency = (k * sampleRate) / n;
    if (frequency < fLow || frequency > fHigh) {
      continue;
    }

    double real = 0.0;
    double imag = 0.0;
    for (int t = 0; t < n; t++) {
      final double angle = 2 * math.pi * k * t / n;
      real += samples[t] * math.cos(angle);
      imag -= samples[t] * math.sin(angle);
    }

    freqs.add(frequency);
    power.add((real * real + imag * imag) / n);
  }

  return SpectrumResult(
    freqs: freqs,
    power: power,
    segmentCount: 1,
  );
}

List<double> _hannWindow(List<double> samples) {
  if (samples.length <= 1) {
    return List<double>.from(samples);
  }

  return List<double>.generate(samples.length, (int i) {
    final double weight =
        0.5 - (0.5 * math.cos((2 * math.pi * i) / (samples.length - 1)));
    return samples[i] * weight;
  });
}

int _largestPowerOfTwo(int value) {
  int power = 1;
  while (power * 2 <= value) {
    power *= 2;
  }
  return power;
}
