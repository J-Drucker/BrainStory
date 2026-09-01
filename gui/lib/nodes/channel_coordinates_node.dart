import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class ChannelCoordinatesNodeType extends NodeType {
  static const String standardCoordinatesAsset =
      'assets/channel_coordinates/standard_1020_coordinates.csv';

  @override
  String get title => 'Channel Coordinates';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  String get subcategory => 'Metadata';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'mode': 'standard',
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('mode', () => 'standard');
    final List<dynamic> selectedDatasetIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final Dataset? visibleDataset = datasets.values
        .where(
          (Dataset dataset) =>
              dataset.timeSeries != null &&
              (selectedDatasetIds.isEmpty ||
                  selectedDatasetIds.contains(dataset.id)),
        )
        .cast<Dataset?>()
        .firstWhere((Dataset? dataset) => dataset != null, orElse: () => null);
    final TimeSeriesData? timeSeries = visibleDataset?.timeSeries;
    final int coordinateCount = timeSeries?.channelCoordinates.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Attach electrode spatial coordinates to the channel labels in this dataset.',
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'mode',
          labelText: 'Coordinate assignment',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'standard',
              label: 'Assign standard coordinates',
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (timeSeries == null)
          const Text(
            'Run an upstream signal node first to populate channel labels.',
            style: TextStyle(color: Colors.black54),
          )
        else
          Text(
            coordinateCount == 0
                ? '${timeSeries.channelCount} channel(s) available; no coordinates assigned yet.'
                : '$coordinateCount coordinate(s) currently attached.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) {
      return;
    }
    final String mode = params['mode']?.toString() ?? 'standard';
    if (mode != 'standard') {
      return;
    }

    final String csvPayload = await rootBundle.loadString(
      standardCoordinatesAsset,
    );
    final Map<String, ChannelCoordinate> standardCoordinates =
        parseChannelCoordinateCsv(csvPayload);
    final List<String> labels = _channelLabelsForSeries(timeSeries);
    final Map<String, ChannelCoordinate> attached =
        <String, ChannelCoordinate>{};
    for (final String label in labels) {
      final ChannelCoordinate? coordinate = coordinateForChannelLabel(
        standardCoordinates,
        label,
      );
      if (coordinate == null) {
        continue;
      }
      attached[label] = ChannelCoordinate(
        label: label,
        x: coordinate.x,
        y: coordinate.y,
        z: coordinate.z,
        coordinateSystem: coordinate.coordinateSystem,
        units: coordinate.units,
      );
    }

    dataset.timeSeries = timeSeries.copyWith(
      channelCoordinates: <String, ChannelCoordinate>{
        ...timeSeries.channelCoordinates,
        ...attached,
      },
      source: timeSeries.source.isEmpty
          ? 'Channel coordinates'
          : '${timeSeries.source} -> Channel coordinates',
    );
    dataset.ram['channelCoordinates.params'] = <String, dynamic>{
      'mode': mode,
      'asset': standardCoordinatesAsset,
      'matched': attached.length,
      'missing': labels.length - attached.length,
    };
  }

  static Map<String, ChannelCoordinate> parseChannelCoordinateCsv(String csv) {
    final List<String> lines = csv
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty && !line.startsWith('#'))
        .toList(growable: false);
    if (lines.length <= 1) {
      return const <String, ChannelCoordinate>{};
    }

    final Map<String, ChannelCoordinate> coordinates =
        <String, ChannelCoordinate>{};
    for (final String line in lines.skip(1)) {
      final List<String> cells = line
          .split(',')
          .map((String cell) => cell.trim())
          .toList(growable: false);
      if (cells.length < 4) {
        continue;
      }
      final String label = cells[0];
      final double? x = double.tryParse(cells[1]);
      final double? y = double.tryParse(cells[2]);
      final double? z = double.tryParse(cells[3]);
      if (label.isEmpty || x == null || y == null || z == null) {
        continue;
      }
      final double conventionalX = _coordinateXWithConventionalSign(label, x);
      coordinates[_normalizeChannelLabel(label)] = ChannelCoordinate(
        label: label,
        x: conventionalX,
        y: y,
        z: z,
        coordinateSystem: cells.length > 4 && cells[4].isNotEmpty
            ? cells[4]
            : 'ten_twenty',
        units: cells.length > 5 && cells[5].isNotEmpty ? cells[5] : 'mm',
      );
    }
    return coordinates;
  }

  static ChannelCoordinate? coordinateForChannelLabel(
    Map<String, ChannelCoordinate> coordinates,
    String channelLabel,
  ) {
    final ChannelCoordinate? exact = coordinates[channelLabel];
    if (exact != null) {
      return exact;
    }
    for (final String key in _coordinateLookupKeys(channelLabel)) {
      final ChannelCoordinate? coordinate = coordinates[key];
      if (coordinate != null) {
        return coordinate;
      }
      for (final MapEntry<String, ChannelCoordinate> entry
          in coordinates.entries) {
        if (_normalizeChannelLabel(entry.key) == key ||
            _normalizeChannelLabel(entry.value.label) == key) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static List<String> _channelLabelsForSeries(TimeSeriesData timeSeries) {
    if (timeSeries.channelLabels.length == timeSeries.channelCount) {
      return timeSeries.channelLabels;
    }
    return List<String>.generate(
      timeSeries.channelCount,
      (int index) => index < timeSeries.channelLabels.length
          ? timeSeries.channelLabels[index]
          : 'Ch ${index + 1}',
      growable: false,
    );
  }

  static List<String> _coordinateLookupKeys(String label) {
    final List<String> candidates = <String>[];
    void addCandidate(String value) {
      final String normalized = _normalizeChannelLabel(value);
      if (normalized.isNotEmpty && !candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    final String trimmed = label.trim();
    addCandidate(trimmed);
    final List<String> parts = trimmed
        .split(RegExp(r'[\s\-_/.:()\[\]]+'))
        .where((String part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      addCandidate(parts.first);
    }
    for (final String suffix in const <String>[
      'average',
      'avg',
      'reference',
      'ref',
      'linkedmastoids',
      'mastoids',
    ]) {
      final String normalized = _normalizeChannelLabel(trimmed);
      if (normalized.endsWith(suffix)) {
        addCandidate(
          normalized.substring(0, normalized.length - suffix.length),
        );
      }
    }
    return candidates;
  }

  static String _normalizeChannelLabel(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static double _coordinateXWithConventionalSign(String label, double x) {
    final RegExpMatch? sideMatch = RegExp(
      r'(\d+)$',
    ).firstMatch(_normalizeChannelLabel(label));
    if (sideMatch == null) {
      return x;
    }
    final int? number = int.tryParse(sideMatch.group(1)!);
    if (number == null) {
      return x;
    }
    if (number.isOdd && x > 0) {
      return -x;
    }
    if (number.isEven && x < 0) {
      return -x;
    }
    return x;
  }
}
