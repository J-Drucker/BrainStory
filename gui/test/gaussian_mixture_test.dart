import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_artifact_snapshot.dart';
import 'package:brainstory_gui/nodes/gaussian_mixture_node.dart';
import 'package:brainstory_gui/nodes/node_registry.dart';
import 'package:brainstory_gui/nodes/node_type.dart';
import 'package:brainstory_gui/platform/brainstory_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gaussian mixture is a visible clustering node', () {
    final NodeRegistryEntry entry = NodeRegistry.entries.firstWhere(
      (NodeRegistryEntry item) => item.create() is GaussianMixtureNodeType,
    );
    final GaussianMixtureNodeType node =
        entry.create() as GaussianMixtureNodeType;

    expect(entry.visible, isTrue);
    expect(entry.group, NodeGroup.machineLearning);
    expect(node.subcategory, 'Clustering');
    expect(node.inputs.first.name, 'segments');
    expect(node.outputs.map((PortSpec port) => port.name), <String>[
      'table',
      'gaussian_mixture',
    ]);
    expect(node.defaultParams['standardize'], isTrue);
    expect(node.defaultParams['observationSource'], 'raw_segments');
  });

  test('native Gaussian mixture response retains model diagnostics', () {
    final NativeGaussianMixtureResult result =
        NativeGaussianMixtureResult.fromJson(<String, dynamic>{
          'assignments': <int>[0, 1],
          'probabilities': <List<double>>[
            <double>[0.9, 0.1],
            <double>[0.2, 0.8],
          ],
          'weights': <double>[0.5, 0.5],
          'means': <List<double>>[
            <double>[1.0],
            <double>[4.0],
          ],
          'variances': <List<double>>[
            <double>[0.2],
            <double>[0.3],
          ],
          'converged': true,
          'iterationCount': 12,
          'logLikelihood': -8.0,
          'aic': 26.0,
          'bic': 25.0,
          'normalizationMean': <double>[2.5],
          'normalizationScale': <double>[1.5],
        });

    expect(result.assignments, <int>[0, 1]);
    expect(result.probabilities[1][1], 0.8);
    expect(result.converged, isTrue);
    expect(result.iterationCount, 12);
    expect(result.bic, 25.0);
  });

  test('Gaussian mixture artifacts survive dataset snapshots', () {
    final Dataset source = Dataset('dataset-1', label: 'Features');
    source.featureTable = const FeatureTableData(
      columns: <String>['x', 'gmm_cluster', 'gmm_probability'],
      rows: <Map<String, String>>[
        <String, String>{
          'x': '1.0',
          'gmm_cluster': '1',
          'gmm_probability': '0.99',
        },
      ],
    );
    source.gaussianMixture = const GaussianMixtureData(
      featureColumns: <String>['x'],
      assignments: <int>[0],
      probabilities: <List<double>>[
        <double>[0.99, 0.01],
      ],
      weights: <double>[0.5, 0.5],
      means: <List<double>>[
        <double>[1.0],
        <double>[4.0],
      ],
      variances: <List<double>>[
        <double>[0.2],
        <double>[0.3],
      ],
      converged: true,
      iterationCount: 8,
      logLikelihood: -4.0,
      aic: 18.0,
      bic: 17.0,
      standardized: true,
      normalizationMean: <double>[2.5],
      normalizationScale: <double>[1.5],
    );

    final DatasetArtifactSnapshot snapshot = DatasetArtifactSnapshot.fromJson(
      DatasetArtifactSnapshot.fromDataset(source).toJson(),
    );
    final Dataset restored = Dataset('dataset-1', label: 'Restored');
    snapshot.applyToDataset(restored);

    expect(restored.featureTable!.rows.single['gmm_cluster'], '1');
    expect(restored.gaussianMixture!.featureColumns, <String>['x']);
    expect(restored.gaussianMixture!.probabilities.single, <double>[
      0.99,
      0.01,
    ]);
    expect(restored.gaussianMixture!.converged, isTrue);
  });

  test('Gaussian mixture rejects too few feature rows before execution', () {
    final Dataset dataset = Dataset('dataset-1', label: 'Features');
    dataset.featureTable = const FeatureTableData(
      columns: <String>['name', 'x'],
      rows: <Map<String, String>>[
        <String, String>{'name': 'a', 'x': '1.0'},
        <String, String>{'name': 'b', 'x': '2.0'},
      ],
    );

    expect(
      () => GaussianMixtureNodeType().run(dataset, <String, dynamic>{
        ...GaussianMixtureNodeType().defaultParams,
        'observationSource': 'feature_table',
        'componentCount': 3,
      }),
      throwsA(isA<StateError>()),
    );
  });

  test('raw Gaussian mixture requires equally shaped segments', () {
    final Dataset dataset = Dataset('dataset-1', label: 'Segments');
    dataset.segmentedTimeSeries = const SegmentedTimeSeriesData(
      sampleRate: 100,
      channelLabels: <String>['Cz'],
      segments: <SignalSegmentData>[
        SignalSegmentData(
          channelSamples: <List<double>>[
            <double>[1, 2, 3],
          ],
          startSeconds: 0,
          stopSeconds: 0.03,
          label: 'A',
        ),
        SignalSegmentData(
          channelSamples: <List<double>>[
            <double>[4, 5],
          ],
          startSeconds: 1,
          stopSeconds: 1.02,
          label: 'B',
        ),
      ],
    );

    expect(
      () => GaussianMixtureNodeType().run(dataset, <String, dynamic>{
        ...GaussianMixtureNodeType().defaultParams,
        'componentCount': 2,
      }),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message.toString(),
          'message',
          contains('Pool, select channels, or downsample upstream'),
        ),
      ),
    );
  });

  test('raw Gaussian mixture fits unchanged segment samples', () async {
    final Dataset dataset = Dataset('dataset-raw', label: 'Raw segments');
    dataset.segmentedTimeSeries = const SegmentedTimeSeriesData(
      sampleRate: 100,
      channelLabels: <String>['Cz'],
      segments: <SignalSegmentData>[
        SignalSegmentData(
          channelSamples: <List<double>>[
            <double>[0, 0.1],
          ],
          startSeconds: 0,
          stopSeconds: 0.02,
          label: 'low',
        ),
        SignalSegmentData(
          channelSamples: <List<double>>[
            <double>[0.1, 0],
          ],
          startSeconds: 1,
          stopSeconds: 1.02,
          label: 'low',
        ),
        SignalSegmentData(
          channelSamples: <List<double>>[
            <double>[10, 10.1],
          ],
          startSeconds: 2,
          stopSeconds: 2.02,
          label: 'high',
        ),
        SignalSegmentData(
          channelSamples: <List<double>>[
            <double>[10.1, 10],
          ],
          startSeconds: 3,
          stopSeconds: 3.02,
          label: 'high',
        ),
      ],
    );

    await GaussianMixtureNodeType().run(dataset, <String, dynamic>{
      ...GaussianMixtureNodeType().defaultParams,
      'componentCount': 2,
    });

    expect(dataset.gaussianMixture?.featureColumns, <String>[
      'value_1',
      'value_2',
    ]);
    expect(dataset.gaussianMixture?.assessmentVariables, <String>['label']);
    expect(dataset.featureTable?.rows, hasLength(4));
    expect(dataset.featureTable?.rows.first['label'], 'low');
    expect(dataset.featureTable?.rows.first, contains('gmm_cluster'));
  });

  test('Gaussian mixture assessment variables survive snapshots', () {
    const GaussianMixtureData model = GaussianMixtureData(
      featureColumns: <String>['value_1'],
      assignments: <int>[0],
      probabilities: <List<double>>[
        <double>[1],
      ],
      weights: <double>[1],
      means: <List<double>>[
        <double>[0],
      ],
      variances: <List<double>>[
        <double>[1],
      ],
      converged: true,
      iterationCount: 1,
      logLikelihood: 0,
      aic: 0,
      bic: 0,
      standardized: false,
      normalizationMean: <double>[0],
      normalizationScale: <double>[1],
      assessmentVariables: <String>['label', 'kind'],
    );
    final GaussianMixtureData restored = GaussianMixtureData.fromJson(
      model.toJson(),
    );
    expect(restored.assessmentVariables, <String>['label', 'kind']);
  });
}
