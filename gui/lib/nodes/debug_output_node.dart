import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class DebugOutputNodeType extends NodeType {
  @override
  String get title => 'Debug Output';

  @override
  NodeCategory get category => NodeCategory.visualize;

  @override
  Map<String, dynamic> get defaultParams => {
    'artifact': 'signal', // 'signal' or 'psd'
    'lines': 5,
  };

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'in', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const [];

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    params.putIfAbsent('artifact', () => 'signal');
    params.putIfAbsent('lines', () => 5);

    final artifact = (params['artifact'] ?? 'signal').toString();
    final lines = (params['lines'] is int) ? params['lines'] as int : 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What to print', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: artifact,
          items: const [
            DropdownMenuItem(value: 'signal', child: Text('Signal (samples)')),
            DropdownMenuItem(value: 'psd', child: Text('PSD (freq,power)')),
          ],
          onChanged: (v) => setState(() => params['artifact'] = v ?? 'signal'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Lines:'),
            const SizedBox(width: 10),
            DropdownButton<int>(
              value: lines,
              items: const [
                DropdownMenuItem(value: 3, child: Text('3')),
                DropdownMenuItem(value: 5, child: Text('5')),
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 20, child: Text('20')),
              ],
              onChanged: (v) => setState(() => params['lines'] = v ?? 5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Run this node to print to the Debug Console.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final artifact = (params['artifact'] ?? 'signal').toString();
    final lines = ((params['lines'] as num?)?.toInt() ?? 5).clamp(1, 200);

    if (artifact == 'signal') {
      final TimeSeriesData? timeSeries = dataset.timeSeries;
      final fs = timeSeries?.sampleRate;
      final channels = timeSeries?.channels;

      debugPrint('--- Debug Output: SIGNAL for ${dataset.label} (${dataset.id}) ---');
      debugPrint('fs: $fs');
      if (channels is List<List<double>> && channels.isNotEmpty) {
        final List<double> samples = channels.first;
        final n = samples.length;
        final k = lines.clamp(1, n);
        debugPrint('channels: ${channels.length}');
        for (int i = 0; i < k; i++) {
          debugPrint('sample[$i] = ${samples[i]}');
        }
        debugPrint('... total samples: $n');
      } else {
        debugPrint('No signal in RAM. (Run Import first)');
      }
      return;
    }

    if (artifact == 'psd') {
      final FrequencySpectrumData? spectrum = dataset.spectrum;
      final freqs = spectrum?.frequencies;
      final power = spectrum?.power;

      debugPrint('--- Debug Output: PSD for ${dataset.label} (${dataset.id}) ---');
      if (freqs is List<double> && power is List<double>) {
        final n = freqs.length < power.length ? freqs.length : power.length;
        final k = lines.clamp(1, n);
        for (int i = 0; i < k; i++) {
          debugPrint('freq=${freqs[i]}  power=${power[i]}');
        }
        debugPrint('... total bins: $n');
      } else {
        debugPrint('No PSD in RAM. (Run PSD node first)');
      }
    }
  }
}
