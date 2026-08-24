import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class IcaComponentRejectionNodeType extends NodeType {
  @override
  String get title => 'ICA Component Rejection';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Matrix Transformation';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'excludedComponents': <int>[],
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'ICA activations', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'clean signal', type: PortType.signal),
  ];

  static Set<int> excludedComponents(Map<String, dynamic> params) {
    return (params['excludedComponents'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<num>()
        .map((num value) => value.toInt())
        .where((int value) => value >= 0)
        .toSet();
  }

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    final List<dynamic> selectedDatasetIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final Dataset? dataset = datasets.values
        .where(
          (Dataset item) =>
              item.matrixTransformation != null &&
              (selectedDatasetIds.isEmpty ||
                  selectedDatasetIds.contains(item.id)),
        )
        .cast<Dataset?>()
        .firstWhere((Dataset? item) => item != null, orElse: () => null);
    final MatrixTransformationData? transform = dataset?.matrixTransformation;
    final int componentCount = transform?.componentCount ?? 0;
    final Set<int> excluded = excludedComponents(params);
    if (transform == null || componentCount == 0) {
      return const Text(
        'Connect this node downstream of a completed ICA node.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('Components excluded during sensor-space reconstruction.'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<Widget>.generate(componentCount, (int index) {
            final String label = index < transform.componentLabels.length
                ? transform.componentLabels[index]
                : 'IC ${index + 1}';
            return FilterChip(
              label: Text(label),
              selected: excluded.contains(index),
              onSelected: (bool selected) {
                setState(() {
                  selected ? excluded.add(index) : excluded.remove(index);
                  params['excludedComponents'] = excluded.toList()..sort();
                });
              },
            );
          }),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? activations = dataset.timeSeries;
    final MatrixTransformationData? transform = dataset.matrixTransformation;
    if (activations == null || activations.channels.isEmpty) {
      throw StateError('ICA component activations are unavailable.');
    }
    if (transform == null || transform.mixingMatrix.isEmpty) {
      throw StateError('ICA reconstruction metadata is unavailable.');
    }
    final Set<int> excluded = excludedComponents(params);
    if (excluded.any((int index) => index >= transform.componentCount)) {
      throw RangeError('An excluded ICA component is out of range.');
    }
    final List<List<double>> cleanChannels = transform
        .reconstructSensorChannels(
          activations.channels,
          excludedComponents: excluded,
        );
    final List<String> labels =
        transform.originalChannelLabels.length == cleanChannels.length
        ? transform.originalChannelLabels
        : List<String>.generate(
            cleanChannels.length,
            (int index) => 'Channel ${index + 1}',
            growable: false,
          );
    final List<int> sortedExcluded = excluded.toList()..sort();
    final String excludedLabels = sortedExcluded.isEmpty
        ? 'none'
        : sortedExcluded
              .map(
                (int index) => index < transform.componentLabels.length
                    ? transform.componentLabels[index]
                    : 'IC ${index + 1}',
              )
              .join(', ');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: cleanChannels,
      sampleRate: activations.sampleRate,
      channelLabels: labels,
      channelCoordinates: transform.originalChannelCoordinates,
      impedanceData: transform.originalImpedanceData,
      markers: activations.markers,
      factors: activations.factors,
      source: '${activations.source} -> ICA rejection ($excludedLabels)',
    );
    dataset.segmentedTimeSeries = null;
  }
}
