import 'package:flutter/material.dart';
import 'node_type.dart';
import '../model/dataset.dart';

class PSDNodeType extends NodeType {
  @override
  String get title => 'PSD';

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
              child: TextFormField(
                initialValue: params['fLow'].toString(),
                decoration: const InputDecoration(labelText: 'Lowest'),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  setState(() {
                    params['fLow'] = double.tryParse(v) ?? params['fLow'];
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: params['fHigh'].toString(),
                decoration: const InputDecoration(labelText: 'Highest'),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  setState(() {
                    params['fHigh'] = double.tryParse(v) ?? params['fHigh'];
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Output', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButtonFormField<String>(
          initialValue: params['outputMode']?.toString() ?? 'averaged',
          decoration: const InputDecoration(labelText: 'Mode'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'segments',
              child: Text('As segments'),
            ),
            DropdownMenuItem<String>(
              value: 'averaged',
              child: Text('Averaged'),
            ),
          ],
          onChanged: (v) => setState(() => params['outputMode'] = v),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final samples = dataset.ram['signal.samples'] as List<double>?;
    final fs = dataset.ram['signal.fs'] as double?;

    if (samples == null || fs == null) {
      // No signal loaded yet
      return;
    }

    final fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
    final fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;

    // Minimal “PSD”: make bins and a simple power proxy.
    // (Real FFT/multitaper later.)
    final nBins = 64;
    final freqs = List<double>.generate(nBins, (i) {
      return fLow + (fHigh - fLow) * (i / (nBins - 1));
    });

    // simple proxy: average squared amplitude
    double meanSq = 0.0;
    for (final x in samples) {
      meanSq += x * x;
    }
    meanSq /= samples.length;

    final mode = (params['outputMode'] ?? 'averaged').toString();

    // If segments, just exaggerate variability (placeholder)
    final power = List<double>.generate(nBins, (i) {
      final base = meanSq / (1.0 + i / 10.0);
      return mode == 'segments' ? base * (1.0 + (i % 5) * 0.05) : base;
    });

    dataset.ram['psd.freqs'] = freqs;
    dataset.ram['psd.power'] = power;
  }
}
