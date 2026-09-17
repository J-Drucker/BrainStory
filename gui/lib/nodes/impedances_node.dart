import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'visualization_node.dart';

class ImpedancesNodeType extends VisualizationNodeType {
  @override
  String get title => 'Impedances';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'display_mode': 'window',
    'impedance_measurement_index': -1,
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
    return RadioGroup<String>(
      groupValue: params['display_mode']?.toString() ?? 'window',
      onChanged: (String? value) {
        if (value == null) {
          return;
        }
        setState(() {
          params['display_mode'] = value;
        });
      },
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
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
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final ImpedanceData? impedanceData = dataset.timeSeries?.impedanceData;
    if (impedanceData == null ||
        impedanceData.channelCount == 0 ||
        impedanceData.measurementCount == 0) {
      throw StateError('Impedances requires upstream impedance data.');
    }
    dataset.ram['impedances.config'] = Map<String, dynamic>.from(params);
  }
}
