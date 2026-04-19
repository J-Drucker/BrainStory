import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_artifact_snapshot.dart';
import 'package:brainstory_gui/model/dataset_state.dart';
import 'package:brainstory_gui/model/node.dart';
import 'package:brainstory_gui/nodes/bandpass_node.dart';
import 'package:brainstory_gui/nodes/bridge_detector_node.dart';
import 'package:brainstory_gui/nodes/channel_coordinates_node.dart';
import 'package:brainstory_gui/nodes/channel_exclusion_node.dart';
import 'package:brainstory_gui/nodes/edit_channels_node.dart';
import 'package:brainstory_gui/nodes/amplitude_features_node.dart';
import 'package:brainstory_gui/nodes/export_edf_node.dart';
import 'package:brainstory_gui/nodes/eye_blinks_node.dart';
import 'package:brainstory_gui/nodes/fooof_node.dart';
import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/nodes/interactive_artifact_detection_node.dart';
import 'package:brainstory_gui/nodes/machine_learning_nodes.dart';
import 'package:brainstory_gui/nodes/node_type.dart';
import 'package:brainstory_gui/nodes/psd_node.dart';
import 'package:brainstory_gui/nodes/recode_markers_node.dart';
import 'package:brainstory_gui/nodes/realign_node.dart';
import 'package:brainstory_gui/nodes/resample_node.dart';
import 'package:brainstory_gui/nodes/segmentation_node.dart';
import 'package:brainstory_gui/nodes/sleep_staging_node.dart';
import 'package:brainstory_gui/nodes/spectral_features_node.dart';
import 'package:brainstory_gui/platform/ant_cnt_import.dart';
import 'package:brainstory_gui/ui/canvas_logic.dart';
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

    final ArtifactIdentity restoredIdentity =
        ArtifactIdentity.fromJson(identity.toJson());
    final ArtifactChangeSet restoredChangeSet =
        ArtifactChangeSet.fromJson(changeSet.toJson());

    expect(restoredIdentity.artifactId, identity.artifactId);
    expect(restoredIdentity.kind, BrainStoryArtifactKind.timeSeries);
    expect(restoredIdentity.sourceArtifactIds.single,
        'artifact-node-1-dataset-1-signal');
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
    final DatasetArtifactSnapshot restored =
        DatasetArtifactSnapshot.fromJson(snapshot.toJson());
    final Dataset target = Dataset('dataset-1', label: 'Target');

    restored.applyToDataset(target);

    expect(
      restored.artifactIdentities[BrainStoryArtifactKind.timeSeries]!.artifactId,
      'node-1-dataset-1-time-series',
    );
    expect(
      target.artifactIdentityFor(BrainStoryArtifactKind.timeSeries)!.producerNodeId,
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
          '1': <String, dynamic>{
            'remove': true,
            'removeMode': 'delete',
          },
        },
      },
    );

    expect(changeSet.touchesChannelTopology, isTrue);
    expect(changeSet.touchesSamples, isTrue);
    expect(changeSet.affectedChannelLabels, <String>['Cz']);
    expect(changeSet.affectedChannelIndices, <int>[1]);
  });

  test('channel removal marks downstream signal nodes stale', () async {
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
          '1': <String, dynamic>{
            'remove': true,
            'removeMode': 'delete',
          },
        },
      },
    );

    await logic.runThisStep(editNode.id, datasetIds: <String>{dataset.id});

    expect(editNode.datasetStates[dataset.id], DatasetState.done);
    expect(psdNode.datasetStates[dataset.id], DatasetState.stale);
    expect(dataset.timeSeries!.channelLabels, <String>['Fz']);
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

    final ArtifactIdentity? spectrumIdentity =
        dataset.artifactIdentityFor(BrainStoryArtifactKind.spectrum);
    expect(spectrumIdentity, isNotNull);
    expect(spectrumIdentity!.producerNodeId, psdNode.id);
    expect(spectrumIdentity.datasetId, dataset.id);
    expect(spectrumIdentity.artifactId,
        '${psdNode.id}:${dataset.id}:spectrum');
    expect(
      spectrumIdentity.sourceArtifactIds,
      contains('import-node:dataset-1:timeSeries'),
    );
    expect(
      dataset.artifactIdentityFor(BrainStoryArtifactKind.timeSeries)!.producerNodeId,
      'import-node',
    );
  });

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

    final Dataset segmentationView =
        await logic.materializedDatasetViewForNode(segmentationNode.id, dataset);
    final Dataset siblingView =
        await logic.materializedDatasetViewForNode(psdNode.id, dataset);

    expect(segmentationView.segmentedTimeSeries, isNotNull);
    expect(siblingView.segmentedTimeSeries, isNull);
    expect(siblingView.timeSeries, isNotNull);
  });

  test('canvas undo reverses saved marker edits from visualization', () {
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

    logic.applyMarkersFromVisualization(
      nodeId: sourceNodeId,
      dataset: dataset,
      rawMarkers: <Map<String, dynamic>>[
        <String, dynamic>{
          'datasetId': dataset.id,
          'label': 'blink',
          'onsetMicros': 1000,
          'durationMicros': 500,
          'markerType': MarkerType.artifact,
        },
      ],
    );

    expect(dataset.timeSeries?.markers, hasLength(1));
    expect(logic.nodes.map((NodeModel node) => node.title), contains('Add/Remove Markers'));

    expect(logic.undoLast(), 'save marker edits');

    expect(dataset.timeSeries?.markers, isEmpty);
    expect(logic.nodes.map((NodeModel node) => node.title), isNot(contains('Add/Remove Markers')));
  });

  test('visualizer channel drop materializes the generated edit node output', () async {
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
    final String sourceNodeId = logic.nodes.single.id;

    logic.applyChannelEditsFromVisualization(
      nodeId: sourceNodeId,
      dataset: dataset,
      datasetConfig: <String, dynamic>{
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

    final NodeModel editNode = logic.nodes.firstWhere(
      (NodeModel node) => node.title == 'Edit Channels',
    );
    final Dataset materialized =
        await logic.materializedDatasetViewForNode(editNode.id, dataset);

    expect(editNode.title, 'Edit Channels');
    expect(dataset.timeSeries!.channelLabels, <String>['Fz']);
    expect(materialized.timeSeries!.channelLabels, <String>['Fz']);
    expect(materialized.timeSeries!.channelSamples, hasLength(1));
  });

  test('channel coordinates parse millimeter table and match decorated labels', () {
    const String csv = '''
channel,x,y,z
Fpz,-0.11,112.43,41.36
Cz,0.32,3.4,147.92
''';
    final Map<String, ChannelCoordinate> coordinates =
        ChannelCoordinatesNodeType.parseChannelCoordinateCsv(csv);

    final ChannelCoordinate? fpz = ChannelCoordinatesNodeType.coordinateForChannelLabel(
      coordinates,
      'Fpz - AVG',
    );
    final ChannelCoordinate? cz = ChannelCoordinatesNodeType.coordinateForChannelLabel(
      coordinates,
      'Cz_ref',
    );

    expect(fpz, isNotNull);
    expect(fpz!.label, 'Fpz');
    expect(fpz.y, 112.43);
    expect(fpz.units, 'mm');
    expect(cz, isNotNull);
    expect(cz!.z, 147.92);
  });

  test('channel coordinates node assigns standard coordinates from asset', () async {
    final Dataset dataset = Dataset('coords', label: 'Coords');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: const <List<double>>[
        <double>[1, 2, 3],
        <double>[4, 5, 6],
      ],
      sampleRate: 1000,
      channelLabels: const <String>['Fpz - AVG', 'NotAnElectrode'],
    );

    await ChannelCoordinatesNodeType().run(dataset, <String, dynamic>{
      'mode': 'standard',
    });

    final Map<String, ChannelCoordinate> coordinates =
        dataset.timeSeries!.channelCoordinates;
    expect(coordinates.keys, contains('Fpz - AVG'));
    expect(coordinates['Fpz - AVG']!.label, 'Fpz - AVG');
    expect(coordinates['Fpz - AVG']!.units, 'mm');
    expect(coordinates.keys, isNot(contains('NotAnElectrode')));
    expect(dataset.ram['channelCoordinates.params'], isA<Map<String, dynamic>>());
  });

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

  test('suppressSpikes replaces isolated outliers with neighborhood median', () {
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
  });

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

  test('PSD node uses the primary channel when time series is multichannel', () async {
    final Dataset dataset = Dataset('psd-multichannel', label: 'Multi');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: <List<double>>[
        List<double>.generate(256, (int i) {
          final double t = i / 256.0;
          return math.sin(2 * math.pi * 10 * t);
        }),
        List<double>.filled(256, 0.0),
      ],
      sampleRate: 256.0,
      channelLabels: const <String>['Fz', 'Cz'],
    );

    await PSDNodeType().run(dataset, <String, dynamic>{
      'fLow': 1.0,
      'fHigh': 40.0,
      'outputMode': 'averaged',
    });

    expect(dataset.spectrum, isNotNull);
    expect(dataset.spectrum!.frequencies, isNotEmpty);
    expect(dataset.spectrum!.power, isNotEmpty);
  });

  test('Edit Channels node can rename, delete, and build derived channels', () async {
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
    expect(dataset.timeSeries!.channelLabels, <String>['Frontal', 'Pz', 'Difference']);
    expect(
      dataset.timeSeries!.channelSamples[2],
      <double>[4.0 / 3.0, 5.0 / 3.0, 2.0],
    );
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
    final Directory tempDir =
        await Directory.systemTemp.createTemp('brainstory_bv_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final File vhdrFile = File('${tempDir.path}\\sample.vhdr');
    final File eegFile = File('${tempDir.path}\\sample.eeg');
    final File vmrkFile = File('${tempDir.path}\\sample.vmrk');

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

    final AntCntImportData parsed = parseAntCntPayload(
      <String, dynamic>{
        'sourceDescription': 'sample.cnt',
        'sampleRate': 500.0,
        'channelCount': 2,
        'sampleCount': 3,
        'channelLabels': <String>['Fp1', 'Fp2'],
        'markers': <Map<String, dynamic>>[
          <String, dynamic>{
            'label': 'Stim',
            'onsetMicros': 2000,
            'durationMicros': 0,
            'markerType': MarkerType.event,
          },
        ],
      },
      bytes.toBytes(),
    );

    expect(parsed.sourceDescription, 'sample.cnt');
    expect(parsed.sampleRate, 500.0);
    expect(parsed.channelLabels, <String>['Fp1', 'Fp2']);
    expect(parsed.channelSamples, <List<double>>[
      <double>[1, 2, 3],
      <double>[4, 5, 6],
    ]);
    expect(parsed.markers.single.label, 'Stim');
    expect(parsed.markers.single.onsetMicros, 2000);
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

  test('buildEdfBytes round-trips multiple channels through EDF parsing', () async {
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
    expect(parsed.channelSamples.first.first, closeTo(channelOne.first, 0.05));
    expect(parsed.channelSamples.last.first, closeTo(channelTwo.first, 0.05));
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

  test('resolveTextExportFile builds a csv filename next to the source file', () {
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
  });

  test('factor resolves the matching level for a marker key', () {
    const Factor factor = Factor(
      name: 'Condition',
      levels: <FactorLevel>[
        FactorLevel(
          name: 'Target',
          markerKeys: <String>{'stim/target', 'stim/go'},
        ),
        FactorLevel(
          name: 'Non-target',
          markerKeys: <String>{'stim/nontarget'},
        ),
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
        FactorLevel(
          name: 'Clean',
          markerKeys: <String>{'segment/keep'},
        ),
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
    expect(
      segment.anchorTimeSeconds,
      closeTo(0.5, 0.0001),
    );
  });

  test('segmented snapshots materialize source-window samples for persistence', () async {
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

    final Map<String, dynamic> json =
        DatasetArtifactSnapshot.fromDataset(dataset).toJson();
    final DatasetArtifactSnapshot restored =
        DatasetArtifactSnapshot.fromJson(json);

    expect(restored.segmentedTimeSeries, isNotNull);
    expect(
      restored.segmentedTimeSeries!.segments.first.channelSamples.single,
      List<double>.generate(20, (int index) => (40 + index).toDouble()),
    );
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
    final int referencePeak =
        aligned!.segments.first.primaryChannel.indexOf(aligned.segments.first.primaryChannel.reduce(math.max));
    final int shiftedPeak =
        aligned.segments.last.primaryChannel.indexOf(aligned.segments.last.primaryChannel.reduce(math.max));
    expect((shiftedPeak - referencePeak).abs(), lessThanOrEqualTo(1));
    expect(aligned.segments.last.appliedShiftMs.abs(), greaterThan(0.5));
  });

  test('sleep staging node adds WAKE/REM/SWS markers without changing signal', () async {
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
    final List<TimeMarker> sleepMarkers =
        staged.markers.where(isSleepStageMarker).toList(growable: false);
    expect(sleepMarkers, hasLength(4));
    expect(
      sleepMarkers.map((TimeMarker marker) => marker.label).toList(),
      <String>['WAKE', 'SWS', 'REM', 'WAKE'],
    );
    expect(sleepMarkers.every((TimeMarker marker) => marker.markerType == MarkerType.window), isTrue);
  });

  test('recode markers node renames selected marker labels and leaves others alone', () async {
    final Dataset dataset = Dataset('recode', label: 'Recode');
    dataset.timeSeries = TimeSeriesData(
      samples: List<double>.generate(32, (int index) => index.toDouble()),
      sampleRate: 256.0,
      markers: const <TimeMarker>[
        TimeMarker(
          onsetMicros: 0,
          label: '1',
          markerType: MarkerType.event,
        ),
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
      'recodeMap': <String, dynamic>{
        'event|1': 'Target',
      },
    });

    expect(
      dataset.timeSeries!.markers.map((TimeMarker marker) => marker.label).toList(),
      <String>['Target', '2', 'Target'],
    );
  });

  test('FOOOF node estimates aperiodic fit and detects oscillatory peaks', () async {
    final Dataset dataset = Dataset('fooof', label: 'FOOOF');
    final List<double> freqs = List<double>.generate(
      80,
      (int index) => index + 1.0,
    );
    final List<double> power = freqs.map((double frequency) {
      final double aperiodic = 1 / math.pow(frequency, 1.5);
      final double alphaPeak = 0.8 * math.exp(-math.pow((frequency - 10.0) / 2.0, 2));
      final double betaPeak = 0.35 * math.exp(-math.pow((frequency - 20.0) / 2.8, 2));
      return aperiodic + alphaPeak + betaPeak;
    }).toList(growable: false);

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
  });

  test('eye blinks node preserves signal and existing markers while placeholder detection is off', () async {
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
  });

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
      timeSeries: TimeSeriesData(
        samples: samples,
        sampleRate: 100.0,
      ),
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
    expect(computation.templates.first.previewSamples.length, lessThanOrEqualTo(160));
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

  test('interactive artifact template preview summarizes multichannel templates', () {
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
    expect(
      computation.templates.first.previewSamples,
      <double>[0, 4, 0.5, 12.5],
    );
    expect(computation.templates.first.previewChannels, hasLength(2));
  });

  test('interactive artifact detection node merges accepted markers into output', () async {
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

    await InteractiveArtifactDetectionNodeType().run(dataset, <String, dynamic>{
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
    });

    final List<TimeMarker> markers = dataset.timeSeries!.markers;
    expect(markers.map((TimeMarker marker) => marker.label), contains('Existing'));
    expect(markers.map((TimeMarker marker) => marker.label), contains('blink'));
    expect(markers.map((TimeMarker marker) => marker.label), contains('motion'));
    expect(
      markers.where((TimeMarker marker) => marker.label == 'blink').length,
      1,
    );
    expect(
      markers.where((TimeMarker marker) => marker.attributes['brainstory.artifactStatus'] == 'pending'),
      isEmpty,
    );
  });

  test('spectral features node creates a CSV-ready feature table from PSD input', () async {
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
    expect(table.columns, containsAll(<String>[
      'dataset',
      'total_power',
      'delta_power',
      'theta_power',
      'alpha_power',
      'beta_power',
      'gamma_power',
      'theta_alpha_ratio',
      'alpha_beta_ratio',
    ]));
    expect(table.rows.first['dataset'], 'Features');
    expect(table.rows.first['delta_power'], '3.000000');
    expect(table.rows.first['theta_power'], '7.000000');
    expect(table.rows.first['alpha_power'], '5.000000');
    expect(table.rows.first['beta_power'], '6.000000');
    expect(table.rows.first['gamma_power'], '7.000000');
    expect(table.rows.first['theta_alpha_ratio'], '1.400000');
    expect(table.toCsv(), contains('theta_alpha_ratio'));
    expect(table.toCsv(), contains('Features'));
  });

  test('amplitude features node creates a CSV-ready feature table from time-domain input', () async {
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
    expect(table.columns, containsAll(<String>[
      'dataset',
      'peak_amplitude',
      'peak_latency_ms',
      'auc',
      'variance',
    ]));
    expect(table.rows.first['dataset'], 'Amplitude');
    expect(table.rows.first['peak_amplitude'], '3.000000');
    expect(table.rows.first['peak_latency_ms'], '2.000000');
    expect(table.toCsv(), contains('peak_amplitude'));
  });

  test('machine learning placeholder nodes keep their category and params contract', () async {
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
  });

  test('bridge detector computes one correlation matrix per full minute using the last 1000 samples', () async {
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
  });

  test('time marker defaults to all channels when no explicit mask is stored', () {
    const TimeMarker marker = TimeMarker(
      onsetMicros: 0,
      label: 'blink',
      markerType: MarkerType.artifact,
    );

    expect(marker.applicableChannels(4), <int>[1, 1, 1, 1]);
  });

  test('channel exclusion mark bad adds a full-duration artifact marker with channel mask', () async {
    final Dataset dataset = Dataset('channel-exclusion', label: 'QC');
    dataset.timeSeries = TimeSeriesData(
      channelSamples: <List<double>>[
        List<double>.filled(100, 1.0),
        List<double>.filled(100, 2.0),
        List<double>.filled(100, 3.0),
      ],
      sampleRate: 100.0,
      channelLabels: const <String>['Fz', 'Cz', 'Pz'],
    );

    await ChannelExclusionNodeType().run(dataset, <String, dynamic>{
      'selectedChannels': <String>['Cz'],
      'action': 'mark_bad',
    });

    final TimeSeriesData? result = dataset.timeSeries;
    expect(result, isNotNull);
    final TimeMarker badChannel = result!.markers.last;
    expect(badChannel.label, 'bad channel');
    expect(badChannel.markerType, MarkerType.artifact);
    expect(badChannel.durationMicros, 1000000);
    expect(badChannel.channelMask, <int>[0, 1, 0]);
  });

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
