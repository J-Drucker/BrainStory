import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class ImpedancesNodeType extends NodeType {
  @override
  String get title => 'Impedances';

  @override
  NodeCategory get category => NodeCategory.endpoints;

  @override
  String get subcategory => 'Visualize';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'display_mode': 'panel',
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Placeholder impedance viewer. This node will eventually extract impedances and graph them.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Display',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        RadioGroup<String>(
          groupValue: params['display_mode']?.toString() ?? 'panel',
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            setState(() {
              params['display_mode'] = value;
            });
          },
          child: Column(
            children: const <Widget>[
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text('Show in panel'),
                value: 'panel',
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text('New window'),
                value: 'window',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Impedance parsing and graphing are not implemented yet.',
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    dataset.ram['impedances.config'] = Map<String, dynamic>.from(params);
  }
}
