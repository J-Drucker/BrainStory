import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class VisualizationNodeType extends NodeType {
  @override
  String get title => 'EEG Visualization';

  @override
  NodeCategory get category => NodeCategory.visualize;

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
        DropdownButtonFormField<String>(
          initialValue: params['backend']?.toString() ?? 'mne',
          decoration: const InputDecoration(labelText: 'Backend'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'mne', child: Text('MNE')),
            DropdownMenuItem<String>(value: 'matplotlib', child: Text('Matplotlib')),
          ],
          onChanged: (String? value) {
            if (value == null) return;
            setState(() {
              params['backend'] = value;
            });
          },
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
        TextFormField(
          initialValue: params['window_sec']?.toString() ?? '5.0',
          decoration: const InputDecoration(labelText: 'Window (seconds)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (String value) {
            setState(() {
              params['window_sec'] =
                  double.tryParse(value) ?? params['window_sec'];
            });
          },
        ),
        TextFormField(
          initialValue: params['channel']?.toString() ?? 'all',
          decoration: const InputDecoration(labelText: 'Channel'),
          onChanged: (String value) {
            setState(() {
              params['channel'] = value.trim().isEmpty ? 'all' : value.trim();
            });
          },
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
