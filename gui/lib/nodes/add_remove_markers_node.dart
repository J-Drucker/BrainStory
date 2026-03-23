import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class AddRemoveMarkersNodeType extends NodeType {
  @override
  String get title => 'Add/Remove Markers';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'markers': <Map<String, dynamic>>[],
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
        PortSpec(name: 'markers', type: PortType.markers),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    final int markerCount =
        (params['markers'] as List<dynamic>? ?? const <dynamic>[]).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Marker edits made from the visualizer are stored in this node.',
        ),
        const SizedBox(height: 12),
        Text(
          '$markerCount marker change${markerCount == 1 ? '' : 's'} recorded',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return;
    }

    dataset.timeSeries = timeSeries.copyWith(
      markers: markersForDataset(
        dataset.id,
        params['markers'] as List<dynamic>? ?? const <dynamic>[],
      ),
    );
  }

  static List<TimeMarker> markersForDataset(
    String datasetId,
    List<dynamic> rawMarkers,
  ) {
    return rawMarkers
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> marker) => marker['datasetId'] == datasetId)
        .map((Map<String, dynamic> marker) {
          final Map<String, dynamic> payload = Map<String, dynamic>.from(marker);
          payload.remove('datasetId');
          return TimeMarker.fromJson(payload);
        })
        .toList(growable: false);
  }
}
