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
    'useParentSegments': false,
    'parentSegmentsNodeId': '',
    'windowing': 'hamming',
    'windowLengthSec': 2.0,
    'windowOverlapPercent': 10,
  };

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'segments', type: PortType.metadata),
  ];

  @override
  List<PortSpec> get outputs => const [
    PortSpec(name: 'psd', type: PortType.signal),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('fLow', () => 1.0);
    params.putIfAbsent('fHigh', () => 40.0);
    params.putIfAbsent('outputMode', () => 'averaged');
    params.putIfAbsent('useParentSegments', () => false);
    params.putIfAbsent('parentSegmentsNodeId', () => '');
    params.putIfAbsent('windowing', () => 'hamming');
    params.putIfAbsent('windowLengthSec', () => 2.0);
    params.putIfAbsent('windowOverlapPercent', () => 50);
    final List<_ParentSegmentOption> parentSegmentOptions =
        _parentSegmentOptionsFromParams(params);
    final bool useParentSegments = params['useParentSegments'] == true;
    final bool selectedParentIsAvailable = parentSegmentOptions.any(
      (_ParentSegmentOption option) =>
          option.id == params['parentSegmentsNodeId']?.toString(),
    );
    if (!selectedParentIsAvailable && parentSegmentOptions.length == 1) {
      params['parentSegmentsNodeId'] = parentSegmentOptions.single.id;
    }

    Widget compactRadio({required String label, required String value}) {
      return RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        title: Text(label),
        value: value,
      );
    }

    Widget optionColumn({
      required String title,
      required List<Widget> children,
      double? width,
    }) {
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Frequency Range',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              optionColumn(
                title: 'Lowest',
                width: 88,
                children: <Widget>[
                  NodeParamTextField(
                    params: params,
                    paramKey: 'fLow',
                    labelText: 'Hz',
                    keyboardType: TextInputType.number,
                    parser: (String value, dynamic previous) =>
                        double.tryParse(value) ?? previous,
                  ),
                ],
              ),
              const SizedBox(width: 12),
              optionColumn(
                title: 'Highest',
                width: 88,
                children: <Widget>[
                  NodeParamTextField(
                    params: params,
                    paramKey: 'fHigh',
                    labelText: 'Hz',
                    keyboardType: TextInputType.number,
                    parser: (String value, dynamic previous) =>
                        double.tryParse(value) ?? previous,
                  ),
                ],
              ),
              const SizedBox(width: 16),
              optionColumn(
                title: 'Output',
                width: 132,
                children: <Widget>[
                  RadioGroup<String>(
                    groupValue: params['outputMode']?.toString() ?? 'averaged',
                    onChanged: (String? value) {
                      if (value == null) return;
                      setState(() {
                        params['outputMode'] = value;
                      });
                    },
                    child: Column(
                      children: <Widget>[
                        compactRadio(label: 'As segments', value: 'segments'),
                        compactRadio(label: 'Averaged', value: 'averaged'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              optionColumn(
                title: 'Windowing',
                width: 126,
                children: <Widget>[
                  RadioGroup<String>(
                    groupValue: params['windowing']?.toString() ?? 'hamming',
                    onChanged: (String? value) {
                      if (value == null) return;
                      setState(() {
                        params['windowing'] = value;
                      });
                    },
                    child: Column(
                      children: <Widget>[
                        compactRadio(label: 'None', value: 'none'),
                        compactRadio(label: 'Unweighted', value: 'unweighted'),
                        compactRadio(label: 'Hamming', value: 'hamming'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              optionColumn(
                title: 'Length',
                width: 112,
                children: <Widget>[
                  NodeParamTextField(
                    params: params,
                    paramKey: 'windowLengthSec',
                    labelText: 'sec',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    parser: (String value, dynamic previous) =>
                        double.tryParse(value) ?? previous,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Overlap',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  NodeParamTextField(
                    params: params,
                    paramKey: 'windowOverlapPercent',
                    labelText: '%',
                    keyboardType: TextInputType.number,
                    parser: (String value, dynamic previous) =>
                        int.tryParse(value) ?? previous,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: useParentSegments,
          title: const Text('Use parent segments'),
          subtitle: Text(
            parentSegmentOptions.isEmpty
                ? 'Off: PSD creates FFT windows before running.'
                : 'Off: PSD creates FFT windows. On: use segments from an upstream node.',
          ),
          onChanged: (bool? value) {
            setState(() {
              params['useParentSegments'] = value == true;
              if (value == true &&
                  params['parentSegmentsNodeId'].toString().isEmpty &&
                  parentSegmentOptions.isNotEmpty) {
                params['parentSegmentsNodeId'] = parentSegmentOptions.first.id;
              }
            });
          },
        ),
        if (useParentSegments && parentSegmentOptions.length > 1) ...<Widget>[
          const SizedBox(height: 8),
          NodeParamDropdownField<String>(
            params: params,
            paramKey: 'parentSegmentsNodeId',
            labelText: 'Segment parent',
            helperText: 'Choose which upstream segment set PSD should use.',
            options: parentSegmentOptions
                .map(
                  (_ParentSegmentOption option) => NodeDropdownOption<String>(
                    value: option.id,
                    label: option.label,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final SegmentedTimeSeriesData? segmented = dataset.segmentedTimeSeries;
    if (segmented == null || segmented.segments.isEmpty) {
      // PSD operates on explicit analysis windows. Run equal-window
      // segmentation upstream first.
      dataset.spectrum = null;
      return;
    }

    final fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
    final fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
    final mode = (params['outputMode'] ?? 'averaged').toString();
    final bool deferAverageToDownstream =
        params['deferAverageToDownstream'] == true;
    final bool averageInThisNode =
        mode != 'segments' && !deferAverageToDownstream;
    final SpectrumResult spectrum;
    final String source;
    spectrum = computeSegmentedSpectrum(
      segmented,
      fLow: fLow,
      fHigh: fHigh,
      averageWithinSegment: true,
      averageAcrossSegments: averageInThisNode,
    );
    source = segmented.source;

    dataset.spectrum = FrequencySpectrumData(
      frequencies: spectrum.freqs,
      power: spectrum.power,
      segmentPowers: spectrum.segmentPowers,
      segmentCount: spectrum.segmentCount,
      source: source,
    );
  }
}

class _ParentSegmentOption {
  const _ParentSegmentOption({required this.id, required this.label});

  final String id;
  final String label;
}

List<_ParentSegmentOption> _parentSegmentOptionsFromParams(
  Map<String, dynamic> params,
) {
  final List<dynamic> rawOptions =
      params['_parentSegmentOptions'] as List<dynamic>? ?? const <dynamic>[];
  return rawOptions
      .whereType<Map<dynamic, dynamic>>()
      .map((Map<dynamic, dynamic> asMap) {
        final String id = asMap['id']?.toString() ?? '';
        final String label = asMap['label']?.toString() ?? id;
        if (id.isEmpty) {
          return null;
        }
        return _ParentSegmentOption(id: id, label: label);
      })
      .whereType<_ParentSegmentOption>()
      .toList(growable: false);
}

class SpectrumResult {
  const SpectrumResult({
    required this.freqs,
    required this.power,
    this.segmentPowers = const <List<double>>[],
    required this.segmentCount,
  });

  final List<double> freqs;
  final List<double> power;
  final List<List<double>> segmentPowers;
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
    return const SpectrumResult(
      freqs: <double>[],
      power: <double>[],
      segmentPowers: <List<double>>[],
      segmentCount: 0,
    );
  }

  final int segmentLength = _largestPowerOfTwo(
    math.max(32, math.min(samples.length, 256)),
  );
  final int hopLength = math.max(1, segmentLength ~/ 2);

  final List<List<double>> spectra = <List<double>>[];
  final List<double> freqs = <double>[];

  for (
    int start = 0;
    start + segmentLength <= samples.length;
    start += hopLength
  ) {
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
      segmentPowers: <List<double>>[single.power],
      segmentCount: 1,
    );
  }

  if (!averageSegments) {
    return SpectrumResult(
      freqs: freqs,
      power: spectra.first,
      segmentPowers: spectra,
      segmentCount: spectra.length,
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
    segmentPowers: spectra,
    segmentCount: spectra.length,
  );
}

SpectrumResult computeSegmentedSpectrum(
  SegmentedTimeSeriesData segmented, {
  required double fLow,
  required double fHigh,
  required bool averageWithinSegment,
  bool averageAcrossSegments = true,
}) {
  final List<SpectrumResult> spectra = <SpectrumResult>[];
  for (final SignalSegmentData segment in segmented.segments) {
    final List<List<double>> channels = segmented.channelSamplesForSegment(
      segment,
    );
    if (channels.isEmpty || channels.first.isEmpty) {
      continue;
    }
    final SpectrumResult spectrum = computeSpectrum(
      channels.first,
      sampleRate: segmented.sampleRate,
      fLow: fLow,
      fHigh: fHigh,
      averageSegments: averageWithinSegment,
    );
    if (spectrum.freqs.isNotEmpty && spectrum.power.isNotEmpty) {
      spectra.add(spectrum);
    }
  }
  if (spectra.isEmpty) {
    return const SpectrumResult(
      freqs: <double>[],
      power: <double>[],
      segmentPowers: <List<double>>[],
      segmentCount: 0,
    );
  }
  final List<double> freqs = spectra.first.freqs;
  final int binCount = freqs.length;
  final List<double> power = List<double>.filled(binCount, 0.0);
  final List<List<double>> segmentPowers = <List<double>>[];
  int includedSpectra = 0;
  int sourceSegmentCount = 0;
  for (final SpectrumResult spectrum in spectra) {
    if (spectrum.freqs.length != binCount ||
        spectrum.power.length != binCount) {
      continue;
    }
    for (int index = 0; index < binCount; index++) {
      power[index] += spectrum.power[index];
    }
    segmentPowers.add(spectrum.power);
    includedSpectra++;
    sourceSegmentCount += math.max(1, spectrum.segmentCount);
  }
  if (includedSpectra == 0) {
    return const SpectrumResult(
      freqs: <double>[],
      power: <double>[],
      segmentPowers: <List<double>>[],
      segmentCount: 0,
    );
  }
  if (!averageAcrossSegments) {
    return SpectrumResult(
      freqs: freqs,
      power: segmentPowers.first,
      segmentPowers: segmentPowers,
      segmentCount: sourceSegmentCount,
    );
  }
  for (int index = 0; index < power.length; index++) {
    power[index] /= includedSpectra;
  }
  return SpectrumResult(
    freqs: freqs,
    power: power,
    segmentPowers: segmentPowers,
    segmentCount: sourceSegmentCount,
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
    segmentPowers: <List<double>>[power],
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
