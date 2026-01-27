import 'package:flutter/material.dart';

enum PortType { signal, metadata, markers }

class PortSpec {
  final String name;
  final PortType type;

  const PortSpec({
    required this.name,
    required this.type,
  });
}

abstract class NodeType {
  String get title;
  Map<String, dynamic> get defaultParams;

  /// Port layout for this node type
  List<PortSpec> get inputs;
  List<PortSpec> get outputs;

  Widget buildConfigWidget(
      Map<String, dynamic> params,
      void Function(Map<String, dynamic>) onSave,
      );
}
