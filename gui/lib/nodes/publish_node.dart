import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class PublishNodeType extends NodeType {
  @override
  String get title => 'Publish';

  @override
  NodeCategory get category => NodeCategory.endpoints;

  @override
  String get subcategory => 'Export';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'target': 'methods',
        'style': 'concise',
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
        PortSpec(name: 'metadata', type: PortType.metadata),
        PortSpec(name: 'markers', type: PortType.markers),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'metadata', type: PortType.metadata),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('target', () => 'methods');
    params.putIfAbsent('style', () => 'concise');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'target',
          labelText: 'Output',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(value: 'methods', label: 'Methods section'),
            NodeDropdownOption<String>(
              value: 'pipeline_summary',
              label: 'Pipeline summary',
            ),
          ],
        ),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'style',
          labelText: 'Style',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(value: 'concise', label: 'Concise'),
            NodeDropdownOption<String>(value: 'detailed', label: 'Detailed'),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Placeholder for a more powerful publishing/export workflow. This node will eventually generate manuscript-ready pipeline descriptions and related outputs.',
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    dataset.ram['publish.config'] = Map<String, dynamic>.from(params);
  }
}
