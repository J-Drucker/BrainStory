import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class KMeansNodeType extends NodeType {
  @override
  String get title => 'K-Means';

  @override
  NodeCategory get category => NodeCategory.machineLearning;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'clusterCount': 4,
        'featureSource': 'segment_mean',
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'segments', type: PortType.metadata),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'metadata', type: PortType.metadata),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('clusterCount', () => 4);
    params.putIfAbsent('featureSource', () => 'segment_mean');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Placeholder machine-learning node for clustering segmented data. This will eventually assign segments to clusters and emit cluster metadata.',
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'clusterCount',
          labelText: 'Number of clusters',
          keyboardType: TextInputType.number,
          parser: (String value, dynamic previous) =>
              int.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'featureSource',
          labelText: 'Feature source',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'segment_mean',
              label: 'Segment mean',
            ),
            NodeDropdownOption<String>(
              value: 'segment_rms',
              label: 'Segment RMS',
            ),
            NodeDropdownOption<String>(
              value: 'custom',
              label: 'Custom later',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    dataset.ram['machineLearning.kmeans.params'] = <String, dynamic>{
      'clusterCount': params['clusterCount'] ?? 4,
      'featureSource': params['featureSource'] ?? 'segment_mean',
      'implemented': false,
    };
  }
}

class CNNNodeType extends NodeType {
  @override
  String get title => 'CNN';

  @override
  NodeCategory get category => NodeCategory.machineLearning;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'architecture': 'sleep_staging',
        'outputMode': 'class_labels',
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'time_frequency', type: PortType.metadata),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'metadata', type: PortType.metadata),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('architecture', () => 'sleep_staging');
    params.putIfAbsent('outputMode', () => 'class_labels');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Placeholder machine-learning node for convolutional models operating on time-frequency representations.',
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'architecture',
          labelText: 'Architecture',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'sleep_staging',
              label: 'Sleep staging CNN',
            ),
            NodeDropdownOption<String>(
              value: 'artifact_detection',
              label: 'Artifact detection CNN',
            ),
            NodeDropdownOption<String>(
              value: 'custom',
              label: 'Custom later',
            ),
          ],
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'outputMode',
          labelText: 'Output',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'class_labels',
              label: 'Class labels',
            ),
            NodeDropdownOption<String>(
              value: 'probabilities',
              label: 'Probabilities',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    dataset.ram['machineLearning.cnn.params'] = <String, dynamic>{
      'architecture': params['architecture'] ?? 'sleep_staging',
      'outputMode': params['outputMode'] ?? 'class_labels',
      'implemented': false,
    };
  }
}
