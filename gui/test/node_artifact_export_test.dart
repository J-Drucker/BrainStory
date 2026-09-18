import 'dart:convert';

import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/nodes/node_type.dart';
import 'package:brainstory_gui/platform/node_artifact_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset dataset;

  setUp(() {
    dataset = Dataset('dataset-1', label: 'Oddball')
      ..path = '/data/oddball.cnt'
      ..loaded = true
      ..timeSeries = TimeSeriesData(
        channelSamples: const <List<double>>[
          <double>[1.0, 2.0],
          <double>[3.0, 4.0],
        ],
        sampleRate: 100.0,
        channelLabels: <String>['Fz', 'Pz'],
      );
  });

  test('long JSON flattens an artifact into path/value records', () {
    final String text = buildNodeArtifactExportText(
      datasets: <Dataset>[dataset],
      selections: const <NodeArtifactExportSelection>{
        NodeArtifactExportSelection(
          datasetId: 'dataset-1',
          artifact: NodePersistenceArtifact.channelNames,
        ),
      },
      format: NodeArtifactExportFormat.json,
      shape: NodeArtifactExportShape.long,
    );

    final List<dynamic> rows = jsonDecode(text) as List<dynamic>;
    expect(rows, hasLength(2));
    expect(rows.first['artifact'], 'channelNames');
    expect(rows.first['path'], '[0]');
    expect(rows.first['value'], 'Fz');
  });

  test('wide CSV separates combined artifacts with a blank row', () {
    final String text = buildNodeArtifactExportText(
      datasets: <Dataset>[dataset],
      selections: const <NodeArtifactExportSelection>{
        NodeArtifactExportSelection(
          datasetId: 'dataset-1',
          artifact: NodePersistenceArtifact.channelNames,
        ),
        NodeArtifactExportSelection(
          datasetId: 'dataset-1',
          artifact: NodePersistenceArtifact.metadata,
        ),
      },
      format: NodeArtifactExportFormat.csv,
      shape: NodeArtifactExportShape.wide,
    );

    expect(text, contains('\n\n'));
    expect(text, contains('"channelNames"'));
    expect(text, contains('"metadata"'));
  });

  test('wide JSON inserts an empty object between artifact blocks', () {
    final String text = buildNodeArtifactExportText(
      datasets: <Dataset>[dataset],
      selections: const <NodeArtifactExportSelection>{
        NodeArtifactExportSelection(
          datasetId: 'dataset-1',
          artifact: NodePersistenceArtifact.channelNames,
        ),
        NodeArtifactExportSelection(
          datasetId: 'dataset-1',
          artifact: NodePersistenceArtifact.metadata,
        ),
      },
      format: NodeArtifactExportFormat.json,
      shape: NodeArtifactExportShape.wide,
    );

    final List<dynamic> blocks = jsonDecode(text) as List<dynamic>;
    expect(blocks, hasLength(3));
    expect(blocks[1], isEmpty);
  });
}
