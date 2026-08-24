import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/brainstory_engine.dart';
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
    'steepness': 0.5,
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
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.primaryChannel.isEmpty) {
      return;
    }
    final List<List<double>> channels = timeSeries.channels;
    final double sampleRate = timeSeries.sampleRate;

    final double low = (params['low'] as num?)?.toDouble() ?? 1.0;
    final double high = (params['high'] as num?)?.toDouble() ?? 40.0;
    final double steepness = (params['steepness'] as num?)?.toDouble() ?? 0.5;
    final double? notch = (params['notch'] as num?)?.toDouble();

    dataset.ram.putIfAbsent(
      'signal.originalSamples',
      () => channels
          .map((List<double> channel) => List<double>.from(channel))
          .toList(),
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
      impedanceData: timeSeries.impedanceData,
      markers: timeSeries.markers,
      factors: timeSeries.factors,
      source: timeSeries.source,
    );
    // A filter always operates on the continuous recording. Any inherited
    // segments refer to the pre-filter signal and must be recreated downstream.
    dataset.segmentedTimeSeries = null;
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
    params.putIfAbsent('steepness', () => 0.5);

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
        _BandpassSteepnessField(
          key: const ValueKey<String>('bandpass-steepness'),
          value: (params['steepness'] as num?)?.toDouble() ?? 0.5,
          onChanged: (double value) {
            params['steepness'] = value;
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

class _BandpassSteepnessField extends StatelessWidget {
  const _BandpassSteepnessField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  double get _normalizedValue {
    if (value < 0.25) return 0.15;
    if (value < 0.75) return 0.5;
    if (value < 0.9) return 0.8;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<double>(
      initialValue: _normalizedValue,
      decoration: const InputDecoration(
        labelText: 'Steepness',
        helperText: 'Higher orders have sharper cutoffs.',
      ),
      items: const <DropdownMenuItem<double>>[
        DropdownMenuItem<double>(value: 0.15, child: Text('Gentle (order 2)')),
        DropdownMenuItem<double>(value: 0.5, child: Text('Standard (order 4)')),
        DropdownMenuItem<double>(value: 0.8, child: Text('Steep (order 6)')),
        DropdownMenuItem<double>(
          value: 1.0,
          child: Text('Very steep (order 8)'),
        ),
      ],
      onChanged: (double? value) {
        if (value != null) onChanged(value);
      },
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

  _validateBandpassParams(
    input: input,
    sampleRate: sampleRate,
    lowCutHz: lowCutHz,
    highCutHz: highCutHz,
    steepness: steepness,
    notchHz: notchHz,
  );

  final List<double>? nativeOutput = applyBandpassFilterNative(
    input,
    sampleRate: sampleRate,
    lowCutHz: lowCutHz,
    highCutHz: highCutHz,
    steepness: steepness,
    notchHz: notchHz,
  );
  if (nativeOutput != null) {
    return nativeOutput;
  }

  final int order = _butterworthOrder(steepness);
  final List<_Biquad> sections = <_Biquad>[];
  if (lowCutHz > 0) {
    sections.addAll(
      _butterworthSections(
        sampleRate: sampleRate,
        cutoffHz: lowCutHz,
        order: order,
        highPass: true,
      ),
    );
  }
  if (highCutHz > 0) {
    sections.addAll(
      _butterworthSections(
        sampleRate: sampleRate,
        cutoffHz: highCutHz,
        order: order,
        highPass: false,
      ),
    );
  }
  if (notchHz != null) {
    final double notchQ = math.max(1.0, 0.6 + (steepness * 3.4));
    sections.add(
      _Biquad.notch(sampleRate: sampleRate, centerHz: notchHz, q: notchQ),
    );
  }
  final double slowestFrequency = lowCutHz > 0
      ? lowCutHz
      : highCutHz > 0
      ? highCutHz
      : notchHz ?? (sampleRate / 2);
  final int settlingPad = (10 * sampleRate / slowestFrequency).ceil();
  return _runZeroPhaseFilter(input, sections, settlingPad: settlingPad);
}

void _validateBandpassParams({
  required List<double> input,
  required double sampleRate,
  required double lowCutHz,
  required double highCutHz,
  required double steepness,
  required double? notchHz,
}) {
  final double nyquist = sampleRate / 2.0;
  if (!sampleRate.isFinite || sampleRate <= 0) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be positive.');
  }
  if (input.any((double value) => !value.isFinite)) {
    throw ArgumentError.value(input, 'input', 'Samples must be finite.');
  }
  if (!steepness.isFinite || steepness < 0 || steepness > 1) {
    throw ArgumentError.value(steepness, 'steepness', 'Must be from 0 to 1.');
  }
  if (!lowCutHz.isFinite || lowCutHz < 0 || lowCutHz >= nyquist) {
    throw ArgumentError.value(
      lowCutHz,
      'lowCutHz',
      'Must be zero (disabled) or below Nyquist ($nyquist Hz).',
    );
  }
  if (!highCutHz.isFinite || highCutHz < 0 || highCutHz >= nyquist) {
    throw ArgumentError.value(
      highCutHz,
      'highCutHz',
      'Must be zero (disabled) or below Nyquist ($nyquist Hz).',
    );
  }
  if (lowCutHz > 0 && highCutHz > 0 && lowCutHz >= highCutHz) {
    throw ArgumentError('Low cutoff must be lower than high cutoff.');
  }
  if (notchHz != null &&
      (!notchHz.isFinite || notchHz <= 0 || notchHz >= nyquist)) {
    throw ArgumentError.value(
      notchHz,
      'notchHz',
      'Must be positive and below Nyquist ($nyquist Hz).',
    );
  }
}

int _butterworthOrder(double steepness) {
  if (steepness < 0.25) return 2;
  if (steepness < 0.75) return 4;
  if (steepness < 0.9) return 6;
  return 8;
}

List<_Biquad> _butterworthSections({
  required double sampleRate,
  required double cutoffHz,
  required int order,
  required bool highPass,
}) {
  return List<_Biquad>.generate(order ~/ 2, (int sectionIndex) {
    final int section = (order ~/ 2) - 1 - sectionIndex;
    final double angle = ((2 * section + 1) * math.pi) / (2 * order);
    final double q = 1 / (2 * math.sin(angle));
    return highPass
        ? _Biquad.highPass(sampleRate: sampleRate, cutoffHz: cutoffHz, q: q)
        : _Biquad.lowPass(sampleRate: sampleRate, cutoffHz: cutoffHz, q: q);
  }, growable: false);
}

List<double> _runZeroPhaseFilter(
  List<double> input,
  List<_Biquad> sections, {
  required int settlingPad,
}) {
  if (sections.isEmpty || input.length < 2) return List<double>.from(input);
  final int padLength = math.min(
    math.max(sections.length * 6, settlingPad),
    input.length - 1,
  );
  List<double> output = _oddReflectionPad(input, padLength);
  for (final _Biquad section in sections) {
    output = _runBiquad(output, section);
  }
  output = output.reversed.toList(growable: false);
  for (final _Biquad section in sections) {
    output = _runBiquad(output, section);
  }
  output = output.reversed.toList(growable: false);
  return output.sublist(padLength, padLength + input.length);
}

List<double> _oddReflectionPad(List<double> input, int padLength) {
  final List<double> output = <double>[];
  for (int index = padLength; index >= 1; index--) {
    output.add((2 * input.first) - input[index]);
  }
  output.addAll(input);
  for (int index = 1; index <= padLength; index++) {
    output.add((2 * input.last) - input[input.length - 1 - index]);
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
    final double y0 =
        (biquad.b0 * x0) +
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

enum _BiquadMode { lowPass, highPass, notch }
