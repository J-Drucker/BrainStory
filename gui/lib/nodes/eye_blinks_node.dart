import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class EyeBlinksNodeType extends NodeType {
  @override
  String get title => 'Eye Blinks';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'detectBlink': true,
        'detectSaccadeVertical': true,
        'detectSaccadeHorizontal': true,
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
        PortSpec(name: 'markers', type: PortType.markers),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('detectBlink', () => true);
    params.putIfAbsent('detectSaccadeVertical', () => true);
    params.putIfAbsent('detectSaccadeHorizontal', () => true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'This node will eventually detect ocular artifacts and emit BrainStory markers. For now it is a workflow placeholder that reserves the marker vocabulary and passes the signal through unchanged.',
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Create blink markers'),
          subtitle: const Text('Marker label: blink'),
          value: params['detectBlink'] as bool? ?? true,
          onChanged: (bool? value) {
            setState(() {
              params['detectBlink'] = value ?? true;
            });
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Create vertical saccade markers'),
          subtitle: const Text('Marker label: saccade_vertical'),
          value: params['detectSaccadeVertical'] as bool? ?? true,
          onChanged: (bool? value) {
            setState(() {
              params['detectSaccadeVertical'] = value ?? true;
            });
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Create horizontal saccade markers'),
          subtitle: const Text('Marker label: saccade_horizontal'),
          value: params['detectSaccadeHorizontal'] as bool? ?? true,
          onChanged: (bool? value) {
            setState(() {
              params['detectSaccadeHorizontal'] = value ?? true;
            });
          },
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return;
    }

    dataset.timeSeries = timeSeries.copyWith(
      markers: _preservedMarkers(timeSeries.markers),
    );
    dataset.ram['eye_blinks.params'] = <String, dynamic>{
      'detectBlink': params['detectBlink'] ?? true,
      'detectSaccadeVertical': params['detectSaccadeVertical'] ?? true,
      'detectSaccadeHorizontal': params['detectSaccadeHorizontal'] ?? true,
      'supportedMarkerLabels': const <String>[
        'blink',
        'saccade_vertical',
        'saccade_horizontal',
      ],
      'implemented': false,
    };
  }
}

List<TimeMarker> _preservedMarkers(List<TimeMarker> markers) {
  return markers
      .where((TimeMarker marker) => marker.attributes['source'] != _eyeBlinkMarkerSource)
      .toList(growable: false);
}

const String _eyeBlinkMarkerSource = 'eye_blinks';
