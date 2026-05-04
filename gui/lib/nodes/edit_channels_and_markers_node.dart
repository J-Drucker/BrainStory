import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'add_remove_markers_node.dart';
import 'edit_channels_node.dart';
import 'node_type.dart';

class EditChannelsAndMarkersNodeType extends NodeType {
  @override
  String get title => 'Edit Channels and Markers';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  String get subcategory => 'Subcategory 1';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'markers': <Map<String, dynamic>>[],
        'applyEmptyMarkerSet': false,
        'channelEditsByDataset': <String, dynamic>{},
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
    final Map<String, dynamic> configByDataset = Map<String, dynamic>.from(
      params['channelEditsByDataset'] as Map? ?? const <String, dynamic>{},
    );
    final int editedDatasetCount = configByDataset.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Viewer-authored channel and marker edits are persisted together in this node.',
        ),
        const SizedBox(height: 12),
        Text(
          '$editedDatasetCount dataset${editedDatasetCount == 1 ? '' : 's'} with channel edits',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
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

    TimeSeriesData nextSeries = timeSeries;
    final Map<String, dynamic> config = EditChannelsNodeType.configForDataset(
      params,
      dataset.id,
    );
    final bool hasChannelChanges =
        EditChannelsNodeType.hasMeaningfulChanges(config);
    ArtifactChangeSet? channelChangeSet;
    if (hasChannelChanges) {
      channelChangeSet = EditChannelsNodeType.changeSetForConfig(
        datasetId: dataset.id,
        timeSeries: nextSeries,
        config: config,
      );
      nextSeries = EditChannelsNodeType.applyChannelEdits(
        nextSeries,
        config,
        warningSink: (String warning) {
          dataset.ram['editChannels.lastWarning'] = warning;
        },
      );
    }

    final List<TimeMarker> editedMarkers = AddRemoveMarkersNodeType.markersForDataset(
      dataset.id,
      params['markers'] as List<dynamic>? ?? const <dynamic>[],
    );
    final bool hasMarkerChanges =
        ((params['applyEmptyMarkerSet'] as bool?) ?? false) || editedMarkers.isNotEmpty;
    if (hasMarkerChanges) {
      nextSeries = nextSeries.copyWith(markers: editedMarkers);
    }

    dataset.timeSeries = nextSeries;

    if (hasChannelChanges || hasMarkerChanges) {
      dataset.ram['artifact.lastChangeSet'] = _mergedChangeSet(
        datasetId: dataset.id,
        channelChangeSet: channelChangeSet,
        editedMarkers: editedMarkers,
      );
    }
  }

  ArtifactChangeSet _mergedChangeSet({
    required String datasetId,
    required ArtifactChangeSet? channelChangeSet,
    required List<TimeMarker> editedMarkers,
  }) {
    final Set<ArtifactChangeType> changeTypes = <ArtifactChangeType>{
      if (channelChangeSet != null) ...channelChangeSet.changeTypes,
      if (editedMarkers.isNotEmpty) ArtifactChangeType.markers,
    };
    return ArtifactChangeSet(
      datasetId: datasetId,
      sourceNodeId: channelChangeSet?.sourceNodeId,
      changeTypes: changeTypes,
      artifactIds: channelChangeSet?.artifactIds ?? const <String>[],
      affectedChannelLabels:
          channelChangeSet?.affectedChannelLabels ?? const <String>[],
      affectedChannelIndices:
          channelChangeSet?.affectedChannelIndices ?? const <int>[],
      description: 'Edit Channels and Markers',
    );
  }
}
