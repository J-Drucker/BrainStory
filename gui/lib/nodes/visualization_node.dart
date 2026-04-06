import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class VisualizationNodeType extends NodeType {
  @override
  String get title => 'EEG Visualization';

  @override
  NodeCategory get category => NodeCategory.endpoints;

  @override
  String get subcategory => 'Visualize';

  @override
  Map<String, dynamic> get defaultParams => {
    'backend': 'mne',
    'window_sec': 5.0,
    'channel': 'all',
    'display_mode': 'panel',
  };

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'markers', type: PortType.markers),
  ];

  @override
  List<PortSpec> get outputs => const [];

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    params.putIfAbsent('backend', () => 'mne');
    params.putIfAbsent('window_sec', () => 5.0);
    params.putIfAbsent('channel', () => 'all');
    params.putIfAbsent('display_mode', () => 'panel');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'backend',
          labelText: 'Backend',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(value: 'mne', label: 'MNE'),
            NodeDropdownOption<String>(
              value: 'matplotlib',
              label: 'Matplotlib',
            ),
          ],
        ),
        const Text(
          'View type is inferred automatically from the upstream node output.',
          style: TextStyle(color: Colors.black54),
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
        NodeParamTextField(
          params: params,
          paramKey: 'window_sec',
          labelText: 'Window (seconds)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: (String value, dynamic previous) =>
              double.tryParse(value) ?? previous,
        ),
        NodeParamTextField(
          params: params,
          paramKey: 'channel',
          labelText: 'Channel',
          parser: (String value, dynamic _) =>
              value.trim().isEmpty ? 'all' : value.trim(),
        ),
        const SizedBox(height: 12),
        const Text(
          'Visualization execution is still a stub, but the node can now be configured in the shared dialog.',
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    dataset.ram['visualization.config'] = Map<String, dynamic>.from(params);
  }
}
