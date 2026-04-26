import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class BandpassNodeType extends NodeType {
  @override
  String get title => 'Bandpass Filter';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Frequency Domain';

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
  bool get supportsBackgroundRun => true;

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.primaryChannel.isEmpty) {
      return;
    }
    final List<List<double>> channels = timeSeries.channels;
    final double sampleRate = timeSeries.sampleRate;

    final double low = (params['low'] as num?)?.toDouble() ?? 1.0;
    final double high = (params['high'] as num?)?.toDouble() ?? 40.0;
    final double steepness = (params['steepness'] as num?)?.toDouble() ?? 0.8;
    final double? notch = (params['notch'] as num?)?.toDouble();

    dataset.ram.putIfAbsent(
      'signal.originalSamples',
      () => channels.map((List<double> channel) => List<double>.from(channel)).toList(),
    );
    dataset.timeSeries = TimeSeriesData(
      channelSamples: channels
          .map(
            (List<double> samples) => applyBandpassFilter(
              samples,
              sampleRate: sampleRate,
              lowCutHz: low,
              highCutHz: high,
              steepness: steepness,
              notchHz: notch,
            ),
          )
          .toList(growable: false),
      sampleRate: sampleRate,
      channelLabels: timeSeries.channelLabels,
      channelCoordinates: timeSeries.channelCoordinates,
      markers: timeSeries.markers,
      factors: timeSeries.factors,
      source: timeSeries.source,
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
        _BandpassNumberField(
          key: const ValueKey<String>('bandpass-low'),
          label: 'Low Cut (Hz)',
          value: params['low']?.toString() ?? '1.0',
          onChanged: (String value) {
            params['low'] = double.tryParse(value) ?? params['low'];
          },
        ),
        _BandpassNumberField(
          key: const ValueKey<String>('bandpass-high'),
          label: 'High Cut (Hz)',
          value: params['high']?.toString() ?? '40.0',
          onChanged: (String value) {
            params['high'] = double.tryParse(value) ?? params['high'];
          },
        ),
        _BandpassNumberField(
          key: const ValueKey<String>('bandpass-steepness'),
          label: 'Steepness',
          value: params['steepness']?.toString() ?? '0.8',
          onChanged: (String value) {
            params['steepness'] = double.tryParse(value) ?? params['steepness'];
          },
        ),
        _BandpassNumberField(
          key: const ValueKey<String>('bandpass-notch'),
          label: 'Notch (Hz, optional)',
          value: params['notch']?.toString() ?? '',
          onChanged: (String value) {
            params['notch'] = value.isEmpty ? null : double.tryParse(value);
          },
        ),
      ],
    );
  }
}

class _BandpassNumberField extends StatefulWidget {
  const _BandpassNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BandpassNumberField> createState() => _BandpassNumberFieldState();
}

class _BandpassNumberFieldState extends State<_BandpassNumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _BandpassNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(labelText: widget.label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: widget.onChanged,
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
  final double q = math.sqrt(0.5);
  final int stageCount = 1 + (normalizedSteepness * 3.0).round();
  List<double> output = List<double>.from(input);

  if (lowCutHz > 0 && lowCutHz < nyquist) {
    final _Biquad biquad = _Biquad.highPass(
      sampleRate: sampleRate,
      cutoffHz: lowCutHz,
      q: q,
    );
    for (int stage = 0; stage < stageCount; stage++) {
      output = _runZeroPhaseBiquad(
        output,
        biquad,
        edgeHz: lowCutHz,
        sampleRate: sampleRate,
      );
    }
  }

  if (highCutHz > 0 && highCutHz < nyquist) {
    final _Biquad biquad = _Biquad.lowPass(
      sampleRate: sampleRate,
      cutoffHz: highCutHz,
      q: q,
    );
    for (int stage = 0; stage < stageCount; stage++) {
      output = _runZeroPhaseBiquad(
        output,
        biquad,
        edgeHz: highCutHz,
        sampleRate: sampleRate,
      );
    }
  }

  if (notchHz != null && notchHz > 0 && notchHz < nyquist) {
    output = _runZeroPhaseBiquad(
      output,
      _Biquad.notch(
        sampleRate: sampleRate,
        centerHz: notchHz,
        q: 20.0,
      ),
      edgeHz: notchHz,
      sampleRate: sampleRate,
    );
  }

  return output;
}

List<double> _runZeroPhaseBiquad(
  List<double> input,
  _Biquad biquad, {
  required double edgeHz,
  required double sampleRate,
}) {
  final List<double> padded = _reflectPad(
    input,
    _edgePaddingLength(
      length: input.length,
      edgeHz: edgeHz,
      sampleRate: sampleRate,
    ),
  );
  final List<double> forward = _runBiquad(padded, biquad);
  final List<double> backward = _runBiquad(
    forward.reversed.toList(growable: false),
    biquad,
  ).reversed.toList(growable: false);
  final int trim = (backward.length - input.length) ~/ 2;
  return backward.sublist(trim, trim + input.length);
}

List<double> _runBiquad(List<double> input, _Biquad biquad) {
  final List<double> output = <double>[];
  double x1 = input.isEmpty ? 0.0 : input.first;
  double x2 = x1;
  double y1 = x1;
  double y2 = x1;

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

int _edgePaddingLength({
  required int length,
  required double edgeHz,
  required double sampleRate,
}) {
  if (length <= 2) {
    return 0;
  }
  final double safeEdgeHz = edgeHz <= 0 ? sampleRate / 8.0 : edgeHz;
  final int requested = math.max(
    24,
    (sampleRate * (3.0 / safeEdgeHz)).round(),
  );
  return requested.clamp(0, math.max(0, length - 1));
}

List<double> _reflectPad(List<double> input, int padLength) {
  if (padLength <= 0 || input.length < 2) {
    return List<double>.from(input, growable: false);
  }
  final List<double> padded = <double>[];
  for (int index = padLength; index >= 1; index--) {
    padded.add(input[index.clamp(0, input.length - 1)]);
  }
  padded.addAll(input);
  for (int index = input.length - 2; index >= input.length - 1 - padLength; index--) {
    padded.add(input[index.clamp(0, input.length - 1)]);
  }
  return padded;
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
