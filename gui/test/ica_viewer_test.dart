import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_state.dart';
import 'package:brainstory_gui/model/node.dart';
import 'package:brainstory_gui/nodes/ica_component_rejection_node.dart';
import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/nodes/matrix_transform_nodes.dart';
import 'package:brainstory_gui/ui/canvas_logic.dart';
import 'package:brainstory_gui/ui/ica_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ICA selection supports preview, reset, and apply', (
    WidgetTester tester,
  ) async {
    final Dataset dataset = _icaDataset();
    Set<int>? applied;
    await _pumpViewer(
      tester,
      dataset: dataset,
      onApply: (Set<int> excluded) async {
        applied = excluded;
      },
    );

    await tester.tap(find.byKey(const ValueKey<String>('ica-component-0')));
    await tester.pump();
    expect(find.text('1 excluded'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('ica-preview')));
    await tester.pump();
    expect(find.text('Sensor-space preview'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ica-preview-traces')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('ica-apply')));
    await tester.pumpAndSettle();
    expect(applied, <int>{0});

    await tester.tap(find.byKey(const ValueKey<String>('ica-reset')));
    await tester.pump();
    expect(find.text('0 excluded'), findsOneWidget);
    expect(find.text('Component activation traces'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ICA viewer remains usable without channel coordinates', (
    WidgetTester tester,
  ) async {
    final Dataset dataset = _icaDataset(includeCoordinates: false);
    await _pumpViewer(tester, dataset: dataset, onApply: (_) async {});

    expect(
      find.byKey(const ValueKey<String>('ica-missing-coordinates')),
      findsWidgets,
    );
    expect(
      find.byKey(const ValueKey<String>('ica-component-traces')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('ica-component-0')));
    await tester.pump();
    expect(find.text('1 excluded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-converged ICA is warned and cannot be applied', (
    WidgetTester tester,
  ) async {
    final Dataset dataset = _icaDataset(converged: false);
    await _pumpViewer(tester, dataset: dataset, onApply: (_) async {});

    expect(
      find.byKey(const ValueKey<String>('ica-nonconvergence-warning')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('ica-component-0')));
    await tester.pump();
    final FilledButton apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('ica-apply')),
    );
    expect(apply.onPressed, isNull);
  });

  test(
    'ICA rejection reconstructs sensors and preserves signal metadata',
    () async {
      final Dataset dataset = _icaDataset();
      final TimeSeriesData activations = dataset.timeSeries!;
      await IcaComponentRejectionNodeType().run(dataset, <String, dynamic>{
        'excludedComponents': <int>[1],
      });

      final TimeSeriesData clean = dataset.timeSeries!;
      expect(clean.channelLabels, <String>['Fz', 'Cz', 'Pz']);
      expect(clean.sampleRate, activations.sampleRate);
      expect(clean.channelCoordinates, contains('Fz'));
      expect(clean.markers, activations.markers);
      expect(clean.factors, activations.factors);
      expect(clean.impedanceData?.channelCount, 3);
      expect(clean.channels[0], <double>[11, 12, 13, 14]);
      expect(clean.channels[1], <double>[20, 20, 20, 20]);
      expect(clean.channels[2], <double>[35, 36, 37, 38]);
      expect(clean.source, contains('IC 2'));
    },
  );

  test(
    'ICA rejection applies its transform to compatible sensor data',
    () async {
      final Dataset dataset = _icaDataset();
      dataset.timeSeries = TimeSeriesData(
        channelSamples: const <List<double>>[
          <double>[11, 12, 13, 14],
          <double>[23, 24, 25, 26],
          <double>[35, 36, 37, 38],
        ],
        sampleRate: 128,
        channelLabels: const <String>['Fz', 'Cz', 'Pz'],
        markers: const <TimeMarker>[
          TimeMarker(onsetMicros: 1000, label: 'target event'),
        ],
        source: 'compatible branch',
      );

      await IcaComponentRejectionNodeType().run(dataset, <String, dynamic>{
        'excludedComponents': <int>[1],
      });

      final TimeSeriesData clean = dataset.timeSeries!;
      expect(clean.channels[0], <double>[11, 12, 13, 14]);
      expect(clean.channels[1], <double>[20, 20, 20, 20]);
      expect(clean.channels[2], <double>[35, 36, 37, 38]);
      expect(clean.markers.single.label, 'target event');
      expect(clean.source, contains('compatible branch'));
    },
  );

  test('ICA rejection leaves channels outside the fit unchanged', () async {
    final Dataset dataset = Dataset('subset-apply');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[11, 12, 13],
        <double>[101, 102, 103],
        <double>[31, 32, 33],
      ],
      sampleRate: 128,
      channelLabels: const <String>['Fz', 'Cz', 'Pz'],
    );
    dataset.matrixTransformation = const MatrixTransformationData(
      matrix: <List<double>>[
        <double>[1, 0],
        <double>[0, 1],
      ],
      unmixingMatrix: <List<double>>[
        <double>[1, 0],
        <double>[0, 1],
      ],
      mixingMatrix: <List<double>>[
        <double>[1, 0],
        <double>[0, 1],
      ],
      channelMeans: <double>[10, 30],
      originalChannelLabels: <String>['Fz', 'Pz'],
      sourceChannelLabels: <String>['Fz', 'Cz', 'Pz'],
      selectedChannelIndices: <int>[0, 2],
      originalSampleRate: 128,
      componentLabels: <String>['IC 1', 'IC 2'],
    );

    await IcaComponentRejectionNodeType().run(dataset, <String, dynamic>{
      'excludedComponents': <int>[0],
    });

    expect(dataset.timeSeries!.channels[0], <double>[10, 10, 10]);
    expect(dataset.timeSeries!.channels[1], <double>[101, 102, 103]);
    expect(dataset.timeSeries!.channels[2], <double>[31, 32, 33]);
  });

  test('ICA rejection refuses incompatible sensor metadata', () async {
    final Dataset dataset = _icaDataset();
    dataset.timeSeries = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[1, 2],
        <double>[3, 4],
        <double>[5, 6],
      ],
      sampleRate: 256,
      channelLabels: const <String>['Fz', 'Pz', 'Cz'],
    );

    await expectLater(
      IcaComponentRejectionNodeType().run(dataset, <String, dynamic>{
        'excludedComponents': <int>[],
      }),
      throwsArgumentError,
    );

    dataset.timeSeries = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[1, 2],
        <double>[3, 4],
        <double>[5, 6],
      ],
      sampleRate: 256,
      channelLabels: const <String>['Fz', 'Cz', 'Pz'],
    );
    await expectLater(
      IcaComponentRejectionNodeType().run(dataset, <String, dynamic>{
        'excludedComponents': <int>[],
      }),
      throwsArgumentError,
    );
  });

  test(
    'applying exclusions creates then updates one downstream graph node',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = _icaDataset();
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(ICANodeType());
      final NodeModel input = logic.nodes[0];
      final NodeModel source = logic.nodes[1];
      input.datasetStates[dataset.id] = DatasetState.done;
      source.datasetStates[dataset.id] = DatasetState.done;
      logic.connections.add(<String, dynamic>{
        'fromNode': input.id,
        'fromPort': 0,
        'toNode': source.id,
        'toPort': 0,
      });

      final String created = await logic.persistIcaComponentExclusions(
        viewerNodeId: source.id,
        dataset: dataset,
        excludedComponents: <int>{0},
        runAfterApply: false,
      );
      final NodeModel rejection = logic.nodes.firstWhere(
        (NodeModel node) => node.type is IcaComponentRejectionNodeType,
      );
      expect(created, 'Created Apply ICA.');
      expect(rejection.params['excludedComponents'], <int>[0]);
      expect(
        logic.connections,
        contains(
          predicate<Map<String, dynamic>>(
            (Map<String, dynamic> connection) =>
                connection['fromNode'] == input.id &&
                connection['fromPort'] == 0 &&
                connection['toNode'] == rejection.id &&
                connection['toPort'] == 0,
          ),
        ),
      );
      expect(
        logic.connections,
        contains(
          predicate<Map<String, dynamic>>(
            (Map<String, dynamic> connection) =>
                connection['fromNode'] == source.id &&
                connection['fromPort'] == 1 &&
                connection['toNode'] == rejection.id &&
                connection['toPort'] == 1,
          ),
        ),
      );

      final String updated = await logic.persistIcaComponentExclusions(
        viewerNodeId: source.id,
        dataset: dataset,
        excludedComponents: <int>{1, 2},
        runAfterApply: false,
      );
      expect(updated, 'Updated Apply ICA.');
      expect(
        logic.nodes.where(
          (NodeModel node) => node.type is IcaComponentRejectionNodeType,
        ),
        hasLength(1),
      );
      expect(rejection.params['excludedComponents'], <int>[1, 2]);
    },
  );

  test('visualization routing recognizes ICA artifacts', () {
    final CanvasLogic logic = CanvasLogic();
    logic.addNode(ICANodeType());
    expect(
      logic.visualizationViewForNodeAndDatasets(logic.nodes.single, <Dataset>[
        _icaDataset(),
      ]),
      'ica',
    );
  });
}

Future<void> _pumpViewer(
  WidgetTester tester, {
  required Dataset dataset,
  required Future<void> Function(Set<int>) onApply,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: IcaViewer(dataset: dataset, onApply: onApply),
        ),
      ),
    ),
  );
  await tester.pump();
}

Dataset _icaDataset({bool includeCoordinates = true, bool converged = true}) {
  final Dataset dataset = Dataset('ica-dataset', label: 'ICA example');
  const List<String> sensorLabels = <String>['Fz', 'Cz', 'Pz'];
  const List<String> componentLabels = <String>['IC 1', 'IC 2', 'IC 3'];
  const Map<String, ChannelCoordinate> coordinates =
      <String, ChannelCoordinate>{
        'Fz': ChannelCoordinate(label: 'Fz', x: 0, y: 0.7, z: 0.7),
        'Cz': ChannelCoordinate(label: 'Cz', x: 0, y: 0, z: 1),
        'Pz': ChannelCoordinate(label: 'Pz', x: 0, y: -0.7, z: 0.7),
      };
  dataset.timeSeries = TimeSeriesData(
    channelSamples: const <List<double>>[
      <double>[1, 2, 3, 4],
      <double>[3, 4, 5, 6],
      <double>[5, 6, 7, 8],
    ],
    sampleRate: 128,
    channelLabels: componentLabels,
    markers: const <TimeMarker>[TimeMarker(onsetMicros: 1000, label: 'event')],
    factors: const <Factor>[Factor(name: 'condition')],
    source: 'synthetic -> ICA',
  );
  dataset.matrixTransformation = MatrixTransformationData(
    matrix: const <List<double>>[
      <double>[1, 0, 0],
      <double>[0, 1, 0],
      <double>[0, 0, 1],
    ],
    unmixingMatrix: const <List<double>>[
      <double>[1, 0, 0],
      <double>[0, 1, 0],
      <double>[0, 0, 1],
    ],
    mixingMatrix: const <List<double>>[
      <double>[1, 0, 0],
      <double>[0, 1, 0],
      <double>[0, 0, 1],
    ],
    channelMeans: const <double>[10, 20, 30],
    originalChannelLabels: sensorLabels,
    originalSampleRate: 128,
    originalChannelCoordinates: includeCoordinates
        ? coordinates
        : const <String, ChannelCoordinate>{},
    originalImpedanceData: ImpedanceData(
      channelLabels: sensorLabels,
      measurementTimesMicros: const <int>[0],
      ohmsByChannel: const <List<double?>>[
        <double?>[5000],
        <double?>[6000],
        <double?>[7000],
      ],
    ),
    componentLabels: componentLabels,
    componentEnergies: const <double>[0.5, 0.3, 0.2],
    algorithm: 'FastICA',
    converged: converged,
    iterationCount: converged ? 12 : 200,
    tolerance: 0.0001,
    maxIterations: 200,
    seed: 42,
  );
  return dataset;
}
