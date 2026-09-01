import 'dart:math' as math;

import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_state.dart';
import 'package:brainstory_gui/model/node.dart';
import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/nodes/matrix_transform_nodes.dart';
import 'package:brainstory_gui/nodes/node_registry.dart';
import 'package:brainstory_gui/ui/canvas_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ICA node emits components and reconstruction-ready metadata', () async {
    const int sampleCount = 2048;
    const double sampleRate = 256.0;
    final List<List<double>> sources = <List<double>>[
      List<double>.generate(
        sampleCount,
        (int index) => math.sin(2 * math.pi * 3.0 * index / sampleRate),
      ),
      List<double>.generate(
        sampleCount,
        (int index) =>
            math.sin(2 * math.pi * 5.0 * index / sampleRate) >= 0 ? 1 : -1,
      ),
      List<double>.generate(
        sampleCount,
        (int index) => ((index * 37 % 101) - 50) / 50.0,
      ),
    ];
    const List<List<double>> mixing = <List<double>>[
      <double>[1.0, 0.5, 0.2],
      <double>[0.3, 1.2, 0.4],
      <double>[0.2, 0.1, 0.9],
    ];
    const List<double> means = <double>[10.0, -4.0, 2.0];
    final List<List<double>> channels = List<List<double>>.generate(3, (
      int channel,
    ) {
      return List<double>.generate(sampleCount, (int sample) {
        return means[channel] +
            List<int>.generate(3, (int index) => index)
                .map(
                  (int source) =>
                      mixing[channel][source] * sources[source][sample],
                )
                .reduce((double left, double right) => left + right);
      }, growable: false);
    }, growable: false);
    final Dataset dataset = Dataset('ica-test');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: channels,
      sampleRate: sampleRate,
      channelLabels: const <String>['Fz', 'Cz', 'Pz'],
      channelCoordinates: const <String, ChannelCoordinate>{
        'Fz': ChannelCoordinate(label: 'Fz', x: 0, y: 0.6, z: 0.8),
      },
      impedanceData: ImpedanceData(
        channelLabels: const <String>['Fz', 'Cz', 'Pz'],
        measurementTimesMicros: const <int>[0],
        ohmsByChannel: const <List<double?>>[
          <double?>[5000],
          <double?>[6000],
          <double?>[7000],
        ],
      ),
      source: 'synthetic',
    );

    await ICANodeType().run(dataset, ICANodeType().defaultParams);

    final TimeSeriesData components = dataset.timeSeries!;
    final MatrixTransformationData transform = dataset.matrixTransformation!;
    expect(components.channelLabels, <String>['IC 1', 'IC 2', 'IC 3']);
    expect(components.channels, hasLength(3));
    expect(transform.algorithm, contains('FastICA'));
    expect(transform.converged, isTrue);
    expect(transform.unmixingMatrix, hasLength(3));
    expect(transform.mixingMatrix, hasLength(3));
    expect(transform.originalChannelLabels, <String>['Fz', 'Cz', 'Pz']);
    expect(transform.originalSampleRate, sampleRate);
    expect(transform.originalChannelCoordinates, contains('Fz'));
    expect(transform.originalImpedanceData?.channelCount, 3);
    expect(
      transform.componentEnergies.reduce((double a, double b) => a + b),
      closeTo(1.0, 1.0e-10),
    );

    final List<List<double>> reconstructed = transform
        .reconstructSensorChannels(components.channels);
    double maximumError = 0.0;
    for (int channel = 0; channel < channels.length; channel++) {
      for (int sample = 0; sample < sampleCount; sample++) {
        maximumError = math.max(
          maximumError,
          (reconstructed[channel][sample] - channels[channel][sample]).abs(),
        );
      }
    }
    expect(maximumError, lessThan(1.0e-8));
  });

  test('ICA transformation survives JSON round trip', () {
    const MatrixTransformationData original = MatrixTransformationData(
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
      channelMeans: <double>[3, 4],
      originalChannelLabels: <String>['A', 'B'],
      sourceChannelLabels: <String>['A', 'B', 'C'],
      selectedChannelIndices: <int>[0, 1],
      originalSampleRate: 256,
      componentLabels: <String>['IC 1', 'IC 2'],
      componentEnergies: <double>[0.7, 0.3],
      algorithm: 'FastICA',
      converged: true,
      iterationCount: 12,
      numericalRank: 2,
      tolerance: 0.0001,
      maxIterations: 200,
      seed: 42,
      fitScope: 'markers',
      fitSampleCount: 512,
      fitMarkerLabels: <String>['blink'],
    );

    final MatrixTransformationData decoded = MatrixTransformationData.fromJson(
      original.toJson(),
    );
    expect(decoded.mixingMatrix, original.mixingMatrix);
    expect(decoded.channelMeans, original.channelMeans);
    expect(decoded.originalSampleRate, 256);
    expect(decoded.sourceChannelLabels, <String>['A', 'B', 'C']);
    expect(decoded.selectedChannelIndices, <int>[0, 1]);
    expect(decoded.fitScope, 'markers');
    expect(decoded.fitSampleCount, 512);
    expect(decoded.fitMarkerLabels, <String>['blink']);
    expect(decoded.algorithm, 'FastICA');
    expect(decoded.converged, isTrue);
    expect(decoded.iterationCount, 12);
  });

  test('ICA fits a middle portion on selected channels', () async {
    final Dataset dataset = _scopedIcaDataset();
    await ICANodeType().run(dataset, <String, dynamic>{
      ...ICANodeType().defaultParams,
      'fitScope': 'portion',
      'portionAnchor': 'middle',
      'portionDurationSeconds': 2.0,
      'channelMode': 'selected',
      'selectedChannelLabels': <String>['Fz', 'Pz'],
    });

    final MatrixTransformationData transform = dataset.matrixTransformation!;
    expect(transform.fitScope, 'portion');
    expect(transform.fitSampleCount, 512);
    expect(transform.sourceChannelLabels, <String>['Fz', 'Cz', 'Pz']);
    expect(transform.originalChannelLabels, <String>['Fz', 'Pz']);
    expect(transform.selectedChannelIndices, <int>[0, 2]);
    expect(dataset.timeSeries!.channelCount, 2);
    expect(dataset.timeSeries!.sampleCount, 2048);
  });

  test('ICA concatenates selected marker windows for fitting', () async {
    final Dataset dataset = _scopedIcaDataset(
      markers: const <TimeMarker>[
        TimeMarker(onsetMicros: 1000000, label: 'blink'),
        TimeMarker(onsetMicros: 2500000, label: 'blink'),
        TimeMarker(onsetMicros: 3000000, label: 'other'),
      ],
    );
    await ICANodeType().run(dataset, <String, dynamic>{
      ...ICANodeType().defaultParams,
      'fitScope': 'markers',
      'markerLabels': <String>['blink'],
      'markerPreSeconds': 0.25,
      'markerPostSeconds': 0.25,
    });

    final MatrixTransformationData transform = dataset.matrixTransformation!;
    expect(transform.fitScope, 'markers');
    expect(transform.fitMarkerLabels, <String>['blink']);
    expect(transform.fitSampleCount, 256);
    expect(dataset.timeSeries!.sampleCount, 2048);
  });

  test('ICA validates multichannel input', () async {
    final Dataset dataset = Dataset('single-channel');
    dataset.timeSeries = TimeSeriesData(
      samples: List<double>.generate(128, (int index) => index.toDouble()),
      sampleRate: 128,
    );
    await expectLater(
      ICANodeType().run(dataset, ICANodeType().defaultParams),
      throwsArgumentError,
    );
  });

  test(
    'ICA graph execution produces a distinct result for every dataset',
    () async {
      final CanvasLogic logic = CanvasLogic(runUiYieldsEnabled: false);
      final Dataset first = _scopedIcaDataset(id: 'ica-a');
      final Dataset second = _scopedIcaDataset(id: 'ica-b');
      logic.datasets[first.id] = first;
      logic.datasets[second.id] = second;
      logic.addNode(ImportNodeType());
      logic.addNode(ICANodeType());
      final NodeModel input = logic.nodes[0];
      final NodeModel ica = logic.nodes[1];
      for (final Dataset dataset in <Dataset>[first, second]) {
        input.datasetStates[dataset.id] = DatasetState.done;
        ica.datasetStates[dataset.id] = DatasetState.ready;
      }
      logic.connections.add(<String, dynamic>{
        'fromNode': input.id,
        'fromPort': 0,
        'toNode': ica.id,
        'toPort': 0,
      });

      await logic.runThisStep(ica.id);

      expect(ica.datasetStates[first.id], DatasetState.done);
      expect(ica.datasetStates[second.id], DatasetState.done);
      final Dataset firstView = await logic.materializedDatasetViewForNode(
        ica.id,
        first,
      );
      final Dataset secondView = await logic.materializedDatasetViewForNode(
        ica.id,
        second,
      );
      expect(firstView.matrixTransformation, isNotNull);
      expect(secondView.matrixTransformation, isNotNull);
      expect(
        firstView.timeSeries!.channelLabels,
        everyElement(startsWith('IC ')),
      );
      expect(
        secondView.timeSeries!.channelLabels,
        everyElement(startsWith('IC ')),
      );
    },
  );

  test('ICA is visible in the node registry', () {
    final NodeRegistryEntry entry = NodeRegistry.entries.firstWhere(
      (NodeRegistryEntry candidate) => candidate.create() is ICANodeType,
    );
    expect(entry.visible, isTrue);
    expect(ICANodeType().defaultParams, containsPair('fitScope', 'whole'));
    expect(ICANodeType().defaultParams, containsPair('channelMode', 'all'));
  });

  testWidgets('ICA parameters expose fit scope and channel selection', (
    WidgetTester tester,
  ) async {
    final Dataset dataset = _scopedIcaDataset(
      markers: const <TimeMarker>[
        TimeMarker(onsetMicros: 1000000, label: 'blink'),
      ],
    );
    final Map<String, dynamic> params = ICANodeType().defaultParams;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return ICANodeType().buildBody(
                  params,
                  datasets: <String, Dataset>{dataset.id: dataset},
                  setState: setState,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Whole'), findsOneWidget);
    expect(find.text('Portion'), findsOneWidget);
    expect(find.text('Markers'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);

    await tester.tap(find.text('Markers'));
    await tester.pump();
    expect(find.text('blink'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Before (seconds)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'After (seconds)'), findsOneWidget);

    await tester.tap(find.text('Selected'));
    await tester.pump();
    expect(find.text('Fz'), findsOneWidget);
    expect(find.text('Cz'), findsOneWidget);
    expect(find.text('Pz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Dataset _scopedIcaDataset({
  String id = 'scoped-ica',
  List<TimeMarker> markers = const <TimeMarker>[],
}) {
  const int sampleCount = 2048;
  const double sampleRate = 256.0;
  final Dataset dataset = Dataset(id);
  dataset.timeSeries = TimeSeriesData(
    channelSamples: <List<double>>[
      List<double>.generate(
        sampleCount,
        (int index) => math.sin(2 * math.pi * 3 * index / sampleRate),
      ),
      List<double>.generate(
        sampleCount,
        (int index) =>
            math.sin(2 * math.pi * 5 * index / sampleRate) +
            0.2 * math.sin(2 * math.pi * 3 * index / sampleRate),
      ),
      List<double>.generate(
        sampleCount,
        (int index) =>
            ((index * 37 % 101) - 50) / 50 +
            0.1 * math.sin(2 * math.pi * 3 * index / sampleRate),
      ),
    ],
    sampleRate: sampleRate,
    channelLabels: const <String>['Fz', 'Cz', 'Pz'],
    markers: markers,
    source: 'scoped synthetic',
  );
  return dataset;
}
