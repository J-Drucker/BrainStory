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
    await Future.delayed(const Duration(milliseconds: 50));
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
