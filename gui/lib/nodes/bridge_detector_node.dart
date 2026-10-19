import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/brainstory_engine.dart';
import 'channel_coordinates_node.dart';
import 'node_type.dart';

class BridgeDetectorNodeType extends NodeType {
  @override
  String get title => 'Bridge Detector';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  String get subcategory => 'Quality Control';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'epochSeconds': 2.0,
    'intervalSeconds': 10.0,
    'normalizeByDistance': false,
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
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
    params.putIfAbsent('epochSeconds', () => 2.0);
    params.putIfAbsent('intervalSeconds', () => 10.0);
    params.putIfAbsent('normalizeByDistance', () => false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Compare every unique electrode pair within regularly spaced epochs. Larger scores indicate more nearly identical signals.',
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'epochSeconds',
          labelText: 'Epoch length (seconds)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: _positiveDouble,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text('Normalize MSE by electrode distance'),
          subtitle: const Text('Experimental; disabled by default.'),
          value: params['normalizeByDistance'] == true,
          onChanged: (bool? value) {
            setState(() => params['normalizeByDistance'] = value == true);
          },
        ),
        const SizedBox(height: 10),
        NodeParamTextField(
          params: params,
          paramKey: 'intervalSeconds',
          labelText: 'Epoch interval (seconds)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: _positiveDouble,
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.length < 2) {
      dataset.bridgeDetection = null;
      return;
    }
    final double epochSeconds =
        (params['epochSeconds'] as num?)?.toDouble() ?? 2.0;
    final double intervalSeconds =
        (params['intervalSeconds'] as num?)?.toDouble() ?? 10.0;
    final bool normalizeByDistance = params['normalizeByDistance'] == true;
    if (epochSeconds <= 0 || intervalSeconds <= 0) {
      throw ArgumentError('Bridge epoch length and interval must be positive.');
    }

    final List<String> labels =
        timeSeries.channelLabels.length == timeSeries.channelCount
        ? timeSeries.channelLabels
        : List<String>.generate(
            timeSeries.channelCount,
            (int index) => 'Ch ${index + 1}',
            growable: false,
          );
    final List<List<double>?> coordinates = labels
        .map((String label) {
          final ChannelCoordinate? coordinate =
              ChannelCoordinatesNodeType.coordinateForChannelLabel(
                timeSeries.channelCoordinates,
                label,
              );
          return coordinate == null
              ? null
              : <double>[coordinate.x, coordinate.y, coordinate.z];
        })
        .toList(growable: false);

    final NativeBridgeDetectionResult? native =
        await computeBridgeDetectionBackground(
          timeSeries.channels,
          sampleRate: timeSeries.sampleRate,
          epochSeconds: epochSeconds,
          intervalSeconds: intervalSeconds,
          coordinates: normalizeByDistance
              ? coordinates
              : List<List<double>?>.filled(labels.length, null),
        );
    if (native == null) {
      throw StateError('The Rust bridge-detection engine is unavailable.');
    }
    dataset.bridgeDetection = BridgeDetectionData(
      channelLabels: labels,
      epochSampleCount: native.epochSampleCount,
      intervalSampleCount: native.intervalSampleCount,
      sampleRate: timeSeries.sampleRate,
      frames: List<BridgeEpochFrameData>.generate(
        native.values.length,
        (int index) => BridgeEpochFrameData(
          epochIndex: index,
          startSample: native.epochStarts[index],
          endSampleExclusive: native.epochEnds[index],
          pairValues: native.values[index],
        ),
        growable: false,
      ),
      distanceNormalizedPairs: native.distanceNormalizedPairs,
      channelCoordinates: <String, ChannelCoordinate>{
        for (final String label in labels)
          if (ChannelCoordinatesNodeType.coordinateForChannelLabel(
                timeSeries.channelCoordinates,
                label,
              )
              case final ChannelCoordinate coordinate)
            label: coordinate,
      },
      source: timeSeries.source,
    );
    dataset.ram['bridgeDetector.params'] = <String, dynamic>{
      'epochSeconds': epochSeconds,
      'intervalSeconds': intervalSeconds,
      'normalizeByDistance': normalizeByDistance,
    };
  }
}

dynamic _positiveDouble(String value, dynamic previous) {
  final double? parsed = double.tryParse(value);
  return parsed != null && parsed > 0 ? parsed : previous;
}
