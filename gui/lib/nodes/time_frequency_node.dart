import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/brainstory_engine.dart';
import 'node_type.dart';

class TimeFrequencyNodeType extends NodeType {
  @override
  String get title => 'Time-Frequency (Wavelet)';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Frequency Domain';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'fLow': 1.0,
    'fHigh': 40.0,
    'frequencyBins': 40,
    'timeBins': 240,
    'cycles': 6.0,
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'time_frequency', type: PortType.metadata),
  ];

  @override
  String get executionChunkingStrategy => 'by channel';

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    for (final MapEntry<String, dynamic> entry in defaultParams.entries) {
      params.putIfAbsent(entry.key, () => entry.value);
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _field(params, 'fLow', 'Lowest Hz', decimal: true),
        _field(params, 'fHigh', 'Highest Hz', decimal: true),
        _field(params, 'frequencyBins', 'Frequency bins'),
        _field(params, 'timeBins', 'Maximum time bins'),
        _field(params, 'cycles', 'Wavelet cycles', decimal: true),
        const SizedBox(
          width: 520,
          child: Text(
            'Output is deliberately bounded. The viewer loads one dataset and one channel at a time.',
          ),
        ),
      ],
    );
  }

  Widget _field(
    Map<String, dynamic> params,
    String key,
    String label, {
    bool decimal = false,
  }) {
    return SizedBox(
      width: 150,
      child: NodeParamTextField(
        params: params,
        paramKey: key,
        labelText: label,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        parser: (String value, dynamic previous) => decimal
            ? double.tryParse(value) ?? previous
            : int.tryParse(value) ?? previous,
      ),
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    await _run(dataset, params, null);
  }

  @override
  Future<void> runChunked(
    Dataset dataset,
    Map<String, dynamic> params,
    NodeExecutionContext context,
  ) => _run(dataset, params, context);

  Future<void> _run(
    Dataset dataset,
    Map<String, dynamic> params,
    NodeExecutionContext? context,
  ) async {
    final TimeSeriesData? signal = dataset.timeSeries;
    if (signal == null || signal.channels.isEmpty) return;
    final double low = (params['fLow'] as num?)?.toDouble() ?? 1.0;
    final double nyquist = signal.sampleRate / 2.0;
    final double requestedHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
    if (!low.isFinite || low <= 0 || low > nyquist) {
      throw ArgumentError(
        'Lowest frequency must be above 0 Hz and no higher than '
        '${nyquist.toStringAsFixed(2)} Hz.',
      );
    }
    if (!requestedHigh.isFinite || requestedHigh < low) {
      throw ArgumentError(
        'Highest frequency must be at least the lowest frequency.',
      );
    }
    final double high = math.min(requestedHigh, nyquist);
    final int frequencyBins = ((params['frequencyBins'] as num?)?.toInt() ?? 40)
        .clamp(1, 128);
    final int timeBins = ((params['timeBins'] as num?)?.toInt() ?? 240).clamp(
      1,
      2048,
    );
    final double cycles = ((params['cycles'] as num?)?.toDouble() ?? 6.0).clamp(
      2.0,
      20.0,
    );
    final List<List<List<double>>> matrices = <List<List<double>>>[];
    List<double> times = const <double>[];
    List<double> frequencies = const <double>[];
    for (int channel = 0; channel < signal.channels.length; channel++) {
      await context?.setProgress(
        'Wavelet channel ${channel + 1} of ${signal.channels.length}',
      );
      final NativeWaveletResult? result = await computeWaveletBackground(
        signal.channels[channel],
        sampleRate: signal.sampleRate,
        lowHz: low,
        highHz: high,
        frequencyCount: frequencyBins,
        timeCount: timeBins,
        cycles: cycles,
      );
      if (result == null) {
        throw UnsupportedError('The BrainStory wavelet engine is unavailable.');
      }
      times = result.times;
      frequencies = result.frequencies;
      matrices.add(result.powerMatrix);
      await context?.yieldIfNeeded();
    }
    dataset.timeFrequency = TimeFrequencyData(
      times: times,
      frequencies: frequencies,
      powerMatrix: matrices.first,
      channelPowerMatrices: matrices,
      channelLabels: signal.channelLabels,
      source: signal.source.isEmpty
          ? 'Morlet wavelet'
          : '${signal.source} -> Morlet wavelet',
    );
  }
}
