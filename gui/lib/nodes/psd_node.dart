import 'package:flutter/material.dart';
import 'node_type.dart';

class PSDNodeType extends NodeType {
  @override
  String get title => 'PSD';

  @override
  Map<String, dynamic> get defaultParams => {};

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  Widget buildConfigWidget(
      Map<String, dynamic> params,
      void Function(Map<String, dynamic>) onSave,
      ) {
    return const _PSDConfigDialog();
  }
}

class _PSDConfigDialog extends StatelessWidget {
  const _PSDConfigDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PSD Node'),
      content: const Text('No configurable parameters yet.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
