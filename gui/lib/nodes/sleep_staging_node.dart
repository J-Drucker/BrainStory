import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class SleepStagingNodeType extends NodeType {
  @override
  String get title => 'Sleep Staging';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'epochSeconds': 30.0,
        'stagePattern': 'WAKE,SWS,SWS,REM',
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
    params.putIfAbsent('epochSeconds', () => 30.0);
    params.putIfAbsent('stagePattern', () => 'WAKE,SWS,SWS,REM');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Creates sleep-stage markers and passes the time series through unchanged. The visualizer will show these markers as a hypnogram.',
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'epochSeconds',
          labelText: 'Epoch length (seconds)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: (String value, dynamic previous) =>
              double.tryParse(value) ?? previous,
        ),
        NodeParamTextField(
          params: params,
          paramKey: 'stagePattern',
          labelText: 'Stage pattern',
          helperText: 'Comma-separated labels, for example WAKE,SWS,SWS,REM',
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.sampleCount == 0) {
      return;
    }

    final double epochSeconds =
        ((params['epochSeconds'] as num?)?.toDouble() ?? 30.0).clamp(1.0, 3600.0);
    final int epochMicros = (epochSeconds * 1000000.0).round();
    final List<String> stagePattern = _stagePatternFromParams(params);
    if (stagePattern.isEmpty) {
      return;
    }

    final int totalDurationMicros =
        ((timeSeries.sampleCount / timeSeries.sampleRate) * 1000000.0).round();
    final List<TimeMarker> preservedMarkers = timeSeries.markers
        .where((TimeMarker marker) => marker.attributes['source'] != _sleepStagingSource)
        .toList(growable: true);

    int onsetMicros = 0;
    int epochIndex = 0;
    while (onsetMicros < totalDurationMicros) {
      final int remainingMicros = totalDurationMicros - onsetMicros;
      final int durationMicros = remainingMicros < epochMicros
          ? remainingMicros
          : epochMicros;
      final String label = stagePattern[epochIndex % stagePattern.length];
      preservedMarkers.add(
        TimeMarker(
          onsetMicros: onsetMicros,
          durationMicros: durationMicros,
          label: label,
          markerType: MarkerType.window,
          attributes: <String, dynamic>{
            'source': _sleepStagingSource,
            'stage': label,
          },
        ),
      );
      onsetMicros += durationMicros;
      epochIndex++;
    }

    dataset.timeSeries = timeSeries.copyWith(markers: preservedMarkers);
    dataset.ram['sleep_staging.params'] = <String, dynamic>{
      'epochSeconds': epochSeconds,
      'stagePattern': stagePattern,
    };
  }
}

const String _sleepStagingSource = 'sleep_staging';

List<String> sleepStagePatternFromTimeSeries(TimeSeriesData timeSeries) {
  final Set<String> labels = timeSeries.markers
      .where((TimeMarker marker) => isSleepStageMarker(marker))
      .map((TimeMarker marker) => marker.label.trim())
      .where((String label) => label.isNotEmpty)
      .toSet();
  final List<String> ordered = labels.toList(growable: false)..sort();
  return ordered;
}

bool isSleepStageMarker(TimeMarker marker) {
  final String normalized = marker.label.trim().toUpperCase();
  return marker.attributes['source'] == _sleepStagingSource ||
      normalized == 'WAKE' ||
      normalized == 'REM' ||
      normalized == 'SWS';
}

List<String> _stagePatternFromParams(Map<String, dynamic> params) {
  final String raw = params['stagePattern']?.toString() ?? '';
  final List<String> parsed = raw
      .split(',')
      .map((String value) => value.trim().toUpperCase())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  if (parsed.isNotEmpty) {
    return parsed;
  }
  return const <String>['WAKE', 'SWS', 'SWS', 'REM'];
}
