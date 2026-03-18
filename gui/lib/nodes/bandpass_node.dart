import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class BandpassNodeType extends NodeType {
  @override
  String get title => 'Bandpass Filter';

  @override
  Map<String, dynamic> get defaultParams => {
    'low': 1.0,
    'high': 40.0,
    'steepness': 0.8,
    'notch': null,
  };

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final List<double>? samples = dataset.ram['signal.samples'] as List<double>?;
    final double? sampleRate = dataset.ram['signal.fs'] as double?;
    if (samples == null || samples.isEmpty || sampleRate == null) {
      return;
    }

    final double low = (params['low'] as num?)?.toDouble() ?? 1.0;
    final double high = (params['high'] as num?)?.toDouble() ?? 40.0;
    final double steepness = (params['steepness'] as num?)?.toDouble() ?? 0.8;
    final double? notch = (params['notch'] as num?)?.toDouble();

    dataset.ram.putIfAbsent(
      'signal.originalSamples',
      () => List<double>.from(samples),
    );
    dataset.ram['signal.samples'] = applyBandpassFilter(
      samples,
      sampleRate: sampleRate,
      lowCutHz: low,
      highCutHz: high,
      steepness: steepness,
      notchHz: notch,
    );
    dataset.ram['bandpass.params'] = <String, dynamic>{
      'low': low,
      'high': high,
      'steepness': steepness,
      'notch': notch,
    };
  }

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    params.putIfAbsent('low', () => 1.0);
    params.putIfAbsent('high', () => 40.0);
    params.putIfAbsent('steepness', () => 0.8);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          initialValue: params['low']?.toString() ?? '1.0',
          decoration: const InputDecoration(labelText: 'Low Cut (Hz)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (String value) {
            setState(() {
              params['low'] = double.tryParse(value) ?? params['low'];
            });
          },
        ),
        TextFormField(
          initialValue: params['high']?.toString() ?? '40.0',
          decoration: const InputDecoration(labelText: 'High Cut (Hz)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (String value) {
            setState(() {
              params['high'] = double.tryParse(value) ?? params['high'];
            });
          },
        ),
        TextFormField(
          initialValue: params['steepness']?.toString() ?? '0.8',
          decoration: const InputDecoration(labelText: 'Steepness'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (String value) {
            setState(() {
              params['steepness'] = double.tryParse(value) ?? params['steepness'];
            });
          },
        ),
        TextFormField(
          initialValue: params['notch']?.toString() ?? '',
          decoration: const InputDecoration(labelText: 'Notch (Hz, optional)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (String value) {
            setState(() {
              params['notch'] = value.isEmpty ? null : double.tryParse(value);
            });
          },
        ),
      ],
    );
  }
}

List<double> applyBandpassFilter(
  List<double> input, {
  required double sampleRate,
  required double lowCutHz,
  required double highCutHz,
  required double steepness,
  double? notchHz,
}) {
  if (input.isEmpty) {
    return <double>[];
  }

  final double nyquist = sampleRate / 2.0;
  final double normalizedSteepness = steepness.clamp(0.0, 1.0);
  final double q = 0.6 + (normalizedSteepness * 3.4);
  List<double> output = List<double>.from(input);

  if (lowCutHz > 0 && lowCutHz < nyquist) {
    output = _runBiquad(
      output,
      _Biquad.highPass(
        sampleRate: sampleRate,
        cutoffHz: lowCutHz,
        q: q,
      ),
    );
  }

  if (highCutHz > 0 && highCutHz < nyquist) {
    output = _runBiquad(
      output,
      _Biquad.lowPass(
        sampleRate: sampleRate,
        cutoffHz: highCutHz,
        q: q,
      ),
    );
  }

  if (notchHz != null && notchHz > 0 && notchHz < nyquist) {
    output = _runBiquad(
      output,
      _Biquad.notch(
        sampleRate: sampleRate,
        centerHz: notchHz,
        q: math.max(1.0, q),
      ),
    );
  }

  return output;
}

List<double> _runBiquad(List<double> input, _Biquad biquad) {
  final List<double> output = <double>[];
  double x1 = 0.0;
  double x2 = 0.0;
  double y1 = 0.0;
  double y2 = 0.0;

  for (final double x0 in input) {
    final double y0 = (biquad.b0 * x0) +
        (biquad.b1 * x1) +
        (biquad.b2 * x2) -
        (biquad.a1 * y1) -
        (biquad.a2 * y2);
    output.add(y0);
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
  }

  return output;
}

class _Biquad {
  const _Biquad({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  factory _Biquad.lowPass({
    required double sampleRate,
    required double cutoffHz,
    required double q,
  }) {
    return _Biquad._fromCookbook(
      sampleRate: sampleRate,
      cutoffHz: cutoffHz,
      q: q,
      mode: _BiquadMode.lowPass,
    );
  }

  factory _Biquad.highPass({
    required double sampleRate,
    required double cutoffHz,
    required double q,
  }) {
    return _Biquad._fromCookbook(
      sampleRate: sampleRate,
      cutoffHz: cutoffHz,
      q: q,
      mode: _BiquadMode.highPass,
    );
  }

  factory _Biquad.notch({
    required double sampleRate,
    required double centerHz,
    required double q,
  }) {
    return _Biquad._fromCookbook(
      sampleRate: sampleRate,
      cutoffHz: centerHz,
      q: q,
      mode: _BiquadMode.notch,
    );
  }

  factory _Biquad._fromCookbook({
    required double sampleRate,
    required double cutoffHz,
    required double q,
    required _BiquadMode mode,
  }) {
    final double omega = 2 * math.pi * cutoffHz / sampleRate;
    final double sinOmega = math.sin(omega);
    final double cosOmega = math.cos(omega);
    final double alpha = sinOmega / (2 * q);

    late final double b0;
    late final double b1;
    late final double b2;

    switch (mode) {
      case _BiquadMode.lowPass:
        b0 = (1 - cosOmega) / 2;
        b1 = 1 - cosOmega;
        b2 = (1 - cosOmega) / 2;
        break;
      case _BiquadMode.highPass:
        b0 = (1 + cosOmega) / 2;
        b1 = -(1 + cosOmega);
        b2 = (1 + cosOmega) / 2;
        break;
      case _BiquadMode.notch:
        b0 = 1;
        b1 = -2 * cosOmega;
        b2 = 1;
        break;
    }

    final double a0 = 1 + alpha;
    final double a1 = -2 * cosOmega;
    final double a2 = 1 - alpha;

    return _Biquad(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }
}

enum _BiquadMode {
  lowPass,
  highPass,
  notch,
}
