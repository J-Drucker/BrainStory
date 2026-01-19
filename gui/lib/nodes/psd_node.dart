// lib/nodes/psd_node.dart
import 'package:flutter/material.dart';
import 'node_type.dart';

class PSDNodeType extends NodeType {
  @override
  String get title => 'PSD';

  @override
  Map<String, dynamic> get defaultParams => {};

  @override
  Widget buildConfigWidget(Map<String, dynamic> params, void Function(Map<String, dynamic>) onSave) {
    // No parameters to edit yet
    return AlertDialog(
      title: const Text('PSD Node'),
      content: const Text('No configurable parameters'),
      actions: [TextButton(onPressed: () => Navigator.pop(onSave as BuildContext), child: const Text('Close'))],
    );
  }
}