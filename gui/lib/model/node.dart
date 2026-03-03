import 'package:flutter/material.dart';
import '../nodes/node_type.dart';
import 'dataset_state.dart';

class NodeModel {
  final String id;
  final NodeType type;
  Offset position;
  Map<String, dynamic> params;

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
  })  : inputPorts = List<PortSpec>.from(type.inputs),
        outputPorts = List<PortSpec>.from(type.outputs);

  // >>> This is the correct placement <<<
  DatasetState get visualState {
    if (datasetStates.isEmpty) return DatasetState.notReady;

    if (datasetStates.values.contains(DatasetState.stale)) {
      return DatasetState.stale;
    }
    if (datasetStates.values.contains(DatasetState.ready)) {
      return DatasetState.ready;
    }
    if (datasetStates.values.contains(DatasetState.notReady)) {
      return DatasetState.notReady;
    }
    return DatasetState.done;
  }
}
