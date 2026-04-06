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
        'eventBaselineStartMs': -200.0,
        'eventBaselineStopMs': 0.0,
        'blockConcatenate': false,
        'blockInvert': false,
        'equalWindowWidthMs': 1000.0,
        'equalWindowOverlapPercent': 0.0,
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
    params.putIfAbsent('eventBaselineStartMs', () => -200.0);
    params.putIfAbsent('eventBaselineStopMs', () => 0.0);
    params.putIfAbsent('blockConcatenate', () => false);
    params.putIfAbsent('blockInvert', () => false);
    params.putIfAbsent('equalWindowWidthMs', () => 1000.0);
    params.putIfAbsent('equalWindowOverlapPercent', () => 0.0);

    final List<Dataset> datasetList = datasets.values.toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    final List<dynamic> selectedIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[];
    final Dataset? activeDataset = _resolveActiveDataset(datasetList, selectedIds);
    final TimeSeriesData? timeSeries = activeDataset?.timeSeries;
    final List<TimeMarker> markers = timeSeries?.markers ?? const <TimeMarker>[];

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
                    options: _eventOptions(
                      params: params,
                      setState: setState,
                    ),
                  ),
                  const Divider(height: 24),
                  _SegmentationModeSection(
                    value: 'blocks',
                    title: 'Blocks',
                    description: 'Create segments from included marker spans.',
                    options: _blockOptions(
                      params: params,
                      setState: setState,
                    ),
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
                  child: _MarkerSelectionPanel(
                    dataset: activeDataset,
                    markers: markers,
                    includedMarkers:
                        Map<String, dynamic>.from(params['includedMarkers'] as Map? ?? <String, dynamic>{}),
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
    final Map<String, dynamic> includedMarkers =
        Map<String, dynamic>.from(params['includedMarkers'] as Map? ?? <String, dynamic>{});
    final List<SignalSegmentData> segments;

    switch (mode) {
      case 'equal_windows':
        segments = _buildEqualWindowSegments(
          timeSeries: timeSeries,
          widthMs: (params['equalWindowWidthMs'] as num?)?.toDouble() ?? 1000.0,
          overlapPercent:
              (params['equalWindowOverlapPercent'] as num?)?.toDouble() ?? 0.0,
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
        segments = _buildEventSegments(
          timeSeries: timeSeries,
          includedMarkers: includedMarkers,
          windowStartMs:
              (params['eventWindowStartMs'] as num?)?.toDouble() ?? -200.0,
          windowStopMs:
              (params['eventWindowStopMs'] as num?)?.toDouble() ?? 800.0,
        );
        break;
    }

    dataset.segmentedTimeSeries = SegmentedTimeSeriesData(
      segments: segments,
      sampleRate: timeSeries.sampleRate,
      channelLabels: timeSeries.channelLabels,
      source: timeSeries.source,
    );
    dataset.ram['segmentation.config'] = Map<String, dynamic>.from(params);
  }

  Dataset? _resolveActiveDataset(List<Dataset> datasets, List<dynamic> selectedIds) {
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

List<SignalSegmentData> _buildEqualWindowSegments({
  required TimeSeriesData timeSeries,
  required double widthMs,
  required double overlapPercent,
}) {
  final double sampleRate = timeSeries.sampleRate;
  final int sampleCount = timeSeries.sampleCount;
  if (sampleCount <= 0) {
    return const <SignalSegmentData>[];
  }

  final int widthSamples =
      math.max(1, ((widthMs / 1000.0) * sampleRate).round());
  final double overlapFraction = (overlapPercent / 100.0).clamp(0.0, 0.95);
  final int stepSamples =
      math.max(1, (widthSamples * (1.0 - overlapFraction)).round());
  final List<SignalSegmentData> segments = <SignalSegmentData>[];

  for (int startIndex = 0; startIndex + widthSamples <= sampleCount; startIndex += stepSamples) {
    final int stopIndex = startIndex + widthSamples;
    final SignalSegmentData? segment = _extractSegment(
      timeSeries: timeSeries,
      startIndex: startIndex,
      stopIndex: stopIndex,
      label: 'Window ${segments.length + 1}',
      kind: 'window',
    );
    if (segment != null) {
      segments.add(segment);
    }
  }

  if (segments.isEmpty && sampleCount > 0) {
    final SignalSegmentData? segment = _extractSegment(
      timeSeries: timeSeries,
      startIndex: 0,
      stopIndex: sampleCount,
      label: 'Window 1',
      kind: 'window',
    );
    if (segment != null) {
      segments.add(segment);
    }
  }

  return segments;
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

  final List<TimeMarker> selectedMarkers = timeSeries.markers
      .where((TimeMarker marker) => _markerIncluded(marker, includedMarkers))
      .toList(growable: false)
    ..sort((TimeMarker a, TimeMarker b) => a.timeSeconds.compareTo(b.timeSeconds));

  final List<_SampleInterval> blockIntervals = <_SampleInterval>[];
  for (int index = 0; index + 1 < selectedMarkers.length; index += 2) {
    final int startIndex =
        (selectedMarkers[index].timeSeconds * timeSeries.sampleRate).round();
    final int stopIndex =
        (selectedMarkers[index + 1].timeSeconds * timeSeries.sampleRate).round();
    final _SampleInterval? interval = _boundedInterval(
      startIndex: startIndex,
      stopIndex: stopIndex,
      sampleCount: sampleCount,
    );
    if (interval != null) {
      blockIntervals.add(interval);
    }
  }

  final List<_SampleInterval> intervals = invert
      ? _invertIntervals(blockIntervals, sampleCount)
      : blockIntervals;
  if (intervals.isEmpty) {
    return const <SignalSegmentData>[];
  }

  if (concatenate) {
    return <SignalSegmentData>[
      _concatenateIntervals(
        timeSeries: timeSeries,
        intervals: intervals,
      ),
    ];
  }

  final List<SignalSegmentData> segments = <SignalSegmentData>[];
  for (int index = 0; index < intervals.length; index++) {
    final _SampleInterval interval = intervals[index];
    final SignalSegmentData? segment = _extractSegment(
      timeSeries: timeSeries,
      startIndex: interval.startIndex,
      stopIndex: interval.stopIndex,
      label: invert ? 'Inverted Block ${index + 1}' : 'Block ${index + 1}',
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
    for (int channelIndex = 0; channelIndex < timeSeries.channelCount; channelIndex++) {
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
  return (includedMarkers[markerKeyForMarker(marker)] as bool?) ?? true;
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
    channelSamples: timeSeries.channels
        .map(
          (List<double> channel) => channel.sublist(
            interval.startIndex,
            interval.stopIndex,
          ),
        )
        .toList(growable: false),
    startSeconds: interval.startIndex / timeSeries.sampleRate,
    stopSeconds: interval.stopIndex / timeSeries.sampleRate,
    label: label,
    kind: kind,
    anchorTimeSeconds: anchorTimeSeconds,
  );
}

_SampleInterval? _boundedInterval({
  required int startIndex,
  required int stopIndex,
  required int sampleCount,
}) {
  final int boundedStart = startIndex.clamp(0, sampleCount);
  final int boundedStop = stopIndex.clamp(0, sampleCount);
  if (boundedStop <= boundedStart) {
    return null;
  }
  return _SampleInterval(
    startIndex: boundedStart,
    stopIndex: boundedStop,
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
    ..sort((_SampleInterval a, _SampleInterval b) => a.startIndex.compareTo(b.startIndex));
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
    inverted.add(
      _SampleInterval(startIndex: cursor, stopIndex: sampleCount),
    );
  }
  return inverted;
}

class _SampleInterval {
  const _SampleInterval({
    required this.startIndex,
    required this.stopIndex,
  });

  final int startIndex;
  final int stopIndex;
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
    final RadioGroupRegistry<String>? radioGroup = RadioGroup.maybeOf<String>(context);
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
                    Radio<String>(
                      value: value,
                    ),
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
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          description,
                          style: TextStyle(color: textColor),
                        ),
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
    Row(
      children: <Widget>[
        Expanded(
          child: _NumericOptionField(
            label: 'Baseline start (ms)',
            value: (params['eventBaselineStartMs'] as num?)?.toDouble() ?? -200.0,
            onChanged: (double value) => setState(() {
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
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
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
  const _MarkerOverview({
    required this.dataset,
    required this.markers,
  });

  final Dataset? dataset;
  final List<TimeMarker> markers;

  @override
  Widget build(BuildContext context) {
    if (dataset == null) {
      return const Center(
        child: Text('No dataset available.'),
      );
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
          (marker.timeSeconds / math.max(durationSeconds, 0.001)).clamp(0.0, 1.0) * size.width;
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
      return const Center(
        child: Text('No dataset available.'),
      );
    }
    if (markers.isEmpty) {
      return const Center(
        child: Text('No markers available in the first selected dataset.'),
      );
    }

    final List<_MarkerLabelSummary> groups = _summarizeMarkersByLabel(markers);
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (BuildContext context, int index) {
        final _MarkerLabelSummary group = groups[index];
        final String key = group.key;
        final bool included = (includedMarkers[key] as bool?) ?? true;
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
          title: Text(
            group.label,
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text('${group.kind} • ${group.count} marker${group.count == 1 ? '' : 's'}'),
          onChanged: (bool? value) {
            final Map<String, dynamic> nextMap = Map<String, dynamic>.from(includedMarkers);
            nextMap[key] = value ?? true;
            onChanged(nextMap);
          },
        );
      },
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
  final Map<String, _MarkerLabelSummary> grouped = <String, _MarkerLabelSummary>{};
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
  final List<_MarkerLabelSummary> summaries = grouped.values.toList(growable: false);
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
