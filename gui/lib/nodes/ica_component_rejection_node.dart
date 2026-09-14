import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class IcaComponentRejectionNodeType extends NodeType {
  @override
  String get title => 'Apply ICA';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Matrix Transformation';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'excludedComponents': <int>[],
    'excludedComponentsByDataset': <String, List<int>>{},
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'ICA transform', type: PortType.matrixTransformation),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'clean signal', type: PortType.signal),
  ];

  static Set<int> excludedComponents(
    Map<String, dynamic> params, {
    String? datasetId,
  }) {
    final Object? perDataset = params['excludedComponentsByDataset'];
    final List<dynamic> values;
    if (datasetId != null && perDataset is Map && perDataset.isNotEmpty) {
      values = perDataset[datasetId] as List<dynamic>? ?? const <dynamic>[];
    } else {
      values =
          params['excludedComponents'] as List<dynamic>? ?? const <dynamic>[];
    }
    return values
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
    final List<Dataset> applicableDatasets = datasets.values
        .where(
          (Dataset item) =>
              item.matrixTransformation != null &&
              (selectedDatasetIds.isEmpty ||
                  selectedDatasetIds.contains(item.id)),
        )
        .toList(growable: false);
    if (applicableDatasets.isEmpty) {
      return const Text(
        'Connect compatible signal data and a completed ICA transform.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('Components excluded during sensor-space reconstruction.'),
        const SizedBox(height: 10),
        for (final Dataset dataset in applicableDatasets) ...<Widget>[
          Text(
            dataset.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Builder(
            builder: (BuildContext context) {
              final MatrixTransformationData transform =
                  dataset.matrixTransformation!;
              final Set<int> excluded = excludedComponents(
                params,
                datasetId: dataset.id,
              );
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List<Widget>.generate(transform.componentCount, (
                  int index,
                ) {
                  final String label = index < transform.componentLabels.length
                      ? transform.componentLabels[index]
                      : 'IC ${index + 1}';
                  return FilterChip(
                    label: Text(label),
                    selected: excluded.contains(index),
                    onSelected: (bool selected) {
                      setState(() {
                        selected ? excluded.add(index) : excluded.remove(index);
                        final Map<String, dynamic> byDataset =
                            Map<String, dynamic>.from(
                              params['excludedComponentsByDataset'] as Map? ??
                                  const <String, dynamic>{},
                            );
                        byDataset[dataset.id] = excluded.toList()..sort();
                        params['excludedComponentsByDataset'] = byDataset;
                      });
                    },
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? input = dataset.timeSeries;
    final MatrixTransformationData? transform = dataset.matrixTransformation;
    if (input == null || input.channels.isEmpty) {
      throw StateError('Signal data for ICA application is unavailable.');
    }
    if (transform == null || transform.mixingMatrix.isEmpty) {
      throw StateError('ICA reconstruction metadata is unavailable.');
    }
    final Set<int> excluded = excludedComponents(params, datasetId: dataset.id);
    if (excluded.any((int index) => index >= transform.componentCount)) {
      throw RangeError('An excluded ICA component is out of range.');
    }
    final bool inputIsActivations = transform.matchesComponentActivations(
      input,
    );
    final List<List<double>> activations = inputIsActivations
        ? input.channels
        : transform.transformSensorChannels(input);
    final List<List<double>> reconstructedChannels = transform
        .reconstructSensorChannels(activations, excludedComponents: excluded);
    final List<List<double>> cleanChannels;
    final List<String> labels;
    if (inputIsActivations) {
      cleanChannels = reconstructedChannels;
      labels = transform.originalChannelLabels;
    } else {
      cleanChannels = input.channels
          .map((List<double> channel) => List<double>.from(channel))
          .toList(growable: false);
      final List<int> selectedIndices =
          transform.resolvedSelectedChannelIndices;
      for (int index = 0; index < selectedIndices.length; index++) {
        cleanChannels[selectedIndices[index]] = reconstructedChannels[index];
      }
      labels = input.channelLabels;
    }
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
      sampleRate: input.sampleRate,
      channelLabels: labels,
      channelCoordinates: inputIsActivations
          ? transform.originalChannelCoordinates
          : input.channelCoordinates,
      impedanceData: inputIsActivations
          ? transform.originalImpedanceData
          : input.impedanceData,
      markers: input.markers,
      factors: input.factors,
      source: '${input.source} -> ICA rejection ($excludedLabels)',
    );
    dataset.segmentedTimeSeries = null;
  }
}
