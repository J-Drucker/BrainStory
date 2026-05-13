import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class AddRemoveMarkersNodeType extends NodeType {
  @override
  String get title => 'Edit Markers';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'markers': <Map<String, dynamic>>[],
    'applyEmptyMarkerSet': false,
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
    final int markerCount =
        (params['markers'] as List<dynamic>? ?? const <dynamic>[]).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Marker edits from the visualizer are persisted in this node.',
        ),
        const SizedBox(height: 12),
        Text(
          '$markerCount marker change${markerCount == 1 ? '' : 's'} recorded',
          style: const TextStyle(fontWeight: FontWeight.w600),
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

    if (params['markerGenerator'] == 'fft_windows') {
      final List<TimeMarker> generatedMarkers = fftWindowMarkersForTimeSeries(
        timeSeries,
        label: params['generatedMarkerLabel']?.toString() ?? 'FFT Window',
        widthMs: (params['windowWidthMs'] as num?)?.toDouble() ?? 1000.0,
        overlapPercent:
            (params['windowOverlapPercent'] as num?)?.toDouble() ?? 0.0,
        durationMode: params['markerDurationMode']?.toString() ?? 'window',
      );
      dataset.timeSeries = timeSeries.copyWith(
        markers: <TimeMarker>[
          ...timeSeries.markers.where(
            (TimeMarker marker) =>
                marker.label !=
                (params['generatedMarkerLabel']?.toString() ?? 'FFT Window'),
          ),
          ...generatedMarkers,
        ],
      );
      return;
    }

    final List<TimeMarker> editedMarkers = markersForDataset(
      dataset.id,
      params['markers'] as List<dynamic>? ?? const <dynamic>[],
    );
    final bool applyEmptyMarkerSet =
        (params['applyEmptyMarkerSet'] as bool?) ?? false;
    if (!applyEmptyMarkerSet && editedMarkers.isEmpty) {
      return;
    }
    dataset.timeSeries = timeSeries.copyWith(markers: editedMarkers);
  }

  static List<TimeMarker> markersForDataset(
    String datasetId,
    List<dynamic> rawMarkers,
  ) {
    return rawMarkers
        .whereType<Map<String, dynamic>>()
        .where(
          (Map<String, dynamic> marker) => marker['datasetId'] == datasetId,
        )
        .map((Map<String, dynamic> marker) {
          final Map<String, dynamic> payload = Map<String, dynamic>.from(
            marker,
          );
          payload.remove('datasetId');
          return TimeMarker.fromJson(payload);
        })
        .toList(growable: false);
  }

  static List<TimeMarker> fftWindowMarkersForTimeSeries(
    TimeSeriesData timeSeries, {
    required String label,
    required double widthMs,
    required double overlapPercent,
    required String durationMode,
  }) {
    final int sampleCount = timeSeries.sampleCount;
    final double sampleRate = timeSeries.sampleRate;
    if (sampleCount <= 0 || sampleRate <= 0) {
      return const <TimeMarker>[];
    }

    final int widthSamples = ((widthMs / 1000.0) * sampleRate).round().clamp(
      1,
      sampleCount,
    );
    final double overlapFraction = (overlapPercent / 100.0).clamp(0.0, 0.95);
    final int stepSamples = (widthSamples * (1.0 - overlapFraction))
        .round()
        .clamp(1, widthSamples);
    final int durationMicros = durationMode == 'window'
        ? ((widthSamples / sampleRate) * 1000000.0).round()
        : 0;

    final List<TimeMarker> markers = <TimeMarker>[];
    for (
      int startSample = 0;
      startSample + widthSamples <= sampleCount;
      startSample += stepSamples
    ) {
      markers.add(
        TimeMarker(
          onsetMicros: ((startSample / sampleRate) * 1000000.0).round(),
          durationMicros: durationMicros,
          label: label,
          markerType: MarkerType.window,
        ),
      );
    }

    if (markers.isEmpty) {
      markers.add(
        TimeMarker(
          onsetMicros: 0,
          durationMicros: durationMicros,
          label: label,
          markerType: MarkerType.window,
        ),
      );
    }
    return markers;
  }
}
