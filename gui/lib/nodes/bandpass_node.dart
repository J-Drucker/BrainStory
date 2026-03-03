import 'package:flutter/material.dart';
import 'node_type.dart';
import '../model/dataset.dart';
import '../ui/node_config.dart';

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
  Widget buildConfigWidget(
      Map<String, dynamic> params,
      void Function(Map<String, dynamic>) onSave, {
        Map<String, Dataset>? datasets,
      }) {
    return BandpassConfigWidget(
      initialParams: params,
      onSave: onSave,
    );
  }

  @override
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
    return const Text('Parameters coming soon');
  }
}
