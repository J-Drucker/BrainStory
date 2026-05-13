import 'package:flutter/material.dart';
import 'data_artifacts.dart';
import '../nodes/node_type.dart';
import 'dataset_state.dart';

class NodeModel {
  final String id;
  final NodeType type;
  Offset position;
  Map<String, dynamic> params;
  MarkerChange markerChange;

  final List<PortSpec> inputPorts;
  final List<PortSpec> outputPorts;

  final Map<dynamic, DatasetState> datasetStates = {};

  final List<String> parentNodeIds = [];
  final List<String> childNodeIds = [];

  String get title => type.title;

  NodeModel({
    required this.id,
    required this.type,
    required this.position,
    required this.params,
    MarkerChange? markerChange,
  })  : inputPorts = List<PortSpec>.from(type.inputs),
        outputPorts = List<PortSpec>.from(type.outputs),
        markerChange = markerChange ?? const MarkerChange();

  // >>> This is the correct placement <<<
  DatasetState get visualState {
    if (datasetStates.isEmpty) return DatasetState.notReady;

    final List<DatasetState> availableStates = datasetStates.values
        .where((DatasetState state) => state != DatasetState.notReady)
        .toList(growable: false);
    if (availableStates.isEmpty) {
      return DatasetState.notReady;
    }

    if (availableStates.contains(DatasetState.stale)) {
      return DatasetState.stale;
    }
    if (availableStates.contains(DatasetState.partial)) {
      return DatasetState.partial;
    }
    final bool hasDone = availableStates.contains(DatasetState.done);
    if (hasDone &&
        availableStates.any((DatasetState state) => state != DatasetState.done)) {
      return DatasetState.partial;
    }
    if (availableStates.contains(DatasetState.ready)) {
      return DatasetState.ready;
    }
    return hasDone ? DatasetState.done : DatasetState.notReady;
  }
}
