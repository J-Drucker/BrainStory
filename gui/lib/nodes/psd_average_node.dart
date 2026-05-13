import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class PSDAverageNodeType extends NodeType {
  @override
  String get title => 'Average Spectra';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Frequency Domain';

  @override
  Map<String, dynamic> get defaultParams => const <String, dynamic>{};

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'psd', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'psd', type: PortType.signal),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    return const Text(
      'Averages the segment-level spectra produced by PSD. If the incoming PSD '
      'is already averaged, it is passed through unchanged.',
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final FrequencySpectrumData? spectrum = dataset.spectrum;
    if (spectrum == null || spectrum.segmentPowers.isEmpty) {
      return;
    }
    final int binCount = spectrum.frequencies.length;
    final List<List<double>> validSegmentPowers = spectrum.segmentPowers
        .where((List<double> power) => power.length == binCount)
        .toList(growable: false);
    if (binCount == 0 || validSegmentPowers.isEmpty) {
      return;
    }

    final List<double> averagedPower = List<double>.filled(binCount, 0.0);
    for (final List<double> power in validSegmentPowers) {
      for (int index = 0; index < binCount; index++) {
        averagedPower[index] += power[index];
      }
    }
    for (int index = 0; index < binCount; index++) {
      averagedPower[index] /= validSegmentPowers.length;
    }

    dataset.spectrum = FrequencySpectrumData(
      frequencies: spectrum.frequencies,
      power: averagedPower,
      segmentPowers: spectrum.segmentPowers,
      segmentCount: validSegmentPowers.length,
      source: spectrum.source,
    );
  }
}
