import 'package:flutter/material.dart';
import 'node_type.dart';
import '../model/dataset.dart';

class ImportNodeType extends NodeType {
  @override
  String get title => 'Import';

  @override
  Map<String, dynamic> get defaultParams => {
    'selectedDatasetIds': <String>[],
  };

  @override
  List<PortSpec> get inputs => const [];

  @override
  List<PortSpec> get outputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    final selected =
    Set<String>.from(params['selectedDatasetIds'] ?? const <String>[]);

    final entries = datasets.entries.toList()
      ..sort((a, b) => a.value.label.compareTo(b.value.label));

    return SizedBox(
      height: 300,
      child: ListView(
        children: entries.map((e) {
          return CheckboxListTile(
            title: Text(e.value.label),
            value: selected.contains(e.key),
            onChanged: (v) {
              setState(() {
                v == true ? selected.add(e.key) : selected.remove(e.key);
                params['selectedDatasetIds'] = selected.toList();
              });
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    // Minimal: “load” synthetic signal into RAM (until EDF parsing exists)
    const fs = 256.0;
    const n = 256 * 5; // 5 seconds

    final samples = List<double>.generate(n, (i) {
      final t = i / fs;
      // mix of 10 Hz + 20 Hz
      return 0.8 * _sin(2 * 3.141592653589793 * 10 * t) +
          0.4 * _sin(2 * 3.141592653589793 * 20 * t);
    });

    dataset.loaded = true;
    dataset.ram['signal.fs'] = fs;
    dataset.ram['signal.samples'] = samples;
  }

  double _sin(double x) {
    // tiny helper (avoid importing dart:math everywhere yet)
    // good enough for synthetic stub
    return (x - (x * x * x) / 6 + (x * x * x * x * x) / 120);
  }
}
