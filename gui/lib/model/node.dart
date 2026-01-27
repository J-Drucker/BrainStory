import 'package:flutter/material.dart';
import '../nodes/node_type.dart';

class NodeModel {
  final String id;
  final NodeType type;
  Offset position;
  Map<String, dynamic> params;

  /// Port specs (copied from type at creation)
  final List<PortSpec> inputPorts;
  final List<PortSpec> outputPorts;

  String get title => type.title;

  NodeModel({
    required this.id,
    required this.type,
    required this.position,
    required this.params,
  })  : inputPorts = List<PortSpec>.from(type.inputs),
        outputPorts = List<PortSpec>.from(type.outputs);
}
