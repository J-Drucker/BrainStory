import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class SegmentationNodeType extends NodeType {
  @override
  String get title => 'Segmentation';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'mode': 'events',
    'includedMarkers': <String, dynamic>{},
    'eventWindowStartMs': -200.0,
    'eventWindowStopMs': 800.0,
    'eventApplyBaseline': false,
    'eventBaselineConfigured': false,
    'eventBaselineStartMs': -200.0,
    'eventBaselineStopMs': 0.0,
    'blockConcatenate': false,
    'blockInvert': false,
    'equalWindowWidthMs': 1000.0,
    'equalWindowOverlapPercent': 0.0,
    'windowMarkerName': 'FFT Window',
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'markers', type: PortType.markers),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'segments', type: PortType.metadata),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('mode', () => 'events');
    params.putIfAbsent('includedMarkers', () => <String, dynamic>{});
    params.putIfAbsent('eventWindowStartMs', () => -200.0);
    params.putIfAbsent('eventWindowStopMs', () => 800.0);
    params.putIfAbsent('eventApplyBaseline', () => false);
    params.putIfAbsent('eventBaselineConfigured', () => false);
    params.putIfAbsent('eventBaselineStartMs', () => -200.0);
    params.putIfAbsent('eventBaselineStopMs', () => 0.0);
    params.putIfAbsent('blockConcatenate', () => false);
    params.putIfAbsent('blockInvert', () => false);
    params.putIfAbsent('equalWindowWidthMs', () => 1000.0);
    params.putIfAbsent('equalWindowOverlapPercent', () => 0.0);
    params.putIfAbsent('windowMarkerName', () => 'FFT Window');

    final List<Dataset> datasetList = datasets.values.toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    final List<dynamic> selectedIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[];
    final Dataset? activeDataset = _resolveActiveDataset(
      datasetList,
      selectedIds,
    );
    final TimeSeriesData? timeSeries = activeDataset?.timeSeries;
    final List<TimeMarker> markers =
        timeSeries?.markers ?? const <TimeMarker>[];

    return SizedBox(
      width: 760,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: RadioGroup<String>(
              groupValue: params['mode']?.toString() ?? 'events',
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    params['mode'] = value;
                  });
                }
              },
              child: Column(
                children: <Widget>[
                  _SegmentationModeSection(
                    value: 'events',
                    title: 'Events',
                    description: 'Create segments around marker events.',
                    options: _eventOptions(params: params, setState: setState),
                  ),
                  const Divider(height: 24),
                  _SegmentationModeSection(
                    value: 'blocks',
                    title: 'Blocks',
                    description: 'Create segments from included marker spans.',
                    options: _blockOptions(params: params, setState: setState),
                  ),
                  const Divider(height: 24),
                  _SegmentationModeSection(
                    value: 'equal_windows',
                    title: 'Equal Windows',
                    description: 'Split the recording into uniform windows.',
                    options: _equalWindowOptions(
                      params: params,
                      setState: setState,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: <Widget>[
                _RightPanelSection(
                  title: activeDataset == null
                      ? 'Marker Overview'
                      : 'Marker Overview: ${activeDataset.label}',
                  child: _MarkerOverview(
                    dataset: activeDataset,
                    markers: markers,
                  ),
                ),
                const SizedBox(height: 14),
                _RightPanelSection(
                  title: 'Include / Exclude Markers',
                  height: 320,
                  child: _MarkerSelectionPanel(
                    dataset: activeDataset,
                    markers: markers,
                    includedMarkers: Map<String, dynamic>.from(
                      params['includedMarkers'] as Map? ?? <String, dynamic>{},
                    ),
                    onChanged: (Map<String, dynamic> nextMap) => setState(() {
                      params['includedMarkers'] = nextMap;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) {
      dataset.segmentedTimeSeries = null;
      dataset.ram['segmentation.config'] = Map<String, dynamic>.from(params);
      return;
    }

    final String mode = (params['mode'] ?? 'events').toString();
    final Map<String, dynamic> includedMarkers = Map<String, dynamic>.from(
      params['includedMarkers'] as Map? ?? <String, dynamic>{},
    );
    final Map<String, dynamic>? previousRunParams =
        _previousRunParamsForDataset(params, dataset.id);
    final List<SignalSegmentData> segments;

    switch (mode) {
      case 'equal_windows':
        final String windowMarkerName =
            params['windowMarkerName']?.toString().trim().isNotEmpty == true
            ? params['windowMarkerName'].toString().trim()
            : 'FFT Window';
        segments = _buildEventSegments(
          timeSeries: timeSeries,
          includedMarkers: <String, dynamic>{
            markerKeyForKindAndLabel(
              kind: MarkerType.window,
              label: windowMarkerName,
            ): true,
          },
          windowStartMs: 0.0,
          windowStopMs:
              (params['equalWindowWidthMs'] as num?)?.toDouble() ?? 1000.0,
        );
        break;
      case 'blocks':
        segments = _buildBlockSegments(
          timeSeries: timeSeries,
          includedMarkers: includedMarkers,
          concatenate: params['blockConcatenate'] as bool? ?? false,
          invert: params['blockInvert'] as bool? ?? false,
        );
        break;
      case 'events':
      default:
        final List<SignalSegmentData> eventSegments =
            _canReuseEventSegmentsForBaselineOnlyChange(
              params: params,
              previousRunParams: previousRunParams,
              existingSegmented: dataset.segmentedTimeSeries,
            )
            ? _reuseExistingEventSegments(dataset.segmentedTimeSeries!)
            : _buildEventSegments(
                timeSeries: timeSeries,
                includedMarkers: includedMarkers,
                windowStartMs:
                    (params['eventWindowStartMs'] as num?)?.toDouble() ??
                    -200.0,
                windowStopMs:
                    (params['eventWindowStopMs'] as num?)?.toDouble() ?? 800.0,
              );
        segments = params['eventApplyBaseline'] as bool? ?? false
            ? _baselineCorrectEventSegments(
                timeSeries: timeSeries,
                segments: eventSegments,
                baselineStartMs:
                    (params['eventBaselineStartMs'] as num?)?.toDouble() ??
                    -200.0,
                baselineStopMs:
                    (params['eventBaselineStopMs'] as num?)?.toDouble() ?? 0.0,
              )
            : eventSegments;
        break;
    }

    dataset.segmentedTimeSeries = SegmentedTimeSeriesData(
      segments: segments,
      sampleRate: timeSeries.sampleRate,
      channelLabels: timeSeries.channelLabels,
      source: timeSeries.source,
      sourceTimeSeries: timeSeries,
    );
    dataset.ram['segmentation.precomputedConditionAverages'] =
        _precomputeConditionAverages(segmented: dataset.segmentedTimeSeries!);
    dataset.ram['segmentation.config'] = Map<String, dynamic>.from(params);
  }

  Dataset? _resolveActiveDataset(
    List<Dataset> datasets,
    List<dynamic> selectedIds,
  ) {
    if (datasets.isEmpty) {
      return null;
    }
    for (final dynamic id in selectedIds) {
      for (final Dataset dataset in datasets) {
        if (dataset.id == id) {
          return dataset;
        }
      }
    }
    return datasets.first;
  }
}

Map<String, dynamic> _precomputeConditionAverages({
  required SegmentedTimeSeriesData segmented,
}) {
  final Map<String, List<SignalSegmentData>> segmentsByLabel =
      <String, List<SignalSegmentData>>{};
  for (final SignalSegmentData segment in segmented.segments) {
    segmentsByLabel
        .putIfAbsent(segment.label, () => <SignalSegmentData>[])
        .add(segment);
  }

  final Map<String, dynamic> averages = <String, dynamic>{};
  for (final MapEntry<String, List<SignalSegmentData>> entry
      in segmentsByLabel.entries) {
    final List<List<List<double>>> materialized = entry.value
        .map(segmented.channelSamplesForSegment)
        .where((List<List<double>> samples) => samples.isNotEmpty)
        .toList(growable: false);
    if (materialized.isEmpty) {
      continue;
    }
    final int channelCount = materialized
        .map((List<List<double>> segmentChannels) => segmentChannels.length)
        .reduce(math.min);
    if (channelCount == 0) {
      continue;
    }
    final int sampleCount = materialized
        .map(
          (List<List<double>> segmentChannels) => segmentChannels
              .take(channelCount)
              .map((List<double> channel) => channel.length)
              .reduce(math.min),
        )
        .reduce(math.min);
    if (sampleCount == 0) {
      continue;
    }

    final List<List<double>> meanChannels = List<List<double>>.generate(
      channelCount,
      (int channelIndex) => List<double>.filled(sampleCount, 0.0),
      growable: false,
    );
    for (final List<List<double>> segmentChannels in materialized) {
      for (int channelIndex = 0; channelIndex < channelCount; channelIndex++) {
        final List<double> channel = segmentChannels[channelIndex];
        for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
          meanChannels[channelIndex][sampleIndex] += channel[sampleIndex];
        }
      }
    }

    final double denominator = materialized.length.toDouble();
    for (int channelIndex = 0; channelIndex < channelCount; channelIndex++) {
      for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
        meanChannels[channelIndex][sampleIndex] /= denominator;
      }
    }

    averages[entry.key] = <String, dynamic>{
      'segmentCount': materialized.length,
      'sampleCount': sampleCount,
      'channelCount': channelCount,
      'sampleRate': segmented.sampleRate,
      'channelLabels': segmented.channelLabels
          .take(channelCount)
          .toList(growable: false),
      'meanChannels': meanChannels,
    };
  }
  return averages;
}

Map<String, dynamic>? _previousRunParamsForDataset(
  Map<String, dynamic> params,
  String datasetId,
) {
  final Map<String, dynamic> byDataset = Map<String, dynamic>.from(
    params['_lastRunParamsByDataset'] as Map? ?? const <String, dynamic>{},
  );
  final dynamic rawParams = byDataset[datasetId];
  if (rawParams is Map) {
    return Map<String, dynamic>.from(rawParams);
  }
  return null;
}

bool _canReuseEventSegmentsForBaselineOnlyChange({
  required Map<String, dynamic> params,
  required Map<String, dynamic>? previousRunParams,
  required SegmentedTimeSeriesData? existingSegmented,
}) {
  if (previousRunParams == null ||
      existingSegmented == null ||
      existingSegmented.segments.isEmpty ||
      (params['mode'] ?? 'events').toString() != 'events' ||
      (previousRunParams['mode'] ?? 'events').toString() != 'events') {
    return false;
  }

  const Set<String> ignoredKeys = <String>{
    'eventApplyBaseline',
    'eventBaselineConfigured',
    'eventBaselineStartMs',
    'eventBaselineStopMs',
    'selectedDatasetIds',
    'storagePolicy',
  };
  final Set<String> keys = <String>{
    ...params.keys.where((String key) => !key.startsWith('_')),
    ...previousRunParams.keys.where((String key) => !key.startsWith('_')),
  }..removeAll(ignoredKeys);

  for (final String key in keys) {
    if (!_paramValuesEquivalent(params[key], previousRunParams[key])) {
      return false;
    }
  }
  return true;
}

bool _paramValuesEquivalent(dynamic left, dynamic right) {
  if (left is num && right is num) {
    return (left.toDouble() - right.toDouble()).abs() < 0.000001;
  }
  if (left is Map || right is Map || left is List || right is List) {
    return left.toString() == right.toString();
  }
  return left == right;
}

List<SignalSegmentData> _reuseExistingEventSegments(
  SegmentedTimeSeriesData segmented,
) {
  return segmented.segments
      .map((SignalSegmentData segment) {
        if (segment.sourceStartSample != null &&
            segment.sourceStopSampleExclusive != null) {
          return segment.copyWith(channelSamples: const <List<double>>[]);
        }
        final int startSample = (segment.startSeconds * segmented.sampleRate)
            .round();
        final int stopSample = (segment.stopSeconds * segmented.sampleRate)
            .round();
        return segment.copyWith(
          channelSamples: const <List<double>>[],
          sourceStartSample: startSample,
          sourceStopSampleExclusive: stopSample,
        );
      })
      .toList(growable: false);
}

List<SignalSegmentData> _buildEventSegments({
  required TimeSeriesData timeSeries,
  required Map<String, dynamic> includedMarkers,
  required double windowStartMs,
  required double windowStopMs,
}) {
  final double sampleRate = timeSeries.sampleRate;
  final List<SignalSegmentData> segments = <SignalSegmentData>[];
  final double startOffsetSeconds = windowStartMs / 1000.0;
  final double stopOffsetSeconds = windowStopMs / 1000.0;

  for (final TimeMarker marker in timeSeries.markers) {
    if (!_markerIncluded(marker, includedMarkers)) {
      continue;
    }
    final int startIndex =
        ((marker.timeSeconds + startOffsetSeconds) * sampleRate).round();
    final int stopIndex =
        ((marker.timeSeconds + stopOffsetSeconds) * sampleRate).round();
    final SignalSegmentData? segment = _extractSegment(
      timeSeries: timeSeries,
      startIndex: startIndex,
      stopIndex: stopIndex,
      label: marker.label,
      kind: marker.kind,
      anchorTimeSeconds: marker.timeSeconds,
    );
    if (segment != null) {
      segments.add(segment);
    }
  }

  return segments;
}

List<SignalSegmentData> _baselineCorrectEventSegments({
  required TimeSeriesData timeSeries,
  required List<SignalSegmentData> segments,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  if (timeSeries.channels.isEmpty || timeSeries.sampleRate <= 0) {
    return segments;
  }
  return segments
      .map(
        (SignalSegmentData segment) => _baselineCorrectEventSegment(
          timeSeries: timeSeries,
          segment: segment,
          baselineStartMs: baselineStartMs,
          baselineStopMs: baselineStopMs,
        ),
      )
      .toList(growable: false);
}

SignalSegmentData _baselineCorrectEventSegment({
  required TimeSeriesData timeSeries,
  required SignalSegmentData segment,
  required double baselineStartMs,
  required double baselineStopMs,
}) {
  final int? start = segment.sourceStartSample;
  final int? stop = segment.sourceStopSampleExclusive;
  if (start == null || stop == null || stop <= start) {
    return segment;
  }
  final double anchorSeconds =
      segment.anchorTimeSeconds ?? segment.startSeconds;
  final int baselineStart =
      ((anchorSeconds + baselineStartMs / 1000.0) * timeSeries.sampleRate)
          .round()
          .clamp(0, timeSeries.sampleCount);
  final int baselineStop =
      ((anchorSeconds + baselineStopMs / 1000.0) * timeSeries.sampleRate)
          .round()
          .clamp(0, timeSeries.sampleCount);
  final int anchorIndex = (anchorSeconds * timeSeries.sampleRate).round().clamp(
    start,
    stop - 1,
  );
  final bool useBaselineWindow = baselineStop > baselineStart;
  final List<List<double>> correctedChannels = timeSeries.channels
      .map((List<double> channel) {
        final List<double> values = channel.sublist(start, stop);
        double baselineValue;
        if (useBaselineWindow) {
          double sum = 0.0;
          for (int index = baselineStart; index < baselineStop; index++) {
            sum += channel[index];
          }
          baselineValue = sum / (baselineStop - baselineStart);
        } else {
          baselineValue = channel[anchorIndex];
        }
        return List<double>.generate(
          values.length,
          (int index) => values[index] - baselineValue,
          growable: false,
        );
      })
      .toList(growable: false);
  return segment.copyWith(
    channelSamples: correctedChannels,
    clearSourceWindow: true,
  );
}

List<SignalSegmentData> _buildBlockSegments({
  required TimeSeriesData timeSeries,
  required Map<String, dynamic> includedMarkers,
  required bool concatenate,
  required bool invert,
}) {
  final int sampleCount = timeSeries.sampleCount;
  if (sampleCount <= 0) {
    return const <SignalSegmentData>[];
  }

  final List<TimeMarker> selectedMarkers =
      timeSeries.markers
          .where(
            (TimeMarker marker) => _markerIncluded(marker, includedMarkers),
          )
          .toList(growable: false)
        ..sort(
          (TimeMarker a, TimeMarker b) =>
              a.timeSeconds.compareTo(b.timeSeconds),
        );

  final List<_SampleInterval> blockIntervals = <_SampleInterval>[];
  final List<TimeMarker> pointBoundaries = <TimeMarker>[];
  for (final TimeMarker marker in selectedMarkers) {
    if (marker.durationMicros <= 0) {
      pointBoundaries.add(marker);
      continue;
    }
    final int startIndex = (marker.timeSeconds * timeSeries.sampleRate).round();
    final int stopIndex =
        (((marker.onsetMicros + marker.durationMicros) / 1000000.0) *
                timeSeries.sampleRate)
            .round();
    final _SampleInterval? interval = _boundedInterval(
      startIndex: startIndex,
      stopIndex: stopIndex,
      sampleCount: sampleCount,
      label: marker.label,
    );
    if (interval != null) {
      blockIntervals.add(interval);
    }
  }
  for (int index = 0; index + 1 < pointBoundaries.length; index += 2) {
    final TimeMarker startMarker = pointBoundaries[index];
    final TimeMarker stopMarker = pointBoundaries[index + 1];
    final int startIndex = (startMarker.timeSeconds * timeSeries.sampleRate)
        .round();
    final int stopIndex = (stopMarker.timeSeconds * timeSeries.sampleRate)
        .round();
    final _SampleInterval? interval = _boundedInterval(
      startIndex: startIndex,
      stopIndex: stopIndex,
      sampleCount: sampleCount,
      label: startMarker.label == stopMarker.label
          ? startMarker.label
          : '${startMarker.label} - ${stopMarker.label}',
    );
    if (interval != null) {
      blockIntervals.add(interval);
    }
  }
  blockIntervals.sort(
    (_SampleInterval a, _SampleInterval b) =>
        a.startIndex.compareTo(b.startIndex),
  );

  final List<_SampleInterval> intervals = invert
      ? _invertIntervals(blockIntervals, sampleCount)
      : blockIntervals;
  if (intervals.isEmpty) {
    return const <SignalSegmentData>[];
  }

  if (concatenate) {
    return <SignalSegmentData>[
      _concatenateIntervals(timeSeries: timeSeries, intervals: intervals),
    ];
  }

  final List<SignalSegmentData> segments = <SignalSegmentData>[];
  for (int index = 0; index < intervals.length; index++) {
    final _SampleInterval interval = intervals[index];
    final String? sourceLabel = interval.label?.trim();
    final SignalSegmentData? segment = _extractSegment(
      timeSeries: timeSeries,
      startIndex: interval.startIndex,
      stopIndex: interval.stopIndex,
      label: invert
          ? 'Inverted Block ${index + 1}'
          : sourceLabel == null || sourceLabel.isEmpty
          ? 'Block ${index + 1}'
          : intervals.length == 1
          ? sourceLabel
          : '$sourceLabel ${index + 1}',
      kind: invert ? 'inverted_block' : 'block',
    );
    if (segment != null) {
      segments.add(segment);
    }
  }
  return segments;
}

SignalSegmentData _concatenateIntervals({
  required TimeSeriesData timeSeries,
  required List<_SampleInterval> intervals,
}) {
  final List<List<double>> channelSamples = List<List<double>>.generate(
    timeSeries.channelCount,
    (_) => <double>[],
  );

  for (final _SampleInterval interval in intervals) {
    for (
      int channelIndex = 0;
      channelIndex < timeSeries.channelCount;
      channelIndex++
    ) {
      channelSamples[channelIndex].addAll(
        timeSeries.channels[channelIndex].sublist(
          interval.startIndex,
          interval.stopIndex,
        ),
      );
    }
  }

  return SignalSegmentData(
    channelSamples: channelSamples,
    startSeconds: intervals.first.startIndex / timeSeries.sampleRate,
    stopSeconds: intervals.last.stopIndex / timeSeries.sampleRate,
    label: 'Concatenated Blocks',
    kind: 'block',
  );
}

bool _markerIncluded(TimeMarker marker, Map<String, dynamic> includedMarkers) {
  return (includedMarkers[markerKeyForMarker(marker)] as bool?) ?? false;
}

SignalSegmentData? _extractSegment({
  required TimeSeriesData timeSeries,
  required int startIndex,
  required int stopIndex,
  required String label,
  required String kind,
  double? anchorTimeSeconds,
}) {
  final _SampleInterval? interval = _boundedInterval(
    startIndex: startIndex,
    stopIndex: stopIndex,
    sampleCount: timeSeries.sampleCount,
  );
  if (interval == null) {
    return null;
  }

  return SignalSegmentData(
    startSeconds: interval.startIndex / timeSeries.sampleRate,
    stopSeconds: interval.stopIndex / timeSeries.sampleRate,
    label: label,
    kind: kind,
    anchorTimeSeconds: anchorTimeSeconds,
    sourceStartSample: interval.startIndex,
    sourceStopSampleExclusive: interval.stopIndex,
  );
}

_SampleInterval? _boundedInterval({
  required int startIndex,
  required int stopIndex,
  required int sampleCount,
  String? label,
}) {
  final int boundedStart = startIndex.clamp(0, sampleCount);
  final int boundedStop = stopIndex.clamp(0, sampleCount);
  if (boundedStop <= boundedStart) {
    return null;
  }
  return _SampleInterval(
    startIndex: boundedStart,
    stopIndex: boundedStop,
    label: label,
  );
}

List<_SampleInterval> _invertIntervals(
  List<_SampleInterval> intervals,
  int sampleCount,
) {
  if (intervals.isEmpty) {
    return <_SampleInterval>[
      _SampleInterval(startIndex: 0, stopIndex: sampleCount),
    ];
  }

  final List<_SampleInterval> ordered = List<_SampleInterval>.from(intervals)
    ..sort(
      (_SampleInterval a, _SampleInterval b) =>
          a.startIndex.compareTo(b.startIndex),
    );
  final List<_SampleInterval> inverted = <_SampleInterval>[];
  int cursor = 0;
  for (final _SampleInterval interval in ordered) {
    if (interval.startIndex > cursor) {
      inverted.add(
        _SampleInterval(startIndex: cursor, stopIndex: interval.startIndex),
      );
    }
    cursor = math.max(cursor, interval.stopIndex);
  }
  if (cursor < sampleCount) {
    inverted.add(_SampleInterval(startIndex: cursor, stopIndex: sampleCount));
  }
  return inverted;
}

class _SampleInterval {
  const _SampleInterval({
    required this.startIndex,
    required this.stopIndex,
    this.label,
  });

  final int startIndex;
  final int stopIndex;
  final String? label;
}

class _SegmentationModeSection extends StatelessWidget {
  const _SegmentationModeSection({
    required this.value,
    required this.title,
    required this.description,
    required this.options,
  });

  final String value;
  final String title;
  final String description;
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    final RadioGroupRegistry<String>? radioGroup = RadioGroup.maybeOf<String>(
      context,
    );
    final String? groupValue = radioGroup?.groupValue;
    final bool active = value == groupValue;
    final Color textColor = active ? Colors.black : Colors.black45;
    return InkWell(
      onTap: () => radioGroup?.onChanged(value),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: active ? 1.0 : 0.55,
        child: AbsorbPointer(
          absorbing: !active,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Radio<String>(value: value),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: DefaultTextStyle(
                    style: TextStyle(color: textColor, fontSize: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(description, style: TextStyle(color: textColor)),
                        const SizedBox(height: 10),
                        ...options,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<Widget> _eventOptions({
  required Map<String, dynamic> params,
  required void Function(void Function()) setState,
}) {
  return <Widget>[
    Row(
      children: <Widget>[
        Expanded(
          child: _NumericOptionField(
            label: 'Window start (ms)',
            value: (params['eventWindowStartMs'] as num?)?.toDouble() ?? -200.0,
            onChanged: (double value) => setState(() {
              params['eventWindowStartMs'] = value;
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _NumericOptionField(
            label: 'Window stop (ms)',
            value: (params['eventWindowStopMs'] as num?)?.toDouble() ?? 800.0,
            onChanged: (double value) => setState(() {
              params['eventWindowStopMs'] = value;
            }),
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: params['eventApplyBaseline'] as bool? ?? false,
      title: const Text('Baseline-correct segment artifact'),
      subtitle: const Text(
        'If off, segments preserve source signal values. Visualization still baseline-corrects for display.',
      ),
      onChanged: (bool? value) => setState(() {
        params['eventApplyBaseline'] = value ?? false;
      }),
    ),
    const SizedBox(height: 6),
    Row(
      children: <Widget>[
        Expanded(
          child: _NumericOptionField(
            label: 'Baseline start (ms)',
            value:
                (params['eventBaselineStartMs'] as num?)?.toDouble() ?? -200.0,
            onChanged: (double value) => setState(() {
              params['eventBaselineConfigured'] = true;
              params['eventBaselineStartMs'] = value;
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _NumericOptionField(
            label: 'Baseline stop (ms)',
            value: (params['eventBaselineStopMs'] as num?)?.toDouble() ?? 0.0,
            onChanged: (double value) => setState(() {
              params['eventBaselineConfigured'] = true;
              params['eventBaselineStopMs'] = value;
            }),
          ),
        ),
      ],
    ),
  ];
}

List<Widget> _blockOptions({
  required Map<String, dynamic> params,
  required void Function(void Function()) setState,
}) {
  final bool concatenate = params['blockConcatenate'] as bool? ?? false;
  final bool invert = params['blockInvert'] as bool? ?? false;
  return <Widget>[
    CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: concatenate,
      title: const Text('Concatenate'),
      subtitle: const Text(
        'Recombine multiple selected blocks into one continuous output.',
      ),
      onChanged: (bool? value) => setState(() {
        params['blockConcatenate'] = value ?? false;
      }),
    ),
    const SizedBox(height: 6),
    CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: invert,
      title: const Text('Invert'),
      subtitle: const Text(
        'Use only timepoints outside the selected marker spans, for example to exclude artifacts.',
      ),
      onChanged: (bool? value) => setState(() {
        params['blockInvert'] = value ?? false;
      }),
    ),
  ];
}

List<Widget> _equalWindowOptions({
  required Map<String, dynamic> params,
  required void Function(void Function()) setState,
}) {
  return <Widget>[
    NodeParamTextField(
      params: params,
      paramKey: 'windowMarkerName',
      labelText: 'Window marker name',
      helperText: 'Auto-created marker label for these windows.',
      parser: (String text, dynamic previous) =>
          text.trim().isEmpty ? previous : text,
    ),
    const SizedBox(height: 10),
    _NumericOptionField(
      label: 'Width (ms)',
      value: (params['equalWindowWidthMs'] as num?)?.toDouble() ?? 1000.0,
      onChanged: (double value) => setState(() {
        params['equalWindowWidthMs'] = value;
      }),
    ),
    const SizedBox(height: 10),
    _NumericOptionField(
      label: 'Overlap (%)',
      value: (params['equalWindowOverlapPercent'] as num?)?.toDouble() ?? 0.0,
      onChanged: (double value) => setState(() {
        params['equalWindowOverlapPercent'] = value.clamp(0.0, 100.0);
      }),
    ),
  ];
}

class _NumericOptionField extends StatefulWidget {
  const _NumericOptionField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_NumericOptionField> createState() => _NumericOptionFieldState();
}

class _NumericOptionFieldState extends State<_NumericOptionField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _NumericOptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final String nextText = _format(widget.value);
      if (_controller.text != nextText) {
        _controller.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (String value) {
        final double? parsed = double.tryParse(value);
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }

  String _format(double value) {
    return value.truncateToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

class _RightPanelSection extends StatelessWidget {
  const _RightPanelSection({
    required this.title,
    required this.child,
    this.height = 220,
  });

  final String title;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Divider(height: 1, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkerOverview extends StatelessWidget {
  const _MarkerOverview({required this.dataset, required this.markers});

  final Dataset? dataset;
  final List<TimeMarker> markers;

  @override
  Widget build(BuildContext context) {
    if (dataset == null) {
      return const Center(child: Text('No dataset available.'));
    }

    final TimeSeriesData? timeSeries = dataset!.timeSeries;
    if (timeSeries == null) {
      return const Center(
        child: Text('Run upstream first to populate markers.'),
      );
    }

    final double durationSeconds = timeSeries.sampleCount > 0
        ? timeSeries.sampleCount / timeSeries.sampleRate
        : markers.isEmpty
        ? 1.0
        : markers
                  .map((TimeMarker marker) => marker.timeSeconds)
                  .reduce(math.max) +
              1.0;

    return CustomPaint(
      painter: _MarkerOverviewPainter(
        markers: markers,
        durationSeconds: durationSeconds,
      ),
      child: Container(),
    );
  }
}

class _MarkerOverviewPainter extends CustomPainter {
  const _MarkerOverviewPainter({
    required this.markers,
    required this.durationSeconds,
  });

  final List<TimeMarker> markers;
  final double durationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint baselinePaint = Paint()
      ..color = Colors.grey.shade500
      ..strokeWidth = 2;
    final double centerY = size.height / 2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      baselinePaint,
    );

    for (int i = 0; i < markers.length; i++) {
      final TimeMarker marker = markers[i];
      final double x =
          (marker.timeSeconds / math.max(durationSeconds, 0.001)).clamp(
            0.0,
            1.0,
          ) *
          size.width;
      final Paint markerPaint = Paint()
        ..color = _markerColor(i, marker)
        ..strokeWidth = 3;
      canvas.drawLine(
        Offset(x, centerY - 40),
        Offset(x, centerY + 40),
        markerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerOverviewPainter oldDelegate) {
    return oldDelegate.markers != markers ||
        oldDelegate.durationSeconds != durationSeconds;
  }
}

class _MarkerSelectionPanel extends StatelessWidget {
  const _MarkerSelectionPanel({
    required this.dataset,
    required this.markers,
    required this.includedMarkers,
    required this.onChanged,
  });

  final Dataset? dataset;
  final List<TimeMarker> markers;
  final Map<String, dynamic> includedMarkers;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (dataset == null) {
      return const Center(child: Text('No dataset available.'));
    }
    if (markers.isEmpty) {
      return const Center(
        child: Text('No markers available in the first selected dataset.'),
      );
    }

    final List<_MarkerLabelSummary> groups = _summarizeMarkersByLabel(markers);
    final int selectedCount = groups
        .where(
          (_MarkerLabelSummary group) =>
              (includedMarkers[group.key] as bool?) ?? false,
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '$selectedCount / ${groups.length} selected',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                onChanged(<String, dynamic>{
                  for (final _MarkerLabelSummary group in groups)
                    group.key: true,
                });
              },
              child: const Text('Select all'),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => onChanged(<String, dynamic>{}),
              child: const Text('Unselect all'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: groups.length,
            itemBuilder: (BuildContext context, int index) {
              final _MarkerLabelSummary group = groups[index];
              final String key = group.key;
              final bool included = (includedMarkers[key] as bool?) ?? false;
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: included,
                secondary: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _markerColor(index, group.sampleMarker),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(group.label, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '${group.kind} • ${group.count} marker${group.count == 1 ? '' : 's'}',
                ),
                onChanged: (bool? value) {
                  final Map<String, dynamic> nextMap =
                      Map<String, dynamic>.from(includedMarkers);
                  if (value == true) {
                    nextMap[key] = true;
                  } else {
                    nextMap.remove(key);
                  }
                  onChanged(nextMap);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MarkerLabelSummary {
  const _MarkerLabelSummary({
    required this.key,
    required this.label,
    required this.kind,
    required this.count,
    required this.sampleMarker,
  });

  final String key;
  final String label;
  final String kind;
  final int count;
  final TimeMarker sampleMarker;
}

List<_MarkerLabelSummary> _summarizeMarkersByLabel(List<TimeMarker> markers) {
  final Map<String, _MarkerLabelSummary> grouped =
      <String, _MarkerLabelSummary>{};
  for (final TimeMarker marker in markers) {
    final String key = markerKeyForMarker(marker);
    final _MarkerLabelSummary? existing = grouped[key];
    if (existing == null) {
      grouped[key] = _MarkerLabelSummary(
        key: key,
        label: marker.label,
        kind: marker.kind,
        count: 1,
        sampleMarker: marker,
      );
    } else {
      grouped[key] = _MarkerLabelSummary(
        key: key,
        label: existing.label,
        kind: existing.kind,
        count: existing.count + 1,
        sampleMarker: existing.sampleMarker,
      );
    }
  }
  final List<_MarkerLabelSummary> summaries = grouped.values.toList(
    growable: false,
  );
  summaries.sort((_MarkerLabelSummary a, _MarkerLabelSummary b) {
    final int kindCompare = a.kind.compareTo(b.kind);
    if (kindCompare != 0) {
      return kindCompare;
    }
    return a.label.compareTo(b.label);
  });
  return summaries;
}

Color _markerColor(int index, TimeMarker marker) {
  if (marker.kind == 'artifact') {
    return Colors.redAccent;
  }
  const List<Color> palette = <Color>[
    Colors.teal,
    Colors.deepPurple,
    Colors.orange,
    Colors.blue,
    Colors.pink,
    Colors.green,
  ];
  return palette[index % palette.length];
}
