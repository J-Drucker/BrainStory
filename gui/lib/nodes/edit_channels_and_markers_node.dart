import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'add_remove_markers_node.dart';
import 'channel_marker_edit_config_editor.dart';
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
    'markerEditOperations': <String, dynamic>{},
    'markerEditScope': 'all',
    'markerEditDatasetIds': <String>[],
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
    final List<dynamic> selectedDatasetIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final Dataset? dataset = datasets.values
        .where(
          (Dataset item) =>
              item.timeSeries != null &&
              (selectedDatasetIds.isEmpty ||
                  selectedDatasetIds.contains(item.id)),
        )
        .cast<Dataset?>()
        .firstWhere((Dataset? item) => item != null, orElse: () => null);
    if (dataset == null || dataset.timeSeries == null) {
      return const Text('Select a dataset with time-domain signal.');
    }
    final List<dynamic> rawMarkers =
        params['markers'] as List<dynamic>? ?? const <dynamic>[];
    final bool hasStoredMarkerSet =
        (params['applyEmptyMarkerSet'] as bool?) ?? false;
    final Map<String, dynamic> operations = Map<String, dynamic>.from(
      params['markerEditOperations'] as Map? ?? const <String, dynamic>{},
    );
    final List<TimeMarker> markers = operations.isNotEmpty
        ? dataset.timeSeries!.markers
        : hasStoredMarkerSet || rawMarkers.isNotEmpty
        ? AddRemoveMarkersNodeType.markersForDataset(dataset.id, rawMarkers)
        : dataset.timeSeries!.markers;
    params.putIfAbsent('markerEditSourceDatasetId', () => dataset.id);
    params.putIfAbsent('channelEditSourceDatasetId', () => dataset.id);
    return SizedBox(
      height: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MarkerDatasetScopeControl(
            params: params,
            datasets: datasets,
            sourceDatasetId: dataset.id,
            onChanged: (VoidCallback change) => setState(change),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ChannelMarkerEditConfigEditor(
              dataset: dataset,
              channelConfig: EditChannelsNodeType.configForDataset(
                params,
                dataset.id,
              ),
              markers: markers,
              initialMarkerOperations: operations,
              onMarkerOperationsChanged: (Map<String, dynamic> nextOperations) {
                setState(() {
                  params['markerEditOperations'] = nextOperations;
                  params['markerEditSourceDatasetId'] = dataset.id;
                });
              },
              onChannelConfigChanged: (Map<String, dynamic> config) {
                setState(() {
                  EditChannelsNodeType.setConfigForDataset(
                    params,
                    dataset.id,
                    config,
                  );
                });
              },
              onMarkersChanged: (List<TimeMarker> nextMarkers) {
                setState(() {
                  params['markers'] = nextMarkers
                      .map(
                        (TimeMarker marker) => <String, dynamic>{
                          ...marker.toJson(),
                          'datasetId': dataset.id,
                        },
                      )
                      .toList(growable: false);
                  params['applyEmptyMarkerSet'] = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return;
    }

    TimeSeriesData nextSeries = timeSeries;
    final Map<String, dynamic> config =
        EditChannelsNodeType.bindConfigToChannelLabels(
          EditChannelsNodeType.executionConfigForDataset(params, dataset.id),
          timeSeries.channelLabels,
        );
    EditChannelsNodeType.setConfigForDataset(params, dataset.id, config);
    final bool hasChannelChanges = EditChannelsNodeType.hasMeaningfulChanges(
      config,
    );
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

    final Map<String, dynamic> markerOperations = Map<String, dynamic>.from(
      params['markerEditOperations'] as Map? ?? const <String, dynamic>{},
    );
    final List<TimeMarker> editedMarkers = markerOperations.isNotEmpty
        ? AddRemoveMarkersNodeType.markerOperationsApplyToDataset(
                params,
                dataset.id,
              )
              ? AddRemoveMarkersNodeType.applyMarkerEditOperations(
                  nextSeries.markers,
                  markerOperations,
                )
              : nextSeries.markers
        : AddRemoveMarkersNodeType.markersForDataset(
            dataset.id,
            params['markers'] as List<dynamic>? ?? const <dynamic>[],
          );
    final String markerSourceDatasetId =
        params['markerEditSourceDatasetId']?.toString() ?? dataset.id;
    final bool hasStoredRowsForDataset =
        (params['markers'] as List<dynamic>? ?? const <dynamic>[]).any(
          (dynamic raw) =>
              raw is Map && raw['datasetId']?.toString() == dataset.id,
        );
    final bool staticMarkersApply =
        hasStoredRowsForDataset || dataset.id == markerSourceDatasetId;
    final bool hasMarkerChanges =
        markerOperations.isNotEmpty ||
        (staticMarkersApply &&
            (((params['applyEmptyMarkerSet'] as bool?) ?? false) ||
                editedMarkers.isNotEmpty));
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
