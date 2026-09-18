import 'dart:convert';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/node_type.dart';
import 'file_save.dart';

class NodeArtifactExportResult {
  const NodeArtifactExportResult({required this.locations});

  final List<String> locations;
}

Future<NodeArtifactExportResult> exportNodeArtifacts({
  required String nodeTitle,
  required List<Dataset> datasets,
  required Set<NodeArtifactExportSelection> selections,
  required NodeArtifactExportOptions options,
}) async {
  final List<_ExportItem> items = <_ExportItem>[];
  for (final Dataset dataset in datasets) {
    for (final NodeArtifactExportSelection selection in selections) {
      if (selection.datasetId != dataset.id) continue;
      items.add(
        _ExportItem(
          dataset: dataset,
          artifact: selection.artifact,
          value: _artifactValue(dataset, selection.artifact),
        ),
      );
    }
  }
  final List<_ExportItem> unavailable = items
      .where((_ExportItem item) => item.value == null)
      .toList(growable: false);
  if (unavailable.isNotEmpty) {
    final _ExportItem first = unavailable.first;
    throw StateError(
      '${first.artifact.name} is not available for ${first.dataset.label}.',
    );
  }
  final Map<String, List<_ExportItem>> groups = <String, List<_ExportItem>>{};
  for (final _ExportItem item in items) {
    final String datasetPart = options.separateDatasets
        ? _safeName(
            item.dataset.label.isEmpty ? item.dataset.id : item.dataset.label,
          )
        : 'datasets';
    final String artifactPart = options.separateArtifacts
        ? item.artifact.name
        : 'artifacts';
    groups
        .putIfAbsent('$datasetPart--$artifactPart', () => <_ExportItem>[])
        .add(item);
  }

  final List<String> locations = <String>[];
  for (final MapEntry<String, List<_ExportItem>> group in groups.entries) {
    for (final NodeArtifactExportFormat format in options.formats) {
      final String text = format == NodeArtifactExportFormat.json
          ? _jsonForItems(group.value, options.shape)
          : _csvForItems(group.value, options.shape);
      final SavedFileResult saved = await saveTextFile(
        text: text,
        suggestedBaseName: '${_safeName(nodeTitle)}--${group.key}',
        filenameSuffix: '',
        fileExtension: format.name,
        datasetPath: group.value.first.dataset.path,
        outputDirectory: '',
      );
      locations.add(saved.locationLabel);
    }
  }
  return NodeArtifactExportResult(locations: locations);
}

String buildNodeArtifactExportText({
  required List<Dataset> datasets,
  required Set<NodeArtifactExportSelection> selections,
  required NodeArtifactExportFormat format,
  required NodeArtifactExportShape shape,
}) {
  final List<_ExportItem> items = <_ExportItem>[
    for (final Dataset dataset in datasets)
      for (final NodeArtifactExportSelection selection in selections)
        if (selection.datasetId == dataset.id)
          _ExportItem(
            dataset: dataset,
            artifact: selection.artifact,
            value: _artifactValue(dataset, selection.artifact),
          ),
  ];
  return format == NodeArtifactExportFormat.json
      ? _jsonForItems(items, shape)
      : _csvForItems(items, shape);
}

class _ExportItem {
  const _ExportItem({
    required this.dataset,
    required this.artifact,
    required this.value,
  });

  final Dataset dataset;
  final NodePersistenceArtifact artifact;
  final Object? value;
}

Object? _artifactValue(Dataset dataset, NodePersistenceArtifact artifact) {
  final TimeSeriesData? timeSeries = dataset.timeSeries;
  return switch (artifact) {
    NodePersistenceArtifact.timeSeries => timeSeries?.toJson(),
    NodePersistenceArtifact.channelNames => timeSeries?.channelLabels,
    NodePersistenceArtifact.channelCoordinates =>
      timeSeries?.channelCoordinates.map(
        (String key, ChannelCoordinate value) => MapEntry(key, value.toJson()),
      ),
    NodePersistenceArtifact.impedance => timeSeries?.impedanceData?.toJson(),
    NodePersistenceArtifact.markers =>
      timeSeries?.markers
          .map((TimeMarker marker) => marker.toJson())
          .toList(growable: false),
    NodePersistenceArtifact.segmentedTimeSeries =>
      dataset.segmentedTimeSeries?.toJson(),
    NodePersistenceArtifact.spectrum => dataset.spectrum?.toJson(),
    NodePersistenceArtifact.fooofResult => dataset.fooofResult?.toJson(),
    NodePersistenceArtifact.featureTable => dataset.featureTable?.toJson(),
    NodePersistenceArtifact.gaussianMixture =>
      dataset.gaussianMixture?.toJson(),
    NodePersistenceArtifact.bridgeDetection =>
      dataset.bridgeDetection?.toJson(),
    NodePersistenceArtifact.timeFrequency => dataset.timeFrequency?.toJson(),
    NodePersistenceArtifact.matrixTransformation =>
      dataset.matrixTransformation?.toJson(),
    NodePersistenceArtifact.metadata => <String, dynamic>{
      'id': dataset.id,
      'label': dataset.label,
      'path': dataset.path,
      'loaded': dataset.loaded,
    },
  };
}

String _jsonForItems(List<_ExportItem> items, NodeArtifactExportShape shape) {
  if (shape == NodeArtifactExportShape.wide) {
    final List<Object?> blocks = <Object?>[];
    for (int index = 0; index < items.length; index++) {
      final _ExportItem item = items[index];
      blocks.add(<String, dynamic>{
        'dataset': item.dataset.label,
        'dataset_id': item.dataset.id,
        'artifact': item.artifact.name,
        'value': item.value,
      });
      if (index < items.length - 1) blocks.add(<String, dynamic>{});
    }
    return const JsonEncoder.withIndent('  ').convert(blocks);
  }
  return const JsonEncoder.withIndent(
    '  ',
  ).convert(items.expand(_longRowsForItem).toList(growable: false));
}

String _csvForItems(List<_ExportItem> items, NodeArtifactExportShape shape) {
  if (shape == NodeArtifactExportShape.wide) {
    return items
        .map((_ExportItem item) => _csvTable(_wideRowsForItem(item)))
        .join('\n\n');
  }
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (final _ExportItem item in items) {
    rows.addAll(_longRowsForItem(item));
  }
  return _csvTable(rows);
}

String _csvTable(List<Map<String, Object?>> rows) {
  final List<String> headers = <String>[];
  for (final Map<String, Object?> row in rows) {
    for (final String key in row.keys) {
      if (!headers.contains(key)) headers.add(key);
    }
  }
  return <String>[
    headers.map(_csvCell).join(','),
    for (final Map<String, Object?> row in rows)
      headers.map((String key) => _csvCell(row[key])).join(','),
  ].join('\n');
}

List<Map<String, Object?>> _longRowsForItem(_ExportItem item) {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  void walk(Object? value, String path) {
    if (value is Map) {
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        walk(
          entry.value,
          path.isEmpty ? entry.key.toString() : '$path.${entry.key}',
        );
      }
    } else if (value is List) {
      for (int index = 0; index < value.length; index++) {
        walk(value[index], '$path[$index]');
      }
    } else {
      rows.add(<String, Object?>{
        'dataset': item.dataset.label,
        'dataset_id': item.dataset.id,
        'artifact': item.artifact.name,
        'path': path,
        'value': value,
      });
    }
  }

  walk(item.value, '');
  return rows;
}

List<Map<String, Object?>> _wideRowsForItem(_ExportItem item) {
  if (item.value is List &&
      (item.value as List).every((Object? value) => value is Map)) {
    return (item.value as List)
        .map((Object? value) {
          return <String, Object?>{
            'dataset': item.dataset.label,
            'dataset_id': item.dataset.id,
            'artifact': item.artifact.name,
            for (final MapEntry<dynamic, dynamic> entry
                in (value as Map).entries)
              entry.key.toString(): _scalarOrJson(entry.value),
          };
        })
        .toList(growable: false);
  }
  if (item.value is Map) {
    return <Map<String, Object?>>[
      <String, Object?>{
        'dataset': item.dataset.label,
        'dataset_id': item.dataset.id,
        'artifact': item.artifact.name,
        for (final MapEntry<dynamic, dynamic> entry
            in (item.value as Map).entries)
          entry.key.toString(): _scalarOrJson(entry.value),
      },
    ];
  }
  return <Map<String, Object?>>[
    <String, Object?>{
      'dataset': item.dataset.label,
      'dataset_id': item.dataset.id,
      'artifact': item.artifact.name,
      'value': _scalarOrJson(item.value),
    },
  ];
}

Object? _scalarOrJson(Object? value) =>
    value is Map || value is List ? jsonEncode(value) : value;

String _csvCell(Object? value) {
  final String text = value?.toString() ?? '';
  return '"${text.replaceAll('"', '""')}"';
}

String _safeName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');
