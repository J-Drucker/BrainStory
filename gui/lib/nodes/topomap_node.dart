import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class TopomapNodeType extends NodeType {
  @override
  String get title => 'Topomap';

  @override
  NodeCategory get category => NodeCategory.endpoints;

  @override
  String get subcategory => 'Visualize';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'display_mode': 'panel',
        'show_labels': true,
        'show_electrodes': true,
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('display_mode', () => 'panel');
    params.putIfAbsent('show_labels', () => true);
    params.putIfAbsent('show_electrodes', () => true);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'First-pass scalp topography viewer. For now it renders a preview RMS value per channel using available channel coordinates.',
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show electrode dots'),
          value: params['show_electrodes'] as bool? ?? true,
          onChanged: (bool? value) {
            setState(() {
              params['show_electrodes'] = value ?? true;
            });
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show channel labels'),
          value: params['show_labels'] as bool? ?? true,
          onChanged: (bool? value) {
            setState(() {
              params['show_labels'] = value ?? true;
            });
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Next steps: choose the scalar source explicitly, support time/frequency selectors, and refine interpolation.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    dataset.ram['topomap.config'] = Map<String, dynamic>.from(params);
  }
}
