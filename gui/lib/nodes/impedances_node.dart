import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';
import 'visualization_node.dart';

class ImpedancesNodeType extends VisualizationNodeType {
  @override
  String get title => 'Impedances';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'display_mode': 'window',
    'impedance_channel': '',
    'impedance_quantity': 'impedance',
    'impedance_y_scale': 'linear',
    'impedance_line_mode': 'line',
  };

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    for (final MapEntry<String, dynamic> entry in defaultParams.entries) {
      params.putIfAbsent(entry.key, () => entry.value);
    }
    final List<String> channelLabels =
        datasets.values
            .map((Dataset dataset) => dataset.timeSeries?.impedanceData)
            .whereType<ImpedanceData>()
            .expand((ImpedanceData data) => data.channelLabels)
            .toSet()
            .toList()
          ..sort();
    final String selectedChannel =
        params['impedance_channel']?.toString() ?? '';
    if (selectedChannel.isNotEmpty &&
        !channelLabels.contains(selectedChannel)) {
      params['impedance_channel'] = '';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'impedance_channel',
          labelText: 'Channel',
          options: <NodeDropdownOption<String>>[
            const NodeDropdownOption<String>(
              value: '',
              label: 'First available channel',
            ),
            ...channelLabels.map(
              (String label) =>
                  NodeDropdownOption<String>(value: label, label: label),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            SizedBox(
              width: 150,
              child: NodeParamDropdownField<String>(
                params: params,
                paramKey: 'impedance_quantity',
                labelText: 'Quantity',
                options: const <NodeDropdownOption<String>>[
                  NodeDropdownOption<String>(
                    value: 'impedance',
                    label: 'Impedance',
                  ),
                  NodeDropdownOption<String>(
                    value: 'admittance',
                    label: 'Admittance',
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 128,
              child: NodeParamDropdownField<String>(
                params: params,
                paramKey: 'impedance_y_scale',
                labelText: 'Y axis',
                options: const <NodeDropdownOption<String>>[
                  NodeDropdownOption<String>(value: 'linear', label: 'Linear'),
                  NodeDropdownOption<String>(value: 'log', label: 'Log10'),
                ],
              ),
            ),
            SizedBox(
              width: 176,
              child: NodeParamDropdownField<String>(
                params: params,
                paramKey: 'impedance_line_mode',
                labelText: 'Line',
                options: const <NodeDropdownOption<String>>[
                  NodeDropdownOption<String>(
                    value: 'none',
                    label: 'Points only',
                  ),
                  NodeDropdownOption<String>(value: 'line', label: 'Straight'),
                  NodeDropdownOption<String>(
                    value: 'smooth',
                    label: 'Smooth spline',
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    dataset.ram['impedances.config'] = Map<String, dynamic>.from(params);
  }
}
