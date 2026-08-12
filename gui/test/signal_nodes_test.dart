import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_artifact_snapshot.dart';
import 'package:brainstory_gui/model/dataset_state.dart';
import 'package:brainstory_gui/model/node.dart';
import 'package:brainstory_gui/nodes/add_remove_markers_node.dart';
import 'package:brainstory_gui/nodes/bandpass_node.dart';
import 'package:brainstory_gui/nodes/bridge_detector_node.dart';
import 'package:brainstory_gui/nodes/channel_coordinates_node.dart';
import 'package:brainstory_gui/nodes/amplitude_features_node.dart';
import 'package:brainstory_gui/nodes/edit_channels_node.dart';
import 'package:brainstory_gui/nodes/edit_channels_and_markers_node.dart';
import 'package:brainstory_gui/nodes/export_edf_node.dart';
import 'package:brainstory_gui/nodes/eye_blinks_node.dart';
import 'package:brainstory_gui/nodes/fooof_node.dart';
import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/nodes/impedances_node.dart';
import 'package:brainstory_gui/nodes/interactive_artifact_detection_node.dart';
import 'package:brainstory_gui/nodes/machine_learning_nodes.dart';
import 'package:brainstory_gui/nodes/node_type.dart';
import 'package:brainstory_gui/nodes/psd_average_node.dart';
import 'package:brainstory_gui/nodes/psd_node.dart';
import 'package:brainstory_gui/nodes/recode_markers_node.dart';
import 'package:brainstory_gui/nodes/realign_node.dart';
import 'package:brainstory_gui/nodes/resample_node.dart';
import 'package:brainstory_gui/nodes/segmentation_node.dart';
import 'package:brainstory_gui/nodes/sleep_staging_node.dart';
import 'package:brainstory_gui/nodes/spectral_features_node.dart';
import 'package:brainstory_gui/nodes/visualization_node.dart';
import 'package:brainstory_gui/platform/ant_cnt_import.dart';
import 'package:brainstory_gui/ui/canvas_logic.dart';
import 'package:brainstory_gui/ui/canvas_view.dart';
import 'package:brainstory_gui/ui/visualization_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canvas undo reverses node creation', () {
    final CanvasLogic logic = CanvasLogic();

    logic.addNode(ImportNodeType());

    expect(logic.nodes, hasLength(1));
    expect(logic.canUndo, isTrue);
    expect(logic.undoLast(), 'add Import');
    expect(logic.nodes, isEmpty);
  });

  test('consecutive channel and marker edits combine into one node', () {
    final CanvasLogic logic = CanvasLogic();
    logic.addNode(EditChannelsNodeType());
    final NodeModel channelNode = logic.nodes.last;
    channelNode.params['channelEditsByDataset'] = <String, dynamic>{
      'dataset-1': <String, dynamic>{
        'edits': <String, dynamic>{
          '0': <String, dynamic>{'rename': 'Fp1 edited'},
        },
      },
    };
    logic.addNode(AddRemoveMarkersNodeType());
    final NodeModel markerNode = logic.nodes.last;
    markerNode.params['markers'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'datasetId': 'dataset-1',
        'label': 'blink',
        'onsetMicros': 1000,
        'durationMicros': 0,
        'markerType': MarkerType.event,
      },
    ];
    markerNode.params['applyEmptyMarkerSet'] = true;
    logic.connections.add(<String, dynamic>{
      'fromNode': channelNode.id,
      'fromPort': 0,
      'toNode': markerNode.id,
      'toPort': 0,
    });

    expect(
      logic.combineConsecutiveEditNodes(channelNode.id, markerNode.id),
      'Edit Channels and Markers',
    );

    expect(logic.nodes, hasLength(1));
    expect(logic.nodes.single.type, isA<EditChannelsAndMarkersNodeType>());
    expect(
      logic.nodes.single.params['channelEditsByDataset'],
      contains('dataset-1'),
    );
    expect(logic.nodes.single.params['markers'], hasLength(1));
    expect(logic.nodes.single.params['applyEmptyMarkerSet'], isTrue);
    expect(logic.connections, isEmpty);

    expect(logic.undoLast(), 'combine edit nodes');
    expect(logic.nodes, hasLength(2));
    expect(logic.connections, hasLength(1));
  });

  test(
    'all graph nodes can open the visualizer without an interactive node',
    () {
      final CanvasLogic logic = CanvasLogic();

      logic.addNode(ImportNodeType());

      expect(logic.canVisualizeNode(logic.nodes.single), isTrue);
      expect(logic.hasVisualizationOutput(logic.nodes.single), isFalse);
      logic.nodes.single.datasetStates['dataset-1'] = DatasetState.done;
      expect(logic.hasVisualizationOutput(logic.nodes.single), isTrue);
      expect(
        logic.availableNodes.map((NodeType type) => type.title),
        isNot(contains('Interactive Artifact Detection')),
      );
    },
  );

  test('run UI records recent jobs when a run finishes', () {
    final CanvasLogic logic = CanvasLogic();

    logic.runActivity.value = const RunActivity(
      label: 'Running Import',
      detail: 'Preparing run state...',
    );
    logic.finishRunUi(succeeded: true, detail: 'Ran Import for 1 dataset(s).');

    expect(logic.runActivity.value, isNull);
    expect(logic.recentRunJobs.value, hasLength(1));
    expect(logic.recentRunJobs.value.first.label, 'Running Import');
    expect(
      logic.recentRunJobs.value.first.detail,
      'Ran Import for 1 dataset(s).',
    );
    expect(logic.recentRunJobs.value.first.state, RunJobState.done);
  });

  testWidgets('canvas shows preparing work without modal lock', (
    WidgetTester tester,
  ) async {
    final CanvasLogic logic = CanvasLogic();
    logic.runActivity.value = const RunActivity(
      label: 'Running PSD',
      detail: 'Preparing data flow...',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CanvasView(logic: logic)),
      ),
    );

    expect(find.text('Running PSD'), findsOneWidget);
    expect(find.text('Preparing'), findsOneWidget);
    expect(find.text('Initializing resources'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is ModalBarrier &&
            widget.semanticsLabel == 'BrainStory is busy',
      ),
      findsNothing,
    );
  });

  testWidgets('canvas keeps active processing visible without modal lock', (
    WidgetTester tester,
  ) async {
    final CanvasLogic logic = CanvasLogic();
    logic.runActivity.value = const RunActivity(
      label: 'Running PSD',
      detail: 'Running PSD on PVT.set...',
      phase: RunActivityPhase.running,
    );
    logic.queuedRunJobs.value = const <RunJobEntry>[
      RunJobEntry(
        label: 'Running Segmentation',
        detail: 'Waiting for the current job to finish.',
        state: RunJobState.queued,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CanvasView(logic: logic)),
      ),
    );

    expect(find.text('Running PSD'), findsOneWidget);
    expect(find.text('Running Segmentation'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is ModalBarrier &&
            widget.semanticsLabel == 'BrainStory is busy',
      ),
      findsNothing,
    );
  });

  test('run queue serializes jobs and publishes queued work', () async {
    final CanvasLogic logic = CanvasLogic(runUiYieldsEnabled: false);
    final Completer<void> releaseFirst = Completer<void>();
    final List<String> order = <String>[];
    Future<void> flushRunQueue() async {
      for (int flush = 0; flush < 12; flush++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final Future<String> first = logic.runQueued(
      label: 'First job',
      action: () async {
        order.add('first-start');
        await logic.setRunDetail(
          'Running first job...',
          phase: RunActivityPhase.running,
        );
        await releaseFirst.future;
        order.add('first-end');
      },
      successDetail: () => 'First complete.',
    );

    await flushRunQueue();
    expect(order, <String>['first-start']);
    expect(logic.runActivity.value?.phase, RunActivityPhase.running);

    final Future<String> second = logic.runQueued(
      label: 'Second job',
      action: () async {
        order.add('second-start');
        await logic.setRunDetail(
          'Running second job...',
          phase: RunActivityPhase.running,
        );
      },
      successDetail: () => 'Second complete.',
    );

    expect(logic.queuedRunJobs.value, hasLength(1));
    expect(logic.queuedRunJobs.value.single.label, 'Second job');

    releaseFirst.complete();
    await flushRunQueue();

    expect(await first, 'First complete.');
    expect(await second, 'Second complete.');
    expect(order, <String>['first-start', 'first-end', 'second-start']);
    expect(logic.queuedRunJobs.value, isEmpty);
    expect(logic.recentRunJobs.value.first.label, 'Second job');
  });

  test(
    'removeDataset removes project dataset state and cached references',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset keep = Dataset('keep', label: 'Keep');
      final Dataset drop = Dataset('drop', label: 'Drop');
      logic.datasets['keep-path'] = keep;
      logic.datasets['drop-path'] = drop;

      logic.addNode(ImportNodeType());
      final NodeModel importNode = logic.nodes.single;
      importNode.params['selectedDatasetIds'] = <String>[keep.id, drop.id];
      importNode.params['datasetAliases'] = <String, dynamic>{
        keep.id: 'Keep alias',
        drop.id: 'Drop alias',
      };
      importNode.datasetStates[keep.id] = DatasetState.ready;
      importNode.datasetStates[drop.id] = DatasetState.done;

      await logic.removeDataset(drop.id);

      expect(
        logic.datasets.values.map((Dataset dataset) => dataset.id),
        <String>[keep.id],
      );
      expect(importNode.datasetStates.containsKey(drop.id), isFalse);
      expect(importNode.params['selectedDatasetIds'], <String>[keep.id]);
      expect(
        (importNode.params['datasetAliases'] as Map<String, dynamic>)
            .containsKey(drop.id),
        isFalse,
      );
    },
  );

  test(
    'node visual state becomes partial when some available datasets are done',
    () {
      final NodeModel node = NodeModel(
        id: 'node-1',
        type: ImportNodeType(),
        position: const Offset(0, 0),
        params: <String, dynamic>{},
      );

      node.datasetStates['dataset-a'] = DatasetState.done;
      node.datasetStates['dataset-b'] = DatasetState.ready;
      node.datasetStates['dataset-c'] = DatasetState.notReady;

      expect(node.visualState, DatasetState.partial);

      node.datasetStates['dataset-b'] = DatasetState.done;
      expect(node.visualState, DatasetState.done);
    },
  );

  test(
    'node descriptors assign branch letters only within split-rejoin regions',
    () {
      final CanvasLogic logic = CanvasLogic();
      logic.addNode(ImportNodeType());
      logic.addNode(BandpassNodeType());
      logic.addNode(PSDNodeType());
      logic.addNode(VisualizationNodeType());

      final NodeModel importNode = logic.nodes[0]
        ..position = const Offset(0, 0);
      final NodeModel leftBranchNode = logic.nodes[1]
        ..position = const Offset(-120, 140);
      final NodeModel rightBranchNode = logic.nodes[2]
        ..position = const Offset(120, 140);
      final NodeModel mergeNode = logic.nodes[3]
        ..position = const Offset(0, 280);

      logic.connections.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': leftBranchNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': rightBranchNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': leftBranchNode.id,
          'fromPort': 0,
          'toNode': mergeNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': rightBranchNode.id,
          'fromPort': 0,
          'toNode': mergeNode.id,
          'toPort': 0,
        },
      ]);

      expect(logic.descriptorForNode(importNode), '#1A Import');
      expect(logic.descriptorForNode(leftBranchNode), '#2A Bandpass Filter');
      expect(logic.descriptorForNode(rightBranchNode), '#3B PSD');
      expect(logic.descriptorForNode(mergeNode), '#4A EEG Visualization');
    },
  );

  test(
    'visualization source refs keep same dataset distinct across pathways',
    () async {
      final CanvasLogic logic = CanvasLogic();
      logic.addNode(ImportNodeType());
      logic.addNode(BandpassNodeType());
      logic.addNode(VisualizationNodeType());

      final NodeModel importNode = logic.nodes[0];
      final NodeModel bandpassNode = logic.nodes[1];
      final NodeModel visualizationNode = logic.nodes[2];

      logic.connections.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': bandpassNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': visualizationNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': bandpassNode.id,
          'fromPort': 0,
          'toNode': visualizationNode.id,
          'toPort': 0,
        },
      ]);

      final Dataset dataset = Dataset('dataset-1', label: 'PVT.set');
      dataset.path = 'C:\\raw\\PVT.set';
      dataset.ram['source.filename'] = 'PVT.set';
      dataset.timeSeries = TimeSeriesData(
        samples: const <double>[0.0, 1.0, 0.5, -0.5],
        sampleRate: 1000.0,
        source: 'synthetic_signal',
      );
      logic.datasets[dataset.label] = dataset;
      importNode.datasetStates[dataset.id] = DatasetState.done;
      bandpassNode.datasetStates[dataset.id] = DatasetState.done;

      final List<VisualizationSourceRef> refs = logic
          .visualizationSourceRefsForNode(visualizationNode.id);
      expect(refs, hasLength(2));
      expect(
        refs.map((VisualizationSourceRef ref) => ref.datasetId).toSet(),
        <String>{dataset.id},
      );
      expect(
        refs
            .map((VisualizationSourceRef ref) => ref.materializeFromNodeId)
            .toSet(),
        <String>{importNode.id, bandpassNode.id},
      );
      expect(
        refs
            .map((VisualizationSourceRef ref) => ref.sourceDescriptor)
            .toSet()
            .length,
        2,
      );

      final List<Dataset> views = await logic
          .materializedDatasetViewsForSourceRefs(refs);
      expect(views, hasLength(2));
      expect(
        views
            .map((Dataset view) => view.ram['viewer.sourceKey'])
            .toSet()
            .length,
        2,
      );
      expect(
        views.every(
          (Dataset view) =>
              view.label.contains('[') && view.label.contains(']'),
        ),
        isTrue,
      );
      expect(views.every((Dataset view) => view.timeSeries != null), isTrue);
      expect(views.every((Dataset view) => view.path.isEmpty), isTrue);
      expect(
        views.every((Dataset view) => !view.ram.containsKey('source.filename')),
        isTrue,
      );
    },
  );

  testWidgets('visualization surface starts with no datasets selected', (
    WidgetTester tester,
  ) async {
    final CanvasLogic logic = CanvasLogic();
    logic.addNode(ImportNodeType());
    logic.addNode(VisualizationNodeType());

    final NodeModel importNode = logic.nodes[0];
    final NodeModel visualizationNode = logic.nodes[1];
    logic.connections.add(<String, dynamic>{
      'fromNode': importNode.id,
      'fromPort': 0,
      'toNode': visualizationNode.id,
      'toPort': 0,
    });

    final Dataset dataset = Dataset('dataset-1', label: 'PVT.set');
    dataset.timeSeries = TimeSeriesData(
      samples: const <double>[0.0, 1.0, 0.5, -0.5],
      sampleRate: 1000.0,
      source: 'synthetic_signal',
    );
    logic.datasets[dataset.label] = dataset;
    importNode.datasetStates[dataset.id] = DatasetState.done;

    final VisualizationSourceRef sourceRef = logic
        .visualizationSourceRefsForNode(visualizationNode.id)
        .single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualizationSurface(
            logic: logic,
            nodeId: visualizationNode.id,
            onChanged: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No dataset selected'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.widgetWithText(FilterChip, sourceRef.displayLabel),
          )
          .selected,
      isFalse,
    );
  });

  test('impedance visualization selects imported impedance datasets', () {
    final CanvasLogic logic = CanvasLogic();
    logic.addNode(ImpedancesNodeType());
    final NodeModel node = logic.nodes.single;
    final Dataset dataset = Dataset('dataset-1', label: 'PVT');
    dataset.timeSeries = TimeSeriesData(
      samples: const <double>[0.0],
      sampleRate: 256.0,
      channelLabels: const <String>['Cz'],
      impedanceData: ImpedanceData(
        channelLabels: const <String>['Cz'],
        measurementTimesMicros: const <int>[0, 2000000],
        ohmsByChannel: const <List<double?>>[
          <double?>[10000.0, 12000.0],
        ],
      ),
    );
    logic.datasets[dataset.id] = dataset;
    node.datasetStates[dataset.id] = DatasetState.done;

    expect(
      logic.visualizationViewForNodeAndDatasets(node, <Dataset>[dataset]),
      'impedances',
    );
    expect(logic.visualizationSourceRefsForNode(node.id), hasLength(1));
  });

  testWidgets('impedance visualization exposes scientific display controls', (
    WidgetTester tester,
  ) async {
    final CanvasLogic logic = CanvasLogic();
    logic.addNode(ImpedancesNodeType());
    final NodeModel node = logic.nodes.single;
    final Dataset dataset = Dataset('dataset-1', label: 'PVT');
    dataset.timeSeries = TimeSeriesData(
      samples: const <double>[0.0],
      sampleRate: 256.0,
      channelLabels: const <String>['Cz'],
      impedanceData: ImpedanceData(
        channelLabels: const <String>['Cz'],
        measurementTimesMicros: const <int>[0, 2000000],
        ohmsByChannel: const <List<double?>>[
          <double?>[10000.0, 12000.0],
        ],
      ),
    );
    logic.datasets[dataset.id] = dataset;
    node.datasetStates[dataset.id] = DatasetState.done;
    final VisualizationSourceRef sourceRef = logic
        .visualizationSourceRefsForNode(node.id)
        .single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualizationSurface(
            logic: logic,
            nodeId: node.id,
            onChanged: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, sourceRef.displayLabel));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Channel: Cz'), findsOneWidget);
    expect(find.text('Quantity: Impedance'), findsOneWidget);
    expect(find.text('Y Axis: Linear'), findsOneWidget);
    expect(find.text('Line: Straight'), findsOneWidget);

    await tester.tap(find.text('Quantity: Impedance'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Admittance'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(node.params['impedance_quantity'], 'admittance');
    expect(find.text('Quantity: Admittance'), findsOneWidget);
  });

  testWidgets('node dialog exposes its save and run callback', (
    WidgetTester tester,
  ) async {
    final ImpedancesNodeType nodeType = ImpedancesNodeType();
    Map<String, dynamic>? runParams;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => nodeType.buildConfigWidget(
                    Map<String, dynamic>.from(nodeType.defaultParams),
                    (_) {},
                    onSaveAndRun: (Map<String, dynamic> params) {
                      runParams = params;
                    },
                    datasets: const <String, Dataset>{},
                    availableDatasetIds: const <String>{},
                    datasetSourceLabels: const <String, List<String>>{},
                    processedDatasetStates: const <String, DatasetState>{},
                    portStatusSummary: const NodePortStatusSummary(
                      inputs: <NodePortDatasetSummary>[],
                      outputs: <NodePortDatasetSummary>[],
                    ),
                    processingSteps: const <String>[],
                  ),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.text('Save & Run'), findsOneWidget);

    await tester.tap(find.text('Save & Run'));
    await tester.pumpAndSettle();

    expect(runParams, isNotNull);
    expect(runParams!['impedance_quantity'], 'impedance');
    expect(runParams!['impedance_line_mode'], 'line');
  });

  test('artifact identity and change sets serialize cleanly', () {
    const ArtifactIdentity identity = ArtifactIdentity(
      artifactId: 'artifact-node-2-dataset-1-signal',
      datasetId: 'dataset-1',
      kind: BrainStoryArtifactKind.timeSeries,
      producerNodeId: 'node-2',
      sourceArtifactIds: <String>['artifact-node-1-dataset-1-signal'],
      revision: 3,
    );
    const ArtifactChangeSet changeSet = ArtifactChangeSet(
      datasetId: 'dataset-1',
      sourceNodeId: 'node-3',
      changeTypes: <ArtifactChangeType>{
        ArtifactChangeType.channelTopology,
        ArtifactChangeType.channelLabels,
      },
      artifactIds: <String>['artifact-node-2-dataset-1-signal'],
      affectedChannelLabels: <String>['Cz'],
      affectedChannelIndices: <int>[1],
      description: 'Removed Cz',
    );

    final ArtifactIdentity restoredIdentity = ArtifactIdentity.fromJson(
      identity.toJson(),
    );
    final ArtifactChangeSet restoredChangeSet = ArtifactChangeSet.fromJson(
      changeSet.toJson(),
    );

    expect(restoredIdentity.artifactId, identity.artifactId);
    expect(restoredIdentity.kind, BrainStoryArtifactKind.timeSeries);
    expect(
      restoredIdentity.sourceArtifactIds.single,
      'artifact-node-1-dataset-1-signal',
    );
    expect(restoredChangeSet.touchesChannelTopology, isTrue);
    expect(restoredChangeSet.touchesSamples, isFalse);
    expect(restoredChangeSet.isChannelScoped, isTrue);
  });

  test('dataset artifact snapshots preserve artifact identities', () {
    final Dataset dataset = Dataset('dataset-1', label: 'Example');
    dataset.timeSeries = TimeSeriesData(
      samples: <double>[1, 2, 3],
      sampleRate: 1000,
      channelLabels: <String>['Cz'],
    );
    dataset.setArtifactIdentity(
      const ArtifactIdentity(
        artifactId: 'node-1-dataset-1-time-series',
        datasetId: 'dataset-1',
        kind: BrainStoryArtifactKind.timeSeries,
        producerNodeId: 'node-1',
      ),
    );

    final DatasetArtifactSnapshot snapshot =
        DatasetArtifactSnapshot.fromDataset(dataset);
    final DatasetArtifactSnapshot restored = DatasetArtifactSnapshot.fromJson(
      snapshot.toJson(),
    );
    final Dataset target = Dataset('dataset-1', label: 'Target');

    restored.applyToDataset(target);

    expect(
      restored
          .artifactIdentities[BrainStoryArtifactKind.timeSeries]!
          .artifactId,
      'node-1-dataset-1-time-series',
    );
    expect(
      target
          .artifactIdentityFor(BrainStoryArtifactKind.timeSeries)!
          .producerNodeId,
      'node-1',
    );
    expect(target.timeSeries!.sampleRate, 1000);
  });

  test('channel edit change sets describe topology changes', () {
    final TimeSeriesData timeSeries = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[1, 2, 3],
        <double>[4, 5, 6],
      ],
      sampleRate: 1000,
      channelLabels: const <String>['Fz', 'Cz'],
    );
    final ArtifactChangeSet changeSet = EditChannelsNodeType.changeSetForConfig(
      datasetId: 'dataset-1',
      timeSeries: timeSeries,
      config: <String, dynamic>{
        'edits': <String, dynamic>{
          '1': <String, dynamic>{'remove': true, 'removeMode': 'delete'},
        },
      },
    );

    expect(changeSet.touchesChannelTopology, isTrue);
    expect(changeSet.touchesSamples, isTrue);
    expect(changeSet.affectedChannelLabels, <String>['Cz']);
    expect(changeSet.affectedChannelIndices, <int>[1]);
  });

  test('channel deletion stays bound to its original label', () {
    final TimeSeriesData source = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[1, 2, 3],
        <double>[4, 5, 6],
        <double>[7, 8, 9],
      ],
      sampleRate: 1000,
      channelLabels: const <String>['Fz', 'Cz', 'Pz'],
    );
    final Map<String, dynamic> config =
        EditChannelsNodeType.bindConfigToChannelLabels(<String, dynamic>{
          'edits': <String, dynamic>{
            '1': <String, dynamic>{'remove': true, 'removeMode': 'delete'},
          },
        }, source.channelLabels);

    final TimeSeriesData first = EditChannelsNodeType.applyChannelEdits(
      source,
      config,
    );
    final TimeSeriesData second = EditChannelsNodeType.applyChannelEdits(
      first,
      config,
    );

    expect(first.channelLabels, <String>['Fz', 'Pz']);
    expect(second.channelLabels, <String>['Fz', 'Pz']);
    expect(second.channels, first.channels);
  });

  test('channel removal marks downstream signal nodes stale', () async {
    final CanvasLogic logic = CanvasLogic();
    final Dataset dataset = Dataset('dataset-1', label: 'Example');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[1, 2, 3],
        <double>[4, 5, 6],
        <double>[7, 8, 9],
      ],
      sampleRate: 1000,
      channelLabels: const <String>['Fz', 'Cz', 'Pz'],
    );
    logic.datasets[dataset.id] = dataset;
    logic.addNode(ImportNodeType());
    logic.addNode(EditChannelsNodeType());
    logic.addNode(PSDNodeType());

    final NodeModel importNode = logic.nodes[0];
    final NodeModel editNode = logic.nodes[1];
    final NodeModel psdNode = logic.nodes[2];
    logic.connections
      ..add(<String, dynamic>{
        'fromNode': importNode.id,
        'fromPort': 0,
        'toNode': editNode.id,
        'toPort': 0,
      })
      ..add(<String, dynamic>{
        'fromNode': editNode.id,
        'fromPort': 0,
        'toNode': psdNode.id,
        'toPort': 0,
      });
    importNode.datasetStates[dataset.id] = DatasetState.done;
    editNode.datasetStates[dataset.id] = DatasetState.ready;
    psdNode.datasetStates[dataset.id] = DatasetState.done;
    EditChannelsNodeType.setConfigForDataset(
      editNode.params,
      dataset.id,
      <String, dynamic>{
        'edits': <String, dynamic>{
          '1': <String, dynamic>{'remove': true, 'removeMode': 'delete'},
        },
      },
    );

    await logic.runThisStep(editNode.id, datasetIds: <String>{dataset.id});

    expect(editNode.datasetStates[dataset.id], DatasetState.done);
    expect(psdNode.datasetStates[dataset.id], DatasetState.stale);
    expect(dataset.timeSeries!.channelLabels, <String>['Fz', 'Pz']);

    editNode.datasetStates[dataset.id] = DatasetState.stale;
    await logic.runThisStep(editNode.id, datasetIds: <String>{dataset.id});

    expect(editNode.datasetStates[dataset.id], DatasetState.done);
    expect(dataset.timeSeries!.channelLabels, <String>['Fz', 'Pz']);
    expect(dataset.timeSeries!.channels.last, <double>[7, 8, 9]);
  });

  test('node runs stamp output artifact identity and lineage', () async {
    final CanvasLogic logic = CanvasLogic();
    final Dataset dataset = Dataset('dataset-1', label: 'Example');
    dataset.timeSeries = TimeSeriesData(
      samples: List<double>.generate(
        128,
        (int index) => math.sin(2 * math.pi * 10 * index / 128),
      ),
      sampleRate: 128,
      channelLabels: const <String>['Cz'],
    );
    dataset.setArtifactIdentity(
      const ArtifactIdentity(
        artifactId: 'import-node:dataset-1:timeSeries',
        datasetId: 'dataset-1',
        kind: BrainStoryArtifactKind.timeSeries,
        producerNodeId: 'import-node',
      ),
    );
    logic.datasets[dataset.id] = dataset;
    logic.addNode(ImportNodeType());
    logic.addNode(PSDNodeType());

    final NodeModel importNode = logic.nodes[0];
    final NodeModel psdNode = logic.nodes[1];
    logic.connections.add(<String, dynamic>{
      'fromNode': importNode.id,
      'fromPort': 0,
      'toNode': psdNode.id,
      'toPort': 0,
    });
    importNode.datasetStates[dataset.id] = DatasetState.done;
    psdNode.datasetStates[dataset.id] = DatasetState.ready;

    await logic.runThisStep(psdNode.id, datasetIds: <String>{dataset.id});

    final ArtifactIdentity? spectrumIdentity = dataset.artifactIdentityFor(
      BrainStoryArtifactKind.spectrum,
    );
    expect(spectrumIdentity, isNotNull);
    expect(spectrumIdentity!.producerNodeId, psdNode.id);
    expect(spectrumIdentity.datasetId, dataset.id);
    expect(spectrumIdentity.artifactId, '${psdNode.id}:${dataset.id}:spectrum');
    final NodeModel markerNode = logic.nodes.firstWhere(
      (NodeModel node) =>
          node.type is AddRemoveMarkersNodeType &&
          node.params['generatedMarkerLabel'] == 'FFT Window',
    );
    final NodeModel segmentationNode = logic.nodes.firstWhere(
      (NodeModel node) => node.type is SegmentationNodeType,
    );
    expect(markerNode.datasetStates[dataset.id], DatasetState.done);
    expect(segmentationNode.datasetStates[dataset.id], DatasetState.done);
    expect(psdNode.datasetStates[dataset.id], DatasetState.done);
    expect(
      spectrumIdentity.sourceArtifactIds,
      contains('${segmentationNode.id}:${dataset.id}:segmentedTimeSeries'),
    );
    expect(
      dataset
          .artifactIdentityFor(BrainStoryArtifactKind.timeSeries)!
          .producerNodeId,
      markerNode.id,
    );
  });

  test(
    'import stores multiple datasets to disk while keeping only the first hot',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset first = Dataset(
        'dataset-a',
        label: 'A.csv',
        path: 'A.csv',
        sourceBytes: Uint8List.fromList(
          utf8.encode('time,Cz\n0,0\n0.001,1\n0.002,0\n'),
        ),
      );
      final Dataset second = Dataset(
        'dataset-b',
        label: 'B.csv',
        path: 'B.csv',
        sourceBytes: Uint8List.fromList(
          utf8.encode('time,Cz\n0,2\n0.001,3\n0.002,2\n'),
        ),
      );
      logic.datasets[first.id] = first;
      logic.datasets[second.id] = second;
      logic.addNode(ImportNodeType());

      final NodeModel importNode = logic.nodes.single;
      importNode.params['selectedDatasetIds'] = <String>[first.id, second.id];

      await logic.runThisStep(
        importNode.id,
        datasetIds: <String>{first.id, second.id},
      );

      expect(importNode.datasetStates[first.id], DatasetState.done);
      expect(importNode.datasetStates[second.id], DatasetState.done);
      expect(first.timeSeries, isNotNull);
      expect(second.timeSeries, isNull);

      final Dataset reloadedSecond = await logic.materializedDatasetViewForNode(
        importNode.id,
        second,
      );
      expect(reloadedSecond.timeSeries, isNotNull);
      expect(reloadedSecond.timeSeries!.primaryChannel, <double>[2, 3, 2]);
    },
  );

  test(
    'renaming a completed import does not reload data or stale consumers',
    () async {
      final CanvasLogic logic = CanvasLogic(runUiYieldsEnabled: false);
      final Dataset dataset = Dataset(
        'rename-only-import-dataset',
        label: 'Original.csv',
        path: 'Original.csv',
        sourceBytes: Uint8List.fromList(
          utf8.encode('time,Cz\n0,1\n0.001,2\n0.002,3\n'),
        ),
      );
      dataset.ram['source.filename'] = 'Original.csv';
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(PSDNodeType());

      final NodeModel importNode = logic.nodes[0];
      final NodeModel consumerNode = logic.nodes[1];
      importNode.params['selectedDatasetIds'] = <String>[dataset.id];
      logic.connections.add(<String, dynamic>{
        'fromNode': importNode.id,
        'fromPort': 0,
        'toNode': consumerNode.id,
        'toPort': 0,
      });

      await logic.runThisStep(importNode.id, datasetIds: <String>{dataset.id});
      final ArtifactIdentity originalIdentity = dataset.artifactIdentityFor(
        BrainStoryArtifactKind.timeSeries,
      )!;
      consumerNode.datasetStates[dataset.id] = DatasetState.done;

      final Map<String, dynamic> renamedParams = Map<String, dynamic>.from(
        importNode.params,
      );
      renamedParams['datasetAliases'] = <String, dynamic>{
        dataset.id: 'Renamed recording',
      };
      logic.applyNodeParamsForTest(importNode, renamedParams);

      expect(dataset.label, 'Renamed recording');
      expect(importNode.datasetStates[dataset.id], DatasetState.stale);
      expect(consumerNode.datasetStates[dataset.id], DatasetState.done);

      dataset
        ..path = '/definitely/missing/brainstory-source.csv'
        ..sourceBytes = null
        ..timeSeries = null;

      await logic.runThisStep(importNode.id, datasetIds: <String>{dataset.id});

      expect(importNode.datasetStates[dataset.id], DatasetState.done);
      expect(consumerNode.datasetStates[dataset.id], DatasetState.done);
      expect(dataset.timeSeries, isNull);
      final Dataset cachedView = await logic.materializedDatasetViewForNode(
        importNode.id,
        dataset,
      );
      expect(cachedView.label, 'Renamed recording');
      expect(cachedView.timeSeries!.primaryChannel, <double>[1, 2, 3]);
      expect(
        cachedView
            .artifactIdentityFor(BrainStoryArtifactKind.timeSeries)!
            .revision,
        originalIdentity.revision,
      );

      final Map<String, dynamic> changedImportParams =
          Map<String, dynamic>.from(importNode.params);
      changedImportParams['sampleRateHz'] = 512.0;
      logic.applyNodeParamsForTest(importNode, changedImportParams);
      expect(importNode.datasetStates[dataset.id], DatasetState.stale);
      expect(consumerNode.datasetStates[dataset.id], DatasetState.stale);
    },
  );

  test('segmentation output stays scoped to its branch', () async {
    final CanvasLogic logic = CanvasLogic();
    final Dataset dataset = Dataset('dataset-1', label: 'Example');
    dataset.timeSeries = TimeSeriesData(
      samples: List<double>.generate(1000, (int index) => index.toDouble()),
      sampleRate: 1000,
      channelLabels: const <String>['Cz'],
      markers: const <TimeMarker>[
        TimeMarker(
          label: 'stim',
          onsetMicros: 400000,
          durationMicros: 0,
          markerType: MarkerType.event,
        ),
      ],
    );
    logic.datasets[dataset.id] = dataset;
    logic.addNode(ImportNodeType());
    logic.addNode(SegmentationNodeType());
    logic.addNode(PSDNodeType());

    final NodeModel importNode = logic.nodes[0];
    final NodeModel segmentationNode = logic.nodes[1];
    final NodeModel psdNode = logic.nodes[2];
    logic.connections.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'fromNode': importNode.id,
        'fromPort': 0,
        'toNode': segmentationNode.id,
        'toPort': 0,
      },
      <String, dynamic>{
        'fromNode': importNode.id,
        'fromPort': 0,
        'toNode': psdNode.id,
        'toPort': 0,
      },
    ]);
    importNode.datasetStates[dataset.id] = DatasetState.done;
    segmentationNode.datasetStates[dataset.id] = DatasetState.ready;
    psdNode.datasetStates[dataset.id] = DatasetState.ready;
    segmentationNode.params['includedMarkers'] = <String, dynamic>{
      'stim': true,
    };

    await logic.runThisStep(
      segmentationNode.id,
      datasetIds: <String>{dataset.id},
    );

    final Dataset segmentationView = await logic.materializedDatasetViewForNode(
      segmentationNode.id,
      dataset,
    );
    final Dataset siblingView = await logic.materializedDatasetViewForNode(
      psdNode.id,
      dataset,
    );

    expect(segmentationView.segmentedTimeSeries, isNotNull);
    expect(siblingView.segmentedTimeSeries, isNull);
    expect(siblingView.timeSeries, isNotNull);
  });

  test(
    'saved segmentation baseline option updates graph-run segment samples',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        channelSamples: <List<double>>[
          List<double>.generate(1000, (int index) => 100.0 + index.toDouble()),
        ],
        sampleRate: 1000,
        channelLabels: const <String>['Cz'],
        markers: const <TimeMarker>[
          TimeMarker(
            label: 'stim',
            onsetMicros: 500000,
            durationMicros: 0,
            markerType: MarkerType.event,
          ),
        ],
      );
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(SegmentationNodeType());
      logic.addNode(PSDNodeType());

      final NodeModel importNode = logic.nodes[0];
      final NodeModel segmentationNode = logic.nodes[1];
      final NodeModel psdNode = logic.nodes[2];
      logic.connections.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': segmentationNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': segmentationNode.id,
          'fromPort': 0,
          'toNode': psdNode.id,
          'toPort': 0,
        },
      ]);
      importNode.datasetStates[dataset.id] = DatasetState.done;
      segmentationNode.datasetStates[dataset.id] = DatasetState.ready;
      psdNode.datasetStates[dataset.id] = DatasetState.done;
      segmentationNode.params.addAll(<String, dynamic>{
        'mode': 'events',
        'eventWindowStartMs': -2.0,
        'eventWindowStopMs': 2.0,
        'eventApplyBaseline': false,
        'includedMarkers': <String, dynamic>{'event|stim': true},
      });

      await logic.runThisStep(
        segmentationNode.id,
        datasetIds: <String>{dataset.id},
      );
      expect(
        dataset.segmentedTimeSeries!
            .channelSamplesForSegment(
              dataset.segmentedTimeSeries!.segments.first,
            )
            .single,
        <double>[598.0, 599.0, 600.0, 601.0],
      );
      dataset.timeSeries = dataset.timeSeries!.copyWith(
        markers: const <TimeMarker>[],
      );

      logic.applyNodeParamsForTest(segmentationNode, <String, dynamic>{
        ...segmentationNode.params,
        'eventApplyBaseline': true,
        'eventBaselineStartMs': -2.0,
        'eventBaselineStopMs': 0.0,
      });

      expect(segmentationNode.datasetStates[dataset.id], DatasetState.stale);
      expect(psdNode.datasetStates[dataset.id], DatasetState.stale);

      await logic.runThisStep(
        segmentationNode.id,
        datasetIds: <String>{dataset.id},
      );
      final SignalSegmentData correctedSegment =
          dataset.segmentedTimeSeries!.segments.first;
      expect(correctedSegment.isSourceWindow, isFalse);
      expect(correctedSegment.channelSamples.single, <double>[
        -0.5,
        0.5,
        1.5,
        2.5,
      ]);
    },
  );

  test(
    'runThisStep refuses to recompute stale upstream dependencies',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        samples: List<double>.generate(128, (int index) => index.toDouble()),
        sampleRate: 128,
        channelLabels: const <String>['Cz'],
      );
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(SegmentationNodeType());
      logic.addNode(PSDNodeType());

      final NodeModel importNode = logic.nodes[0];
      final NodeModel segmentationNode = logic.nodes[1];
      final NodeModel psdNode = logic.nodes[2];
      logic.connections.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': segmentationNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': segmentationNode.id,
          'fromPort': 0,
          'toNode': psdNode.id,
          'toPort': 0,
        },
      ]);
      importNode.datasetStates[dataset.id] = DatasetState.done;
      segmentationNode.datasetStates[dataset.id] = DatasetState.stale;
      psdNode.datasetStates[dataset.id] = DatasetState.ready;

      await expectLater(
        logic.runThisStep(psdNode.id, datasetIds: <String>{dataset.id}),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Use Run From Start'),
          ),
        ),
      );
      expect(segmentationNode.datasetStates[dataset.id], DatasetState.stale);
    },
  );

  test('persistViewerEdits spawns a downstream edit markers node', () async {
    final CanvasLogic logic = CanvasLogic();
    final Dataset dataset = Dataset('dataset-1', label: 'Example');
    dataset.timeSeries = TimeSeriesData(
      samples: <double>[0, 1, 0, -1],
      sampleRate: 1000,
      channelLabels: <String>['Cz'],
    );
    logic.datasets['dataset-1'] = dataset;
    logic.addNode(ImportNodeType());
    final String sourceNodeId = logic.nodes.single.id;
    logic.nodes.single.datasetStates[dataset.id] = DatasetState.done;

    final String message = await logic.persistViewerEdits(
      viewerNodeId: sourceNodeId,
      dataset: dataset,
      markerEdits: <Map<String, dynamic>>[
        <String, dynamic>{
          'datasetId': dataset.id,
          'label': 'blink',
          'onsetMicros': 1000,
          'durationMicros': 500,
          'markerType': MarkerType.artifact,
        },
      ],
    );

    expect(message, 'Created Edit Markers.');
    expect(dataset.timeSeries?.markers, isEmpty);
    expect(
      logic.nodes.map((NodeModel node) => node.title),
      contains('Edit Markers'),
    );
    expect(logic.nodes, hasLength(2));

    final NodeModel editNode = logic.nodes.firstWhere(
      (NodeModel node) => node.type is AddRemoveMarkersNodeType,
    );

    expect(logic.selectedNodeId, sourceNodeId);
    expect(editNode.datasetStates[dataset.id], DatasetState.ready);
    expect(
      logic.connections.any(
        (Map<String, dynamic> connection) =>
            connection['fromNode'] == sourceNodeId &&
            connection['toNode'] == editNode.id,
      ),
      isTrue,
    );
  });

  test(
    'persistViewerEdits converts interactive artifact drafts to edit markers',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        samples: List<double>.filled(64, 0.0),
        sampleRate: 100,
        channelLabels: const <String>['Cz'],
        markers: const <TimeMarker>[
          TimeMarker(
            onsetMicros: 500000,
            label: 'Existing',
            markerType: MarkerType.event,
          ),
        ],
      );
      logic.datasets['dataset-1'] = dataset;
      logic.addNode(ImportNodeType());
      final String sourceNodeId = logic.nodes.single.id;
      logic.nodes.single.datasetStates[dataset.id] = DatasetState.done;

      final String message = await logic.persistViewerEdits(
        viewerNodeId: sourceNodeId,
        dataset: dataset,
        interactiveArtifactParams: <String, dynamic>{
          'artifactExemplars': <Map<String, dynamic>>[
            const ArtifactExemplarData(
              id: 'e1',
              datasetId: 'dataset-1',
              label: 'blink',
              onsetMicros: 1000000,
              durationMicros: 50000,
            ).toJson(),
          ],
          'artifactCandidates': <Map<String, dynamic>>[
            const ArtifactCandidateData(
              id: 'c1',
              datasetId: 'dataset-1',
              label: 'motion',
              onsetMicros: 2000000,
              durationMicros: 80000,
              score: 0.9,
              status: InteractiveArtifactDetectionNodeType.acceptedStatus,
            ).toJson(),
            const ArtifactCandidateData(
              id: 'c2',
              datasetId: 'dataset-1',
              label: 'blink',
              onsetMicros: 3000000,
              durationMicros: 80000,
              score: 0.8,
              status: InteractiveArtifactDetectionNodeType.pendingStatus,
            ).toJson(),
          ],
          'artifactTemplates': <Map<String, dynamic>>[],
        },
      );

      expect(message, 'Created Edit Markers.');
      expect(
        logic.nodes.map((NodeModel node) => node.title),
        isNot(contains('Interactive Artifact Detection')),
      );

      final NodeModel editNode = logic.nodes.firstWhere(
        (NodeModel node) => node.type is AddRemoveMarkersNodeType,
      );
      final List<Map<String, dynamic>> markers =
          (editNode.params['markers'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);

      expect(
        markers.map((Map<String, dynamic> marker) => marker['label']),
        containsAll(<String>['Existing', 'blink', 'motion']),
      );
      expect(
        markers.where((Map<String, dynamic> marker) {
          final Map<String, dynamic> attributes = Map<String, dynamic>.from(
            marker['attributes'] as Map,
          );
          return attributes['brainstory.artifactStatus'] ==
              InteractiveArtifactDetectionNodeType.pendingStatus;
        }),
        isEmpty,
      );
    },
  );

  test(
    'persistViewerEdits creates separate channel and marker edit nodes',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        channelSamples: const <List<double>>[
          <double>[1, 2, 3],
          <double>[4, 5, 6],
        ],
        sampleRate: 1000,
        channelLabels: const <String>['Fz', 'Cz'],
      );
      logic.datasets['dataset-1'] = dataset;
      logic.addNode(ImportNodeType());
      final NodeModel sourceNode = logic.nodes.single;
      sourceNode.datasetStates[dataset.id] = DatasetState.done;

      final String message = await logic.persistViewerEdits(
        viewerNodeId: sourceNode.id,
        dataset: dataset,
        markerEdits: <Map<String, dynamic>>[
          <String, dynamic>{
            'datasetId': dataset.id,
            'label': 'blink',
            'onsetMicros': 1000,
            'durationMicros': 500,
            'markerType': MarkerType.artifact,
          },
        ],
        channelEditConfig: <String, dynamic>{
          'edits': <String, dynamic>{
            '1': <String, dynamic>{
              'rename': '',
              'remove': true,
              'removeMode': 'delete',
            },
          },
          'newChannels': <Map<String, dynamic>>[],
          'visibleChannelIndices': <int>[1],
        },
      );

      expect(message, 'Created Edit Channels -> Edit Markers.');
      expect(dataset.timeSeries!.channelLabels, <String>['Fz', 'Cz']);

      final NodeModel channelNode = logic.nodes.firstWhere(
        (NodeModel node) => node.type is EditChannelsNodeType,
      );
      final NodeModel markerNode = logic.nodes.firstWhere(
        (NodeModel node) => node.type is AddRemoveMarkersNodeType,
      );

      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == sourceNode.id &&
              connection['toNode'] == channelNode.id,
        ),
        isTrue,
      );
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == channelNode.id &&
              connection['toNode'] == markerNode.id,
        ),
        isTrue,
      );
      final Dataset materialized = Dataset(dataset.id, label: 'Materialized')
        ..timeSeries = TimeSeriesData.fromJson(dataset.timeSeries!.toJson());
      await channelNode.type.run(materialized, channelNode.params);
      await markerNode.type.run(materialized, markerNode.params);

      expect(materialized.timeSeries!.channelLabels, <String>['Fz']);
      expect(materialized.timeSeries!.markers, hasLength(1));
      expect(materialized.timeSeries!.markers.first.label, 'blink');
    },
  );

  test(
    'persistViewerEdits rewires a visualization node through the spawned edit node',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        samples: <double>[0, 1, 0, -1],
        sampleRate: 1000,
        channelLabels: const <String>['Cz'],
      );
      logic.datasets['dataset-1'] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(VisualizationNodeType());
      final NodeModel importNode = logic.nodes[0];
      final NodeModel visualizationNode = logic.nodes[1];
      importNode.datasetStates[dataset.id] = DatasetState.done;
      logic.connections.add(<String, dynamic>{
        'fromNode': importNode.id,
        'fromPort': 0,
        'toNode': visualizationNode.id,
        'toPort': 0,
      });

      final VisualizationSourceRef sourceRef = logic
          .visualizationSourceRefsForNode(visualizationNode.id)
          .single;
      final Dataset view = await logic.materializedDatasetViewForSourceRef(
        sourceRef,
      );

      final String message = await logic.persistViewerEdits(
        viewerNodeId: visualizationNode.id,
        dataset: view,
        markerEdits: <Map<String, dynamic>>[
          <String, dynamic>{
            'datasetId': dataset.id,
            'label': 'blink',
            'onsetMicros': 1000,
            'durationMicros': 500,
            'markerType': MarkerType.artifact,
          },
        ],
      );

      final NodeModel editNode = logic.nodes.firstWhere(
        (NodeModel node) => node.type is AddRemoveMarkersNodeType,
      );
      expect(message, 'Created Edit Markers.');
      expect(logic.selectedNodeId, visualizationNode.id);
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == importNode.id &&
              connection['toNode'] == editNode.id,
        ),
        isTrue,
      );
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == editNode.id &&
              connection['toNode'] == visualizationNode.id,
        ),
        isTrue,
      );
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == importNode.id &&
              connection['toNode'] == visualizationNode.id,
        ),
        isFalse,
      );

      final VisualizationSourceRef rewiredSource = logic
          .visualizationSourceRefsForNode(visualizationNode.id)
          .single;

      expect(rewiredSource.materializeFromNodeId, editNode.id);
      expect(
        AddRemoveMarkersNodeType.markersForDataset(
          dataset.id,
          editNode.params['markers'] as List<dynamic>,
        ).map((TimeMarker marker) => marker.label),
        <String>['blink'],
      );
    },
  );

  test(
    'channel coordinates parse millimeter table and match decorated labels',
    () {
      const String csv = '''
channel,x,y,z
Fpz,-0.11,112.43,41.36
Fp1,30.7,107.17,41.45
Fp2,-30.7,107.13,41.35
Cz,0.32,3.4,147.92
''';
      final Map<String, ChannelCoordinate> coordinates =
          ChannelCoordinatesNodeType.parseChannelCoordinateCsv(csv);

      final ChannelCoordinate? fpz =
          ChannelCoordinatesNodeType.coordinateForChannelLabel(
            coordinates,
            'Fpz - AVG',
          );
      final ChannelCoordinate? cz =
          ChannelCoordinatesNodeType.coordinateForChannelLabel(
            coordinates,
            'Cz_ref',
          );

      expect(fpz, isNotNull);
      expect(fpz!.label, 'Fpz');
      expect(fpz.y, 112.43);
      expect(fpz.units, 'mm');
      expect(coordinates['fp1']!.x, -30.7);
      expect(coordinates['fp2']!.x, 30.7);
      expect(cz, isNotNull);
      expect(cz!.z, 147.92);
    },
  );

  test(
    'channel coordinates node assigns standard coordinates from asset',
    () async {
      final Dataset dataset = Dataset('coords', label: 'Coords');
      dataset.timeSeries = TimeSeriesData(
        channelSamples: const <List<double>>[
          <double>[1, 2, 3],
          <double>[4, 5, 6],
          <double>[7, 8, 9],
          <double>[10, 11, 12],
        ],
        sampleRate: 1000,
        channelLabels: const <String>[
          'Fpz - AVG',
          'Fp1',
          'Fp2',
          'NotAnElectrode',
        ],
      );

      await ChannelCoordinatesNodeType().run(dataset, <String, dynamic>{
        'mode': 'standard',
      });

      final Map<String, ChannelCoordinate> coordinates =
          dataset.timeSeries!.channelCoordinates;
      expect(coordinates.keys, contains('Fpz - AVG'));
      expect(coordinates['Fpz - AVG']!.label, 'Fpz - AVG');
      expect(coordinates['Fpz - AVG']!.units, 'mm');
      expect(coordinates['Fp1']!.x, lessThan(0));
      expect(coordinates['Fp2']!.x, greaterThan(0));
      expect(coordinates.keys, isNot(contains('NotAnElectrode')));
      expect(
        dataset.ram['channelCoordinates.params'],
        isA<Map<String, dynamic>>(),
      );
    },
  );

  test('parseSignalText infers sample rate from a time column', () {
    const String contents = '''
time,value
0,0.10
10,0.20
20,0.15
30,0.18
''';

    final ParsedSignalData parsed = parseSignalText(
      contents,
      fallbackSampleRate: 128.0,
      sourceDescription: 'inline.csv',
    );

    expect(parsed.samples.length, 4);
    expect(parsed.sampleRate, closeTo(100.0, 0.01));
    expect(parsed.channelLabels, <String>['value']);
    expect(parsed.samples[1], closeTo(0.20, 0.0001));
  });

  test('parseSignalText parses multiple channels from a time series table', () {
    const String contents = '''
time,Fz,Cz
0,1.0,10.0
10,2.0,20.0
20,3.0,30.0
''';

    final ParsedSignalData parsed = parseSignalText(
      contents,
      fallbackSampleRate: 128.0,
      sourceDescription: 'multichannel.csv',
    );

    expect(parsed.channelSamples.length, 2);
    expect(parsed.channelLabels, <String>['Fz', 'Cz']);
    expect(parsed.channelSamples[1], <double>[10.0, 20.0, 30.0]);
  });

  test('resampleSignal updates the sample rate and output length', () {
    final List<double> input = List<double>.generate(
      200,
      (int i) => math.sin(2 * math.pi * 8 * (i / 200.0)),
    );

    final List<double> output = resampleSignal(
      input,
      sourceSampleRate: 200.0,
      targetSampleRate: 100.0,
      method: 'cubic_spline',
    );

    expect(output.length, 100);
    expect(output.first, closeTo(input.first, 0.05));
    expect(output[25], closeTo(0.0, 0.25));
  });

  test(
    'suppressSpikes replaces isolated outliers with neighborhood median',
    () {
      final List<double> cleaned = suppressSpikes(<double>[
        0,
        0,
        0,
        25,
        0,
        0,
        0,
      ]);

      expect(cleaned[3], closeTo(0.0, 0.001));
    },
  );

  test('parseSignalText falls back to the provided sample rate', () {
    const String contents = '''
1.2
0.8
0.4
-0.1
''';

    final ParsedSignalData parsed = parseSignalText(
      contents,
      fallbackSampleRate: 256.0,
      sourceDescription: 'single-column.txt',
    );

    expect(parsed.samples, <double>[1.2, 0.8, 0.4, -0.1]);
    expect(parsed.sampleRate, 256.0);
  });

  test('applyBandpassFilter changes the signal while preserving length', () {
    final List<double> input = List<double>.generate(
      512,
      (int i) => (i.isEven ? 1.0 : -1.0) + (i / 512.0),
    );

    final List<double> output = applyBandpassFilter(
      input,
      sampleRate: 256.0,
      lowCutHz: 1.0,
      highCutHz: 40.0,
      steepness: 0.8,
      notchHz: 60.0,
    );

    expect(output.length, input.length);
    expect(output.first, isNot(closeTo(input.first, 0.0001)));
  });

  test('applyBandpassFilter notch attenuates the requested frequency', () {
    const double sampleRate = 256.0;
    const double targetFrequency = 60.0;
    final List<double> input = List<double>.generate(2048, (int i) {
      final double t = i / sampleRate;
      return math.sin(2 * math.pi * targetFrequency * t) +
          (0.25 * math.sin(2 * math.pi * 10.0 * t));
    });

    final List<double> withoutNotch = applyBandpassFilter(
      input,
      sampleRate: sampleRate,
      lowCutHz: 1.0,
      highCutHz: 100.0,
      steepness: 0.8,
    );
    final List<double> withNotch = applyBandpassFilter(
      input,
      sampleRate: sampleRate,
      lowCutHz: 1.0,
      highCutHz: 100.0,
      steepness: 0.8,
      notchHz: targetFrequency,
    );

    final double powerWithoutNotch = _singleFrequencyPower(
      withoutNotch,
      sampleRate,
      targetFrequency,
    );
    final double powerWithNotch = _singleFrequencyPower(
      withNotch,
      sampleRate,
      targetFrequency,
    );

    expect(powerWithNotch, lessThan(powerWithoutNotch * 0.2));
  });

  test('computeSpectrum identifies the dominant frequency of a sine wave', () {
    const double sampleRate = 256.0;
    const double targetFrequency = 12.0;
    final List<double> samples = List<double>.generate(256, (int i) {
      final double t = i / sampleRate;
      return math.sin(2 * math.pi * targetFrequency * t);
    });

    final SpectrumResult spectrum = computeSpectrum(
      samples,
      sampleRate: sampleRate,
      fLow: 1.0,
      fHigh: 40.0,
      averageSegments: true,
    );

    final int peakIndex = spectrum.power.indexWhere(
      (double value) => value == spectrum.power.reduce(math.max),
    );
    expect(spectrum.freqs[peakIndex], closeTo(targetFrequency, 1.5));
  });

  test(
    'PSD node uses the primary channel when time series is multichannel',
    () async {
      final Dataset dataset = Dataset('psd-multichannel', label: 'Multi');
      dataset.segmentedTimeSeries = SegmentedTimeSeriesData(
        sampleRate: 256.0,
        channelLabels: const <String>['Fz', 'Cz'],
        source: 'segmented',
        segments: <SignalSegmentData>[
          SignalSegmentData(
            channelSamples: <List<double>>[
              List<double>.generate(256, (int i) {
                final double t = i / 256.0;
                return math.sin(2 * math.pi * 10 * t);
              }),
              List<double>.filled(256, 0.0),
            ],
            startSeconds: 0,
            stopSeconds: 1,
            label: 'A',
          ),
        ],
      );

      await PSDNodeType().run(dataset, <String, dynamic>{
        'fLow': 1.0,
        'fHigh': 40.0,
        'outputMode': 'averaged',
      });

      expect(dataset.spectrum, isNotNull);
      expect(dataset.spectrum!.frequencies, isNotEmpty);
      expect(dataset.spectrum!.power, isNotEmpty);
    },
  );

  test('Resample node reports execution chunks by channel', () async {
    final Dataset dataset = Dataset('chunked-resample', label: 'Chunked');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[0, 1, 0, -1],
        <double>[1, 0, -1, 0],
      ],
      sampleRate: 4.0,
      channelLabels: const <String>['Cz', 'Pz'],
    );
    int progressCount = 0;
    int yieldCount = 0;

    await ResampleNodeType().runChunked(
      dataset,
      <String, dynamic>{
        'newSampleRate': 8.0,
        'method': 'linear',
        'omitSpikes': false,
      },
      NodeExecutionContext(
        setProgress: (String detail) async {
          progressCount++;
        },
        yieldIfNeeded: () async {
          yieldCount++;
        },
      ),
    );

    expect(progressCount, 2);
    expect(yieldCount, 2);
    expect(dataset.timeSeries!.channels, hasLength(2));
    expect(dataset.timeSeries!.sampleRate, 8.0);
  });

  test('PSD node can compute from segmented time series', () async {
    final Dataset dataset = Dataset('psd-segments', label: 'Segments');
    final List<double> samples = List<double>.generate(512, (int i) {
      final double t = i / 256.0;
      return math.sin(2 * math.pi * 12 * t);
    });
    dataset.segmentedTimeSeries = SegmentedTimeSeriesData(
      sampleRate: 256.0,
      channelLabels: const <String>['Cz'],
      source: 'segmented',
      segments: <SignalSegmentData>[
        SignalSegmentData(
          channelSamples: <List<double>>[samples.sublist(0, 256)],
          startSeconds: 0,
          stopSeconds: 1,
          label: 'A',
        ),
        SignalSegmentData(
          channelSamples: <List<double>>[samples.sublist(256, 512)],
          startSeconds: 1,
          stopSeconds: 2,
          label: 'A',
        ),
      ],
    );

    await PSDNodeType().run(dataset, <String, dynamic>{
      'fLow': 1.0,
      'fHigh': 40.0,
      'outputMode': 'averaged',
    });

    expect(dataset.spectrum, isNotNull);
    expect(dataset.spectrum!.frequencies, isNotEmpty);
    final int peakIndex = dataset.spectrum!.power.indexWhere(
      (double value) => value == dataset.spectrum!.power.reduce(math.max),
    );
    expect(dataset.spectrum!.frequencies[peakIndex], closeTo(12.0, 1.5));
    expect(dataset.spectrum!.segmentCount, greaterThanOrEqualTo(2));
  });

  test(
    'running averaged PSD expands visible marker, segmentation, and average nodes',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        samples: List<double>.filled(256, 0.0),
        sampleRate: 256,
        channelLabels: const <String>['Cz'],
      );
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(PSDNodeType());
      final NodeModel importNode = logic.nodes[0];
      final NodeModel psdNode = logic.nodes[1];
      importNode.datasetStates[dataset.id] = DatasetState.done;
      logic.connections.add(<String, dynamic>{
        'fromNode': importNode.id,
        'fromPort': 0,
        'toNode': psdNode.id,
        'toPort': 0,
      });

      psdNode.params['outputMode'] = 'averaged';

      await logic.runFromStart(psdNode.id, datasetIds: <String>{dataset.id});

      final NodeModel markerNode = logic.nodes.firstWhere(
        (NodeModel node) =>
            node.type is AddRemoveMarkersNodeType &&
            node.params['generatedMarkerLabel'] == 'FFT Window',
      );
      final NodeModel segmentationNode = logic.nodes.firstWhere(
        (NodeModel node) => node.type is SegmentationNodeType,
      );
      final NodeModel averageNode = logic.nodes.firstWhere(
        (NodeModel node) => node.type is PSDAverageNodeType,
      );

      expect(psdNode.params['deferAverageToDownstream'], isTrue);
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == importNode.id &&
              connection['toNode'] == markerNode.id,
        ),
        isTrue,
      );
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == markerNode.id &&
              connection['toNode'] == segmentationNode.id,
        ),
        isTrue,
      );
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == segmentationNode.id &&
              connection['toNode'] == psdNode.id,
        ),
        isTrue,
      );
      expect(
        logic.connections.any(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == psdNode.id &&
              connection['toNode'] == averageNode.id,
        ),
        isTrue,
      );
    },
  );

  test(
    'PSD can use selected parent segments instead of creating windows',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        samples: List<double>.generate(
          512,
          (int index) => math.sin(2 * math.pi * 12 * index / 256),
        ),
        sampleRate: 256,
        channelLabels: const <String>['Cz'],
        markers: const <TimeMarker>[
          TimeMarker(
            label: 'stim',
            onsetMicros: 500000,
            durationMicros: 0,
            markerType: MarkerType.event,
          ),
        ],
      );
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(SegmentationNodeType());
      logic.addNode(PSDNodeType());

      final NodeModel importNode = logic.nodes[0];
      final NodeModel segmentationNode = logic.nodes[1];
      final NodeModel psdNode = logic.nodes[2];
      logic.connections.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': segmentationNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': importNode.id,
          'fromPort': 0,
          'toNode': psdNode.id,
          'toPort': 0,
        },
        <String, dynamic>{
          'fromNode': segmentationNode.id,
          'fromPort': 0,
          'toNode': psdNode.id,
          'toPort': 1,
        },
      ]);
      importNode.datasetStates[dataset.id] = DatasetState.done;
      segmentationNode.datasetStates[dataset.id] = DatasetState.ready;
      psdNode.datasetStates[dataset.id] = DatasetState.ready;
      segmentationNode.params.addAll(<String, dynamic>{
        'mode': 'events',
        'eventWindowStartMs': -100.0,
        'eventWindowStopMs': 400.0,
        'includedMarkers': <String, dynamic>{'event|stim': true},
      });
      psdNode.params.addAll(<String, dynamic>{
        'useParentSegments': true,
        'parentSegmentsNodeId': segmentationNode.id,
        'outputMode': 'segments',
      });

      await logic.runFromStart(psdNode.id, datasetIds: <String>{dataset.id});

      expect(
        logic.nodes.where(
          (NodeModel node) => node.type is SegmentationNodeType,
        ),
        hasLength(1),
      );
      expect(
        logic.nodes.any(
          (NodeModel node) =>
              node.type is AddRemoveMarkersNodeType &&
              node.params['generatedMarkerLabel'] == 'FFT Window',
        ),
        isFalse,
      );
      expect(segmentationNode.datasetStates[dataset.id], DatasetState.done);
      expect(psdNode.datasetStates[dataset.id], DatasetState.done);
      expect(dataset.spectrum, isNotNull);
      expect(
        dataset
            .artifactIdentityFor(BrainStoryArtifactKind.spectrum)!
            .sourceArtifactIds,
        contains('${segmentationNode.id}:${dataset.id}:segmentedTimeSeries'),
      );
    },
  );

  test(
    'running standalone equal-window segmentation creates named window markers',
    () async {
      final CanvasLogic logic = CanvasLogic();
      final Dataset dataset = Dataset('dataset-1', label: 'Example');
      dataset.timeSeries = TimeSeriesData(
        samples: List<double>.filled(300, 0.0),
        sampleRate: 100,
        channelLabels: const <String>['Cz'],
      );
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(SegmentationNodeType());
      final NodeModel importNode = logic.nodes[0];
      final NodeModel segmentationNode = logic.nodes[1];
      importNode.datasetStates[dataset.id] = DatasetState.done;
      segmentationNode.params['mode'] = 'equal_windows';
      segmentationNode.params['windowMarkerName'] = 'Welch Window';
      segmentationNode.params['equalWindowWidthMs'] = 1000.0;
      segmentationNode.params['equalWindowOverlapPercent'] = 0.0;
      logic.connections.add(<String, dynamic>{
        'fromNode': importNode.id,
        'fromPort': 0,
        'toNode': segmentationNode.id,
        'toPort': 0,
      });

      await logic.runFromStart(
        segmentationNode.id,
        datasetIds: <String>{dataset.id},
      );

      expect(
        logic.nodes.where(
          (NodeModel node) =>
              node.type is AddRemoveMarkersNodeType &&
              node.params['generatedMarkerLabel'] == 'Welch Window',
        ),
        hasLength(1),
      );
      expect(dataset.segmentedTimeSeries, isNotNull);
      expect(
        dataset.segmentedTimeSeries!.segments
            .map((SignalSegmentData segment) => segment.label)
            .toSet(),
        <String>{'Welch Window'},
      );
    },
  );

  test('Average Spectra node averages stored PSD segment powers', () async {
    final Dataset dataset = Dataset('psd-average', label: 'PSD Average');
    dataset.spectrum = const FrequencySpectrumData(
      frequencies: <double>[1, 2],
      power: <double>[1, 3],
      segmentPowers: <List<double>>[
        <double>[1, 3],
        <double>[3, 5],
      ],
      segmentCount: 2,
    );

    await PSDAverageNodeType().run(dataset, <String, dynamic>{});

    expect(dataset.spectrum!.power, <double>[2, 4]);
    expect(dataset.spectrum!.segmentCount, 2);
  });

  test(
    'Edit Channels node can rename, delete, and build derived channels',
    () async {
      final Dataset dataset = Dataset('edit-channels', label: 'Edit');
      dataset.timeSeries = TimeSeriesData(
        channelSamples: const <List<double>>[
          <double>[1, 2, 3],
          <double>[4, 5, 6],
          <double>[7, 8, 9],
        ],
        sampleRate: 100.0,
        channelLabels: const <String>['Fz', 'Cz', 'Pz'],
      );

      await EditChannelsNodeType().run(dataset, <String, dynamic>{
        'channelEditsByDataset': <String, dynamic>{
          dataset.id: <String, dynamic>{
            'edits': <String, dynamic>{
              '0': <String, dynamic>{
                'rename': 'Frontal',
                'remove': false,
                'removeMode': 'delete',
              },
              '1': <String, dynamic>{
                'rename': '',
                'remove': true,
                'removeMode': 'delete',
              },
            },
            'newChannels': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'pool-1',
                'name': 'Difference',
                'addSourceIndices': <int>[0, 2],
                'subtractSourceIndices': <int>[1],
                'normalize': true,
              },
            ],
          },
        },
      });

      expect(dataset.timeSeries, isNotNull);
      expect(dataset.timeSeries!.channelLabels, <String>[
        'Frontal',
        'Pz',
        'Difference',
      ]);
      expect(dataset.timeSeries!.channelSamples[2], <double>[
        4.0 / 3.0,
        5.0 / 3.0,
        2.0,
      ]);
    },
  );

  test(
    'Edit Channels can assign standard coordinates and average rereference',
    () async {
      final Dataset dataset = Dataset('edit-channels-meta', label: 'Edit Meta');
      dataset.timeSeries = TimeSeriesData(
        channelSamples: const <List<double>>[
          <double>[1, 4],
          <double>[3, 8],
        ],
        sampleRate: 100.0,
        channelLabels: const <String>['Fpz - AVG', 'Cz'],
      );

      await EditChannelsNodeType().run(dataset, <String, dynamic>{
        'channelEditsByDataset': <String, dynamic>{
          dataset.id: <String, dynamic>{
            'coordinateImportMode':
                EditChannelsNodeType.coordinateImportStandard,
            'rereferenceMode': EditChannelsNodeType.rereferenceAverage,
          },
        },
      });

      expect(dataset.timeSeries!.channelSamples[0], <double>[-1, -2]);
      expect(dataset.timeSeries!.channelSamples[1], <double>[1, 2]);
      expect(
        dataset.timeSeries!.channelCoordinates.keys,
        contains('Fpz - AVG'),
      );
      expect(dataset.timeSeries!.channelCoordinates.keys, contains('Cz'));
      expect(dataset.timeSeries!.channelCoordinates['Fpz - AVG']!.units, 'mm');
    },
  );

  testWidgets('Edit Channels controls fit without internal overflow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(385, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ChannelEditConfigEditor(
              channelLabels: const <String>['ECG1'],
              config: const <String, dynamic>{},
              initialVisibleChannelIndices: const <int>[0],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Import channel coordinates'), findsOneWidget);
    expect(find.text('Rereference'), findsOneWidget);
  });

  test('loadDatasetSignal imports the sample EDF fixture', () async {
    final ParsedSignalData parsed = await loadDatasetSignal(
      '..\\tests\\Zhao_Alex_2024-09-24_16-47-37_highpass_Segment_0.edf',
      fallbackSampleRate: 256.0,
    );

    expect(parsed.samples, isNotEmpty);
    expect(parsed.sampleRate, greaterThan(0));
    expect(parsed.sourceDescription, contains('.edf'));
  });

  test('loadDatasetSignal imports the sample CSV fixture', () async {
    final ParsedSignalData parsed = await loadDatasetSignal(
      '..\\tests\\test_data.csv',
      fallbackSampleRate: 256.0,
    );

    expect(parsed.samples, isNotEmpty);
    expect(parsed.sampleRate, greaterThan(0));
  });

  test('loadDatasetSignal imports the sample EEGLAB fixture', () async {
    final ParsedSignalData parsed = await loadDatasetSignal(
      '..\\tests\\PVT.set',
      fallbackSampleRate: 256.0,
    );

    expect(parsed.channelSamples.length, 63);
    expect(parsed.channelLabels.first, 'Fp1');
    expect(parsed.sampleRate, closeTo(500.0, 0.001));
    expect(parsed.samples.length, 306060);
    expect(parsed.markers, isNotEmpty);
    expect(parsed.markers.first.label, isNotEmpty);
  });

  test('loadDatasetSignal imports a synthetic BrainVision fixture', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'brainstory_bv_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final File vhdrFile = File(
      '${tempDir.path}${Platform.pathSeparator}sample.vhdr',
    );
    final File eegFile = File(
      '${tempDir.path}${Platform.pathSeparator}sample.eeg',
    );
    final File vmrkFile = File(
      '${tempDir.path}${Platform.pathSeparator}sample.vmrk',
    );

    await vhdrFile.writeAsString('''
Brain Vision Data Exchange Header File Version 1.0
[Common Infos]
DataFile=sample.eeg
MarkerFile=sample.vmrk
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=2
SamplingInterval=2000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,
Ch2=Fp2,,
''');

    await vmrkFile.writeAsString('''
Brain Vision Data Exchange Marker File, Version 1.0
[Marker Infos]
Mk1=Stimulus,S  1,1,1,0
Mk2=Artifact,Bad Segment,11,5,0
''');

    final ByteData eegData = ByteData(4 * 2 * 2);
    final List<int> values = <int>[100, 1000, 200, 900, 300, 800, 400, 700];
    for (int i = 0; i < values.length; i++) {
      eegData.setInt16(i * 2, values[i], Endian.little);
    }
    await eegFile.writeAsBytes(eegData.buffer.asUint8List());

    final ParsedSignalData parsed = await loadDatasetSignal(
      vhdrFile.path,
      fallbackSampleRate: 256.0,
    );

    expect(parsed.channelSamples.length, 2);
    expect(parsed.channelLabels, <String>['Fp1', 'Fp2']);
    expect(parsed.sampleRate, closeTo(500.0, 0.001));
    expect(parsed.channelSamples[0], <double>[100, 200, 300, 400]);
    expect(parsed.channelSamples[1], <double>[1000, 900, 800, 700]);
    expect(parsed.markers, hasLength(2));
    expect(parsed.markers.first.label, 'S  1');
    expect(parsed.markers.first.markerType, MarkerType.event);
    expect(parsed.markers.last.label, 'Bad Segment');
    expect(parsed.markers.last.markerType, MarkerType.artifact);
  });

  test('parseAntCntPayload decodes channel-major float32 data and markers', () {
    final BytesBuilder bytes = BytesBuilder();
    for (final double value in <double>[1, 2, 3, 4, 5, 6]) {
      final ByteData encoded = ByteData(4)..setFloat32(0, value, Endian.little);
      bytes.add(encoded.buffer.asUint8List());
    }

    final AntCntImportData parsed = parseAntCntPayload(<String, dynamic>{
      'sourceDescription': 'sample.cnt',
      'sampleRate': 500.0,
      'channelCount': 2,
      'sampleCount': 3,
      'channelLabels': <String>['Fp1', 'Fp2'],
      'impedance': <String, dynamic>{
        'channelLabels': <String>['Fp1', 'Fp2'],
        'measurementTimesMicros': <int>[2000, 4000],
        'ohmsByChannel': <List<double?>>[
          <double?>[12.5, 11.0],
          <double?>[18.0, null],
        ],
      },
      'markers': <Map<String, dynamic>>[
        <String, dynamic>{
          'label': 'Stim',
          'onsetMicros': 2000,
          'durationMicros': 0,
          'markerType': MarkerType.event,
        },
      ],
    }, bytes.toBytes());

    expect(parsed.sourceDescription, 'sample.cnt');
    expect(parsed.sampleRate, 500.0);
    expect(parsed.channelLabels, <String>['Fp1', 'Fp2']);
    expect(parsed.channelSamples, <List<double>>[
      <double>[1, 2, 3],
      <double>[4, 5, 6],
    ]);
    expect(parsed.markers.single.label, 'Stim');
    expect(parsed.markers.single.onsetMicros, 2000);
    expect(parsed.impedanceData?.channelLabels, <String>['Fp1', 'Fp2']);
    expect(parsed.impedanceData?.measurementTimesMicros, <int>[2000, 4000]);
    expect(parsed.impedanceData?.ohmsByChannel, <List<double?>>[
      <double?>[12.5, 11.0],
      <double?>[18.0, null],
    ]);

    final TimeSeriesData restored = TimeSeriesData.fromJson(
      TimeSeriesData(
        channelSamples: parsed.channelSamples,
        sampleRate: parsed.sampleRate,
        channelLabels: parsed.channelLabels,
        impedanceData: parsed.impedanceData,
        markers: parsed.markers,
      ).toJson(),
    );
    expect(restored.impedanceData?.ohmsByChannel, <List<double?>>[
      <double?>[12.5, 11.0],
      <double?>[18.0, null],
    ]);
  });

  test('buildSingleChannelEdfBytes round-trips through EDF parsing', () async {
    final List<double> samples = List<double>.generate(
      128,
      (int i) => math.sin(2 * math.pi * 8 * (i / 128.0)),
    );

    final List<int> bytes = buildSingleChannelEdfBytes(
      samples: samples,
      sampleRate: 128.0,
      label: 'RoundTrip',
    );
    final ParsedSignalData parsed = parseEdfBytes(
      Uint8List.fromList(bytes),
      sourceDescription: 'memory.edf',
    );

    expect(parsed.samples.length, samples.length);
    expect(parsed.sampleRate, closeTo(128.0, 0.001));
    expect(parsed.samples.first, closeTo(samples.first, 0.05));
  });

  test(
    'buildEdfBytes round-trips multiple channels through EDF parsing',
    () async {
      final List<double> channelOne = List<double>.generate(
        64,
        (int i) => math.sin(2 * math.pi * 6 * (i / 128.0)),
      );
      final List<double> channelTwo = List<double>.generate(
        64,
        (int i) => math.cos(2 * math.pi * 10 * (i / 128.0)),
      );

      final List<int> bytes = buildEdfBytes(
        channelSamples: <List<double>>[channelOne, channelTwo],
        sampleRate: 128.0,
        labels: const <String>['Fz', 'Cz'],
      );
      final ParsedSignalData parsed = parseEdfBytes(
        Uint8List.fromList(bytes),
        sourceDescription: 'multichannel.edf',
      );

      expect(parsed.channelSamples.length, 2);
      expect(parsed.channelLabels, <String>['Fz', 'Cz']);
      expect(
        parsed.channelSamples.first.first,
        closeTo(channelOne.first, 0.05),
      );
      expect(parsed.channelSamples.last.first, closeTo(channelTwo.first, 0.05));
    },
  );

  test('parseEdfBytes extracts EDF+ annotation markers', () {
    String field(String value, int width) {
      final String trimmed = value.length > width
          ? value.substring(0, width)
          : value;
      return trimmed.padRight(width);
    }

    Uint8List buildAnnotatedEdfBytes() {
      const int numSignals = 2;
      const int numRecords = 2;
      const double recordDurationSeconds = 1.0;
      const int dataSamplesPerRecord = 1;
      const int annotationSamplesPerRecord = 32;
      const int headerBytes = 256 + (numSignals * 256);

      final StringBuffer header = StringBuffer()
        ..write(field('0', 8))
        ..write(field('BrainStory', 80))
        ..write(field('BrainStory', 80))
        ..write(field('01.01.26', 8))
        ..write(field('01.01.01', 8))
        ..write(field('$headerBytes', 8))
        ..write(field('', 44))
        ..write(field('$numRecords', 8))
        ..write(field(recordDurationSeconds.toStringAsFixed(1), 8))
        ..write(field('$numSignals', 4));

      for (final String label in <String>['C3', 'EDF Annotations']) {
        header.write(field(label, 16));
      }
      for (int i = 0; i < numSignals; i++) {
        header.write(field('', 80));
      }
      for (int i = 0; i < numSignals; i++) {
        header.write(field(i == 0 ? 'uV' : '', 8));
      }
      header
        ..write(field('-100', 8))
        ..write(field('-1', 8));
      header
        ..write(field('100', 8))
        ..write(field('1', 8));
      header
        ..write(field('-32768', 8))
        ..write(field('-32768', 8));
      header
        ..write(field('32767', 8))
        ..write(field('32767', 8));
      for (int i = 0; i < numSignals; i++) {
        header.write(field('', 80));
      }
      header
        ..write(field('$dataSamplesPerRecord', 8))
        ..write(field('$annotationSamplesPerRecord', 8));
      for (int i = 0; i < numSignals; i++) {
        header.write(field('', 32));
      }

      final BytesBuilder builder = BytesBuilder();
      builder.add(ascii.encode(header.toString()));

      List<int> annotationRecord(String tal) {
        final List<int> bytes = ascii.encode(tal);
        return <int>[
          ...bytes,
          ...List<int>.filled(
            (annotationSamplesPerRecord * 2) - bytes.length,
            0,
          ),
        ];
      }

      final ByteData signalData = ByteData(numRecords * 2);
      signalData.setInt16(0, 100, Endian.little);
      signalData.setInt16(2, 200, Endian.little);

      builder.add(signalData.buffer.asUint8List(0, 2));
      builder.add(annotationRecord('+0\x14Stim\x14\x00'));
      builder.add(signalData.buffer.asUint8List(2, 2));
      builder.add(annotationRecord('+1\x150.5\x14Bad Segment\x14\x00'));

      return builder.toBytes();
    }

    final ParsedSignalData parsed = parseEdfBytes(
      buildAnnotatedEdfBytes(),
      sourceDescription: 'annotated.edf',
    );

    expect(parsed.channelLabels, <String>['C3']);
    expect(parsed.channelSamples.single.length, 2);
    expect(parsed.markers, hasLength(2));
    expect(parsed.markers.first.label, 'Stim');
    expect(parsed.markers.first.markerType, MarkerType.event);
    expect(parsed.markers.first.onsetMicros, 0);
    expect(parsed.markers.last.label, 'Bad Segment');
    expect(parsed.markers.last.markerType, MarkerType.artifact);
    expect(parsed.markers.last.onsetMicros, 1000000);
    expect(parsed.markers.last.durationMicros, 500000);
  });

  test('resolveEdfExportFile builds a filename next to the source file', () {
    final Dataset dataset = Dataset(
      '1',
      label: 'My Signal',
      path: 'C:\\temp\\example.csv',
    );

    final String target = resolveEdfExportFile(
      dataset: dataset,
      outputDirectory: '',
      filenameSuffix: '_brainstory',
    );

    expect(target, 'C:\\temp\\example_brainstory.edf');
  });

  test(
    'resolveTextExportFile builds a csv filename next to the source file',
    () {
      final Dataset dataset = Dataset(
        '2',
        label: 'Feature Table',
        path: 'C:\\temp\\example.csv',
      );

      final String target = resolveTextExportFile(
        dataset: dataset,
        outputDirectory: '',
        filenameSuffix: '_brainstory',
        fileExtension: 'csv',
      );

      expect(target, 'C:\\temp\\example_brainstory.csv');
    },
  );

  test('factor resolves the matching level for a marker key', () {
    const Factor factor = Factor(
      name: 'Condition',
      levels: <FactorLevel>[
        FactorLevel(
          name: 'Target',
          markerKeys: <String>{'stim/target', 'stim/go'},
        ),
        FactorLevel(name: 'Non-target', markerKeys: <String>{'stim/nontarget'}),
      ],
    );

    expect(factor.levelForMarker('stim/go')?.name, 'Target');
    expect(factor.levelForMarker('missing'), isNull);
    expect(factor.isValid, isTrue);
  });

  test('factor becomes invalid when a marker belongs to multiple levels', () {
    const Factor factor = Factor(
      name: 'Artifact State',
      levels: <FactorLevel>[
        FactorLevel(name: 'Clean', markerKeys: <String>{'segment/keep'}),
        FactorLevel(
          name: 'Artifact',
          markerKeys: <String>{'segment/keep', 'segment/reject'},
        ),
      ],
    );

    expect(factor.markerBelongsToMultipleLevels(), isTrue);
    expect(factor.isValid, isFalse);
  });

  test('segmentation node creates event-based segments', () async {
    final Dataset dataset = Dataset('segments', label: 'Segmented');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: <List<double>>[
        List<double>.generate(1000, (int index) => index.toDouble()),
      ],
      sampleRate: 1000.0,
      channelLabels: const <String>['Cz'],
      markers: const <TimeMarker>[
        TimeMarker(
          onsetMicros: 500000,
          durationMicros: 0,
          label: 'Pulse',
          markerType: MarkerType.event,
        ),
      ],
    );

    await SegmentationNodeType().run(dataset, <String, dynamic>{
      'mode': 'events',
      'eventWindowStartMs': -100.0,
      'eventWindowStopMs': 100.0,
      'includedMarkers': <String, dynamic>{'event|Pulse': true},
    });

    expect(dataset.segmentedTimeSeries, isNotNull);
    expect(dataset.segmentedTimeSeries!.segmentCount, 1);
    final SegmentedTimeSeriesData segmented = dataset.segmentedTimeSeries!;
    final SignalSegmentData segment = segmented.segments.first;
    expect(segment.sampleCount, 200);
    expect(segment.channelSamples, isEmpty);
    expect(segment.isSourceWindow, isTrue);
    expect(segmented.sourceTimeSeries, same(dataset.timeSeries));
    expect(segmented.channelSamplesForSegment(segment).single.first, 400.0);
    expect(segmented.channelSamplesForSegment(segment).single.last, 599.0);
    expect(segment.anchorTimeSeconds, closeTo(0.5, 0.0001));
    final Map<String, dynamic> averages = Map<String, dynamic>.from(
      dataset.ram['segmentation.precomputedConditionAverages'] as Map? ??
          const <String, dynamic>{},
    );
    expect(averages, contains('Pulse'));
    final Map<String, dynamic> pulseAverage = Map<String, dynamic>.from(
      averages['Pulse'] as Map,
    );
    expect(pulseAverage['segmentCount'], 1);
    expect(pulseAverage['sampleCount'], 200);
  });

  test(
    'event segmentation optionally baseline-corrects output artifacts',
    () async {
      final Dataset rawDataset = Dataset('segments-raw', label: 'Raw');
      rawDataset.timeSeries = TimeSeriesData(
        channelSamples: <List<double>>[
          List<double>.generate(1000, (int index) => 100.0 + index.toDouble()),
        ],
        sampleRate: 1000.0,
        channelLabels: const <String>['Cz'],
        markers: const <TimeMarker>[
          TimeMarker(
            onsetMicros: 500000,
            durationMicros: 0,
            label: 'Pulse',
            markerType: MarkerType.event,
          ),
        ],
      );
      await SegmentationNodeType().run(rawDataset, <String, dynamic>{
        'mode': 'events',
        'eventWindowStartMs': -2.0,
        'eventWindowStopMs': 2.0,
        'eventApplyBaseline': false,
        'includedMarkers': <String, dynamic>{'event|Pulse': true},
      });
      expect(
        rawDataset.segmentedTimeSeries!
            .channelSamplesForSegment(
              rawDataset.segmentedTimeSeries!.segments.first,
            )
            .single,
        <double>[598.0, 599.0, 600.0, 601.0],
      );

      final Dataset correctedDataset = Dataset(
        'segments-corrected',
        label: 'Corrected',
      );
      correctedDataset.timeSeries = rawDataset.timeSeries;
      await SegmentationNodeType().run(correctedDataset, <String, dynamic>{
        'mode': 'events',
        'eventWindowStartMs': -2.0,
        'eventWindowStopMs': 2.0,
        'eventApplyBaseline': true,
        'eventBaselineStartMs': -2.0,
        'eventBaselineStopMs': 0.0,
        'includedMarkers': <String, dynamic>{'event|Pulse': true},
      });
      final SignalSegmentData correctedSegment =
          correctedDataset.segmentedTimeSeries!.segments.first;
      expect(correctedSegment.isSourceWindow, isFalse);
      expect(correctedSegment.channelSamples.single, <double>[
        -0.5,
        0.5,
        1.5,
        2.5,
      ]);
    },
  );

  test(
    'segmented snapshots materialize source-window samples for persistence',
    () async {
      final Dataset dataset = Dataset('segments', label: 'Segmented');
      dataset.timeSeries = TimeSeriesData(
        channelSamples: <List<double>>[
          List<double>.generate(100, (int index) => index.toDouble()),
        ],
        sampleRate: 1000.0,
        channelLabels: const <String>['Cz'],
        markers: const <TimeMarker>[
          TimeMarker(
            onsetMicros: 50000,
            label: 'Pulse',
            markerType: MarkerType.event,
          ),
        ],
      );

      await SegmentationNodeType().run(dataset, <String, dynamic>{
        'mode': 'events',
        'eventWindowStartMs': -10.0,
        'eventWindowStopMs': 10.0,
        'includedMarkers': <String, dynamic>{'event|Pulse': true},
      });

      final Map<String, dynamic> json = DatasetArtifactSnapshot.fromDataset(
        dataset,
      ).toJson();
      final DatasetArtifactSnapshot restored = DatasetArtifactSnapshot.fromJson(
        json,
      );

      expect(restored.segmentedTimeSeries, isNotNull);
      expect(
        restored.segmentedTimeSeries!.segments.first.channelSamples.single,
        List<double>.generate(20, (int index) => (40 + index).toDouble()),
      );
    },
  );

  test('block segmentation consumes one duration-bearing marker', () async {
    final Dataset dataset = Dataset('block-window', label: 'Block window');
    dataset.timeSeries = TimeSeriesData(
      samples: List<double>.generate(100, (int index) => index.toDouble()),
      sampleRate: 10.0,
      channelLabels: const <String>['Cz'],
      markers: const <TimeMarker>[
        TimeMarker(
          onsetMicros: 2000000,
          durationMicros: 3000000,
          label: 'Task block',
          markerType: MarkerType.window,
        ),
      ],
    );

    await SegmentationNodeType().run(dataset, <String, dynamic>{
      'mode': 'blocks',
      'includedMarkers': <String, dynamic>{'window|Task block': true},
      'blockConcatenate': false,
      'blockInvert': false,
    });

    final SignalSegmentData segment =
        dataset.segmentedTimeSeries!.segments.single;
    expect(segment.label, 'Task block');
    expect(segment.startSeconds, 2.0);
    expect(segment.stopSeconds, 5.0);
    expect(segment.sourceStartSample, 20);
    expect(segment.sourceStopSampleExclusive, 50);
    expect(
      dataset.segmentedTimeSeries!.channelSamplesForSegment(segment).single,
      List<double>.generate(30, (int index) => (20 + index).toDouble()),
    );
  });

  test('block concatenation keeps conditions separate', () async {
    final Dataset dataset = Dataset(
      'condition-blocks',
      label: 'Condition blocks',
    );
    dataset.timeSeries = TimeSeriesData(
      samples: List<double>.generate(10, (int index) => index.toDouble()),
      sampleRate: 1.0,
      channelLabels: const <String>['Cz'],
      markers: const <TimeMarker>[
        TimeMarker(
          onsetMicros: 0,
          durationMicros: 2000000,
          label: 'Condition A',
          markerType: MarkerType.window,
        ),
        TimeMarker(
          onsetMicros: 2000000,
          durationMicros: 2000000,
          label: 'Condition B',
          markerType: MarkerType.window,
        ),
        TimeMarker(
          onsetMicros: 4000000,
          durationMicros: 2000000,
          label: 'Condition A',
          markerType: MarkerType.window,
        ),
        TimeMarker(
          onsetMicros: 6000000,
          durationMicros: 2000000,
          label: 'Condition B',
          markerType: MarkerType.window,
        ),
      ],
    );
    final Map<String, dynamic> params = <String, dynamic>{
      'mode': 'blocks',
      'includedMarkers': <String, dynamic>{
        'window|Condition A': true,
        'window|Condition B': true,
      },
      'blockConcatenate': false,
      'blockInvert': false,
    };

    await SegmentationNodeType().run(dataset, params);
    expect(
      dataset.segmentedTimeSeries!.segments
          .map((SignalSegmentData segment) => segment.label)
          .toList(growable: false),
      <String>['Condition A', 'Condition B', 'Condition A', 'Condition B'],
    );

    params['blockConcatenate'] = true;
    await SegmentationNodeType().run(dataset, params);

    final List<SignalSegmentData> concatenated =
        dataset.segmentedTimeSeries!.segments;
    expect(
      concatenated.map((SignalSegmentData segment) => segment.label),
      <String>['Condition A', 'Condition B'],
    );
    expect(concatenated[0].primaryChannel, <double>[0, 1, 4, 5]);
    expect(concatenated[1].primaryChannel, <double>[2, 3, 6, 7]);
  });

  test('realign node shifts segmented artifacts back into alignment', () async {
    final List<double> reference = List<double>.filled(64, 0.0);
    reference[20] = 5.0;
    reference[21] = 2.5;
    final List<double> shifted = List<double>.filled(64, 0.0);
    shifted[24] = 5.0;
    shifted[25] = 2.5;

    final Dataset dataset = Dataset('realign', label: 'Realign');
    dataset.segmentedTimeSeries = SegmentedTimeSeriesData(
      sampleRate: 1000.0,
      channelLabels: const <String>['Cz'],
      segments: <SignalSegmentData>[
        SignalSegmentData(
          channelSamples: <List<double>>[reference],
          startSeconds: 0.0,
          stopSeconds: 0.064,
          label: 'A',
          kind: 'event',
        ),
        SignalSegmentData(
          channelSamples: <List<double>>[shifted],
          startSeconds: 0.1,
          stopSeconds: 0.164,
          label: 'B',
          kind: 'event',
        ),
      ],
    );

    await RealignNodeType().run(dataset, <String, dynamic>{
      'upsampleRateHz': 100000.0,
      'method': 'cubic_spline',
      'maxShiftMs': 10.0,
    });

    final SegmentedTimeSeriesData? aligned = dataset.segmentedTimeSeries;
    expect(aligned, isNotNull);
    final int referencePeak = aligned!.segments.first.primaryChannel.indexOf(
      aligned.segments.first.primaryChannel.reduce(math.max),
    );
    final int shiftedPeak = aligned.segments.last.primaryChannel.indexOf(
      aligned.segments.last.primaryChannel.reduce(math.max),
    );
    expect((shiftedPeak - referencePeak).abs(), lessThanOrEqualTo(1));
    expect(aligned.segments.last.appliedShiftMs.abs(), greaterThan(0.5));
  });

  test(
    'sleep staging node adds WAKE/REM/SWS markers without changing signal',
    () async {
      final Dataset dataset = Dataset('sleep', label: 'Sleep');
      final List<double> samples = List<double>.generate(
        120,
        (int index) => math.sin(index / 10.0),
      );
      dataset.timeSeries = TimeSeriesData(
        samples: samples,
        sampleRate: 1.0,
        markers: const <TimeMarker>[
          TimeMarker(
            onsetMicros: 5 * 1000000,
            label: 'Existing',
            markerType: MarkerType.event,
          ),
        ],
      );

      await SleepStagingNodeType().run(dataset, <String, dynamic>{
        'epochSeconds': 30.0,
        'stagePattern': 'WAKE,SWS,REM',
      });

      final TimeSeriesData? staged = dataset.timeSeries;
      expect(staged, isNotNull);
      expect(staged!.primaryChannel, samples);
      expect(
        staged.markers.any((TimeMarker marker) => marker.label == 'Existing'),
        isTrue,
      );
      final List<TimeMarker> sleepMarkers = staged.markers
          .where(isSleepStageMarker)
          .toList(growable: false);
      expect(sleepMarkers, hasLength(4));
      expect(
        sleepMarkers.map((TimeMarker marker) => marker.label).toList(),
        <String>['WAKE', 'SWS', 'REM', 'WAKE'],
      );
      expect(
        sleepMarkers.every(
          (TimeMarker marker) => marker.markerType == MarkerType.window,
        ),
        isTrue,
      );
    },
  );

  test(
    'recode markers node renames selected marker labels and leaves others alone',
    () async {
      final Dataset dataset = Dataset('recode', label: 'Recode');
      dataset.timeSeries = TimeSeriesData(
        samples: List<double>.generate(32, (int index) => index.toDouble()),
        sampleRate: 256.0,
        markers: const <TimeMarker>[
          TimeMarker(onsetMicros: 0, label: '1', markerType: MarkerType.event),
          TimeMarker(
            onsetMicros: 1000000,
            label: '2',
            markerType: MarkerType.event,
          ),
          TimeMarker(
            onsetMicros: 2000000,
            label: '1',
            markerType: MarkerType.event,
          ),
        ],
      );

      await RecodeMarkersNodeType().run(dataset, <String, dynamic>{
        'recodeMap': <String, dynamic>{'event|1': 'Target'},
      });

      expect(
        dataset.timeSeries!.markers
            .map((TimeMarker marker) => marker.label)
            .toList(),
        <String>['Target', '2', 'Target'],
      );
    },
  );

  test('marker boundaries combine into blocks without dropping orphans', () {
    final List<TimeMarker> markers = <TimeMarker>[
      const TimeMarker(onsetMicros: 500, label: 'Stop'),
      const TimeMarker(onsetMicros: 1000, label: 'Start'),
      const TimeMarker(onsetMicros: 2500, label: 'Stop'),
      const TimeMarker(onsetMicros: 3000, label: 'Note'),
      const TimeMarker(onsetMicros: 4000, label: 'Start'),
      const TimeMarker(onsetMicros: 7000, label: 'Stop'),
      const TimeMarker(onsetMicros: 9000, label: 'Start'),
    ];

    final MarkerBoundaryCombinationResult result =
        AddRemoveMarkersNodeType.combineBoundaryMarkers(
          markers,
          startLabel: 'Start',
          stopLabel: 'Stop',
          blockLabel: 'Task block',
        );

    expect(result.combinedCount, 2);
    expect(result.unmatchedStartCount, 1);
    expect(result.unmatchedStopCount, 1);
    final List<TimeMarker> blocks = result.markers
        .where((TimeMarker marker) => marker.label == 'Task block')
        .toList(growable: false);
    expect(blocks, hasLength(2));
    expect(blocks.first.onsetMicros, 1000);
    expect(blocks.first.durationMicros, 1500);
    expect(blocks.first.markerType, MarkerType.window);
    expect(blocks.last.onsetMicros, 4000);
    expect(blocks.last.durationMicros, 3000);
    expect(
      result.markers
          .where((TimeMarker marker) => marker.label == 'Start')
          .map((TimeMarker marker) => marker.onsetMicros),
      <int>[9000],
    );
    expect(
      result.markers
          .where((TimeMarker marker) => marker.label == 'Stop')
          .map((TimeMarker marker) => marker.onsetMicros),
      <int>[500],
    );
    expect(
      result.markers.any((TimeMarker marker) => marker.label == 'Note'),
      isTrue,
    );
  });

  test(
    'FOOOF node estimates aperiodic fit and detects oscillatory peaks',
    () async {
      final Dataset dataset = Dataset('fooof', label: 'FOOOF');
      final List<double> freqs = List<double>.generate(
        80,
        (int index) => index + 1.0,
      );
      final List<double> power = freqs
          .map((double frequency) {
            final double aperiodic = 1 / math.pow(frequency, 1.5);
            final double alphaPeak =
                0.8 * math.exp(-math.pow((frequency - 10.0) / 2.0, 2));
            final double betaPeak =
                0.35 * math.exp(-math.pow((frequency - 20.0) / 2.8, 2));
            return aperiodic + alphaPeak + betaPeak;
          })
          .toList(growable: false);

      dataset.spectrum = FrequencySpectrumData(
        frequencies: freqs,
        power: power,
        source: 'synthetic',
      );

      await FooofNodeType().run(dataset, <String, dynamic>{
        'fLow': 1.0,
        'fHigh': 40.0,
        'maxPeaks': 4,
        'minPeakAmplitude': 0.03,
      });

      final FooofResultData? result = dataset.fooofResult;
      expect(result, isNotNull);
      expect(result!.exponent, closeTo(1.5, 0.7));
      expect(result.peaks, isNotEmpty);
      expect(
        result.peaks.any(
          (FooofPeakData peak) => (peak.centerFrequencyHz - 10.0).abs() < 2.0,
        ),
        isTrue,
      );
    },
  );

  test(
    'eye blinks node preserves signal and existing markers while placeholder detection is off',
    () async {
      final Dataset dataset = Dataset('eye', label: 'Eye');
      final List<double> samples = List<double>.generate(
        32,
        (int index) => index.toDouble(),
      );
      const TimeMarker existing = TimeMarker(
        onsetMicros: 1000000,
        label: 'Existing',
        markerType: MarkerType.event,
      );
      dataset.timeSeries = TimeSeriesData(
        samples: samples,
        sampleRate: 256.0,
        markers: const <TimeMarker>[existing],
      );

      await EyeBlinksNodeType().run(dataset, <String, dynamic>{
        'detectBlink': true,
        'detectSaccadeVertical': true,
        'detectSaccadeHorizontal': true,
      });

      final TimeSeriesData? result = dataset.timeSeries;
      expect(result, isNotNull);
      expect(result!.primaryChannel, samples);
      expect(result.markers, const <TimeMarker>[existing]);
      expect(dataset.ram['eye_blinks.params'], isA<Map<String, dynamic>>());
    },
  );

  test('interactive artifact detection builds candidates from exemplars', () {
    final List<double> samples = List<double>.filled(512, 0.0);
    const List<double> blinkShape = <double>[0.0, 1.0, 4.0, 7.0, 4.0, 1.0, 0.0];
    for (int index = 0; index < blinkShape.length; index++) {
      samples[100 + index] = blinkShape[index];
      samples[300 + index] = blinkShape[index];
    }

    final ArtifactDetectionComputation computation =
        InteractiveArtifactDetectionNodeType.recomputeDetectionsForDataset(
          datasetId: 'interactive',
          timeSeries: TimeSeriesData(samples: samples, sampleRate: 100.0),
          exemplars: const <ArtifactExemplarData>[
            ArtifactExemplarData(
              id: 'e1',
              datasetId: 'interactive',
              label: 'blink',
              onsetMicros: 1000000,
              durationMicros: 70000,
            ),
          ],
          existingCandidates: const <ArtifactCandidateData>[],
          threshold: 0.75,
        );

    expect(computation.templates, hasLength(1));
    expect(computation.templates.first.previewSamples, isNotEmpty);
    expect(computation.templates.first.previewChannels, isNotEmpty);
    expect(computation.templates.first.durationMicros, greaterThan(0));
    expect(
      computation.templates.first.previewSamples.length,
      lessThanOrEqualTo(160),
    );
    expect(computation.candidates, isNotEmpty);
    expect(
      computation.candidates.any(
        (ArtifactCandidateData candidate) =>
            candidate.label == 'blink' &&
            (candidate.onsetMicros - 3000000).abs() <= 30000,
      ),
      isTrue,
    );
  });

  test(
    'interactive artifact edit backend can compute templates without candidates',
    () {
      final List<double> samples = List<double>.filled(512, 0.0);
      const List<double> blinkShape = <double>[
        0.0,
        1.0,
        4.0,
        7.0,
        4.0,
        1.0,
        0.0,
      ];
      for (int index = 0; index < blinkShape.length; index++) {
        samples[100 + index] = blinkShape[index];
        samples[300 + index] = blinkShape[index];
      }

      final ArtifactDetectionComputation computation =
          InteractiveArtifactDetectionNodeType.recomputeDetectionsForDataset(
            datasetId: 'interactive',
            timeSeries: TimeSeriesData(samples: samples, sampleRate: 100.0),
            exemplars: const <ArtifactExemplarData>[
              ArtifactExemplarData(
                id: 'e1',
                datasetId: 'interactive',
                label: 'blink',
                onsetMicros: 1000000,
                durationMicros: 70000,
              ),
            ],
            existingCandidates: const <ArtifactCandidateData>[],
            threshold: 0.75,
            enableTemplateMatching: false,
          );

      expect(computation.templates, hasLength(1));
      expect(computation.candidates, isEmpty);
    },
  );

  test('interactive artifact matching survives cross-channel cancellation', () {
    const List<double> blinkShape = <double>[0.0, 1.0, 4.0, 7.0, 4.0, 1.0, 0.0];
    final List<List<double>> channels = List<List<double>>.generate(6, (
      int channelIndex,
    ) {
      final List<double> samples = List<double>.filled(512, 0.0);
      final double polarity = channelIndex < 3 ? 1.0 : -1.0;
      for (final int onset in <int>[100, 300]) {
        for (int index = 0; index < blinkShape.length; index++) {
          samples[onset + index] = blinkShape[index] * polarity;
        }
      }
      return samples;
    });

    final ArtifactDetectionComputation computation =
        InteractiveArtifactDetectionNodeType.recomputeDetectionsForDataset(
          datasetId: 'multichannel-cancellation',
          timeSeries: TimeSeriesData(
            channelSamples: channels,
            sampleRate: 100.0,
          ),
          exemplars: const <ArtifactExemplarData>[
            ArtifactExemplarData(
              id: 'e1',
              datasetId: 'multichannel-cancellation',
              label: 'blink',
              onsetMicros: 1000000,
              durationMicros: 70000,
            ),
          ],
          existingCandidates: const <ArtifactCandidateData>[],
          threshold: 0.75,
        );

    expect(
      computation.candidates.any(
        (ArtifactCandidateData candidate) =>
            (candidate.onsetMicros - 3000000).abs() <= 30000,
      ),
      isTrue,
    );
  });

  test(
    'interactive artifact template preview summarizes multichannel templates',
    () {
      final ArtifactDetectionComputation computation =
          InteractiveArtifactDetectionNodeType.recomputeDetectionsForDataset(
            datasetId: 'interactive',
            timeSeries: TimeSeriesData(
              channelSamples: const <List<double>>[
                <double>[2, 4, 3, 5],
                <double>[10, 12, 10, 14],
              ],
              sampleRate: 100.0,
              channelLabels: const <String>['Fz', 'Cz'],
            ),
            exemplars: const <ArtifactExemplarData>[
              ArtifactExemplarData(
                id: 'e1',
                datasetId: 'interactive',
                label: 'blink',
                onsetMicros: 0,
                durationMicros: 40000,
              ),
            ],
            existingCandidates: const <ArtifactCandidateData>[],
            threshold: 0.75,
          );

      expect(computation.templates, hasLength(1));
      expect(computation.templates.first.previewSamples, <double>[
        0,
        4,
        0.5,
        12.5,
      ]);
      expect(computation.templates.first.previewChannels, hasLength(2));
      expect(computation.templates.first.peakTopomapValues, <double>[
        -0.5,
        -1.5,
      ]);
    },
  );

  test('interactive artifact topomap snapshot centers channel baselines', () {
    final ArtifactDetectionComputation computation =
        InteractiveArtifactDetectionNodeType.recomputeDetectionsForDataset(
          datasetId: 'interactive',
          timeSeries: TimeSeriesData(
            channelSamples: const <List<double>>[
              <double>[100, 102, 100, 100],
              <double>[10, 10, 14, 10],
            ],
            sampleRate: 100.0,
            channelLabels: const <String>['Fz', 'Cz'],
          ),
          exemplars: const <ArtifactExemplarData>[
            ArtifactExemplarData(
              id: 'e1',
              datasetId: 'interactive',
              label: 'blink',
              onsetMicros: 0,
              durationMicros: 40000,
            ),
          ],
          existingCandidates: const <ArtifactCandidateData>[],
          threshold: 0.75,
        );

    expect(computation.templates, hasLength(1));
    expect(computation.templates.first.peakTopomapValues, <double>[-0.5, 3.0]);
  });

  test(
    'interactive artifact detection node merges accepted markers into output',
    () async {
      final Dataset dataset = Dataset('interactive-run', label: 'Interactive');
      dataset.timeSeries = TimeSeriesData(
        samples: List<double>.filled(64, 0.0),
        sampleRate: 100.0,
        markers: const <TimeMarker>[
          TimeMarker(
            onsetMicros: 500000,
            label: 'Existing',
            markerType: MarkerType.event,
          ),
        ],
      );

      await InteractiveArtifactDetectionNodeType().run(
        dataset,
        <String, dynamic>{
          'artifactExemplars': <Map<String, dynamic>>[
            const ArtifactExemplarData(
              id: 'e1',
              datasetId: 'interactive-run',
              label: 'blink',
              onsetMicros: 1000000,
              durationMicros: 50000,
            ).toJson(),
          ],
          'artifactCandidates': <Map<String, dynamic>>[
            const ArtifactCandidateData(
              id: 'c1',
              datasetId: 'interactive-run',
              label: 'motion',
              onsetMicros: 2000000,
              durationMicros: 80000,
              score: 0.9,
              status: InteractiveArtifactDetectionNodeType.acceptedStatus,
            ).toJson(),
            const ArtifactCandidateData(
              id: 'c2',
              datasetId: 'interactive-run',
              label: 'blink',
              onsetMicros: 3000000,
              durationMicros: 80000,
              score: 0.8,
              status: InteractiveArtifactDetectionNodeType.pendingStatus,
            ).toJson(),
          ],
          'artifactTemplates': <Map<String, dynamic>>[],
        },
      );

      final List<TimeMarker> markers = dataset.timeSeries!.markers;
      expect(
        markers.map((TimeMarker marker) => marker.label),
        contains('Existing'),
      );
      expect(
        markers.map((TimeMarker marker) => marker.label),
        contains('blink'),
      );
      expect(
        markers.map((TimeMarker marker) => marker.label),
        contains('motion'),
      );
      expect(
        markers.where((TimeMarker marker) => marker.label == 'blink').length,
        1,
      );
      expect(
        markers.where(
          (TimeMarker marker) =>
              marker.attributes['brainstory.artifactStatus'] == 'pending',
        ),
        isEmpty,
      );
    },
  );

  test(
    'spectral features node creates a CSV-ready feature table from PSD input',
    () async {
      final Dataset dataset = Dataset('features', label: 'Features');
      dataset.spectrum = FrequencySpectrumData(
        frequencies: const <double>[1, 3, 5, 7, 10, 20, 45],
        power: const <double>[1, 2, 3, 4, 5, 6, 7],
        source: 'synthetic_psd',
      );

      await SpectralFeaturesNodeType().run(dataset, <String, dynamic>{
        'powerFeatures': <String, dynamic>{
          'total_power': true,
          'delta_power': true,
          'theta_power': true,
          'alpha_power': true,
          'beta_power': true,
          'gamma_power': true,
        },
        'ratioFeatures': <String, dynamic>{
          'theta_alpha_ratio': true,
          'theta_beta_ratio': false,
          'alpha_beta_ratio': true,
          'delta_beta_ratio': false,
        },
      });

      final FeatureTableData? table = dataset.featureTable;
      expect(table, isNotNull);
      expect(table!.rows, hasLength(1));
      expect(
        table.columns,
        containsAll(<String>[
          'dataset',
          'total_power',
          'delta_power',
          'theta_power',
          'alpha_power',
          'beta_power',
          'gamma_power',
          'theta_alpha_ratio',
          'alpha_beta_ratio',
        ]),
      );
      expect(table.rows.first['dataset'], 'Features');
      expect(table.rows.first['delta_power'], '3.000000');
      expect(table.rows.first['theta_power'], '7.000000');
      expect(table.rows.first['alpha_power'], '5.000000');
      expect(table.rows.first['beta_power'], '6.000000');
      expect(table.rows.first['gamma_power'], '7.000000');
      expect(table.rows.first['theta_alpha_ratio'], '1.400000');
      expect(table.toCsv(), contains('theta_alpha_ratio'));
      expect(table.toCsv(), contains('Features'));
    },
  );

  test(
    'amplitude features node creates a CSV-ready feature table from time-domain input',
    () async {
      final Dataset dataset = Dataset('amplitude-features', label: 'Amplitude');
      dataset.timeSeries = TimeSeriesData(
        samples: const <double>[0.0, 1.0, 3.0, 2.0, 1.0],
        sampleRate: 1000.0,
        source: 'synthetic_signal',
      );

      await AmplitudeFeaturesNodeType().run(dataset, <String, dynamic>{
        'amplitudeFeatures': <String, dynamic>{
          'peak_amplitude': true,
          'peak_latency': true,
          'auc': true,
          'variance': true,
        },
      });

      final FeatureTableData? table = dataset.featureTable;
      expect(table, isNotNull);
      expect(table!.rows, hasLength(1));
      expect(
        table.columns,
        containsAll(<String>[
          'dataset',
          'peak_amplitude',
          'peak_latency_ms',
          'auc',
          'variance',
        ]),
      );
      expect(table.rows.first['dataset'], 'Amplitude');
      expect(table.rows.first['peak_amplitude'], '3.000000');
      expect(table.rows.first['peak_latency_ms'], '2.000000');
      expect(table.toCsv(), contains('peak_amplitude'));
    },
  );

  test(
    'machine learning placeholder nodes keep their category and params contract',
    () async {
      final Dataset dataset = Dataset('ml', label: 'ML');

      await KMeansNodeType().run(dataset, <String, dynamic>{
        'clusterCount': 5,
        'featureSource': 'segment_rms',
      });
      await CNNNodeType().run(dataset, <String, dynamic>{
        'architecture': 'artifact_detection',
        'outputMode': 'probabilities',
      });

      expect(KMeansNodeType().category, NodeCategory.machineLearning);
      expect(CNNNodeType().category, NodeCategory.machineLearning);
      expect(
        dataset.ram['machineLearning.kmeans.params'],
        isA<Map<String, dynamic>>(),
      );
      expect(
        dataset.ram['machineLearning.cnn.params'],
        isA<Map<String, dynamic>>(),
      );
    },
  );

  test(
    'bridge detector computes one correlation matrix per full minute using the last 1000 samples',
    () async {
      final List<double> channelA = List<double>.generate(
        60000,
        (int index) => (index % 1000).toDouble(),
        growable: false,
      );
      final List<double> channelB = List<double>.generate(
        60000,
        (int index) => (index % 1000).toDouble(),
        growable: false,
      );

      final TimeSeriesData timeSeries = TimeSeriesData(
        channelSamples: <List<double>>[channelA, channelB],
        sampleRate: 500.0,
        channelLabels: const <String>['Fz', 'Cz'],
        source: 'synthetic_bridge',
      );
      final BridgeDetectionData result = computeBridgeDetection(
        timeSeries,
        windowSamples: 1000,
      );

      expect(result.frameCount, 2);
      expect(result.channelCount, 2);
      expect(result.valueCount, 8);
      expect(result.frames.first.minuteIndex, 1);
      expect(result.frames.first.startSample, 29000);
      expect(result.frames.first.endSampleExclusive, 30000);
      expect(result.frames.last.minuteIndex, 2);
      expect(result.frames.last.startSample, 59000);
      expect(result.frames.last.endSampleExclusive, 60000);
      expect(result.frames.first.correlationMatrix[0][1], closeTo(1.0, 0.0001));
    },
  );

  test(
    'time marker defaults to all channels when no explicit mask is stored',
    () {
      const TimeMarker marker = TimeMarker(
        onsetMicros: 0,
        label: 'blink',
        markerType: MarkerType.artifact,
      );

      expect(marker.applicableChannels(4), <int>[1, 1, 1, 1]);
    },
  );

  test('marker change serializes add/remove/change rows', () {
    final MarkerChange change = MarkerChange(
      rows: <MarkerChangeEntry>[
        const MarkerChangeEntry(
          dataset: 'example.edf[#2]',
          changeType: MarkerChangeType.add,
          newLabel: 'blink',
          newOnsetMicros: 1250000,
          newDurationMicros: 180000,
        ),
        const MarkerChangeEntry(
          dataset: 'example.edf[#3]',
          changeType: MarkerChangeType.remove,
          oldLabel: 'artifact',
          oldOnsetMicros: 500000,
          oldDurationMicros: 40000,
        ),
        const MarkerChangeEntry(
          dataset: 'example.edf[#4]',
          changeType: MarkerChangeType.change,
          oldLabel: 'blink',
          oldOnsetMicros: 1000,
          oldDurationMicros: 2000,
          newLabel: 'saccade_vertical',
          newOnsetMicros: 1500,
          newDurationMicros: 2200,
        ),
      ],
    );

    final MarkerChange decoded = MarkerChange.fromJson(change.toJson());

    expect(decoded.rows, hasLength(3));
    expect(decoded.rows[0].changeType, MarkerChangeType.add);
    expect(decoded.rows[0].oldLabel, isNull);
    expect(decoded.rows[1].newLabel, isNull);
    expect(decoded.rows[2].newLabel, 'saccade_vertical');
  });

  test('node model starts with an empty marker change table', () {
    final NodeModel node = NodeModel(
      id: 'node-1',
      type: ImportNodeType(),
      position: Offset.zero,
      params: <String, dynamic>{},
    );

    expect(node.markerChange.isEmpty, isTrue);
    expect(node.markerChange.rows, isEmpty);
  });
}

double _singleFrequencyPower(
  List<double> samples,
  double sampleRate,
  double frequency,
) {
  final int start = samples.length ~/ 2;
  double real = 0.0;
  double imaginary = 0.0;
  for (int i = start; i < samples.length; i++) {
    final double phase = 2 * math.pi * frequency * i / sampleRate;
    real += samples[i] * math.cos(phase);
    imaginary -= samples[i] * math.sin(phase);
  }
  final int count = samples.length - start;
  return (real * real + imaginary * imaginary) / (count * count);
}
