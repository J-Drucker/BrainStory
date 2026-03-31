import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/bandpass_node.dart';

class RawSignalBrowser extends StatefulWidget {
  const RawSignalBrowser({
    super.key,
    required this.dataset,
    required this.params,
    this.onChanged,
    this.onMarkersChanged,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback? onChanged;
  final ValueChanged<List<dynamic>>? onMarkersChanged;

  @override
  State<RawSignalBrowser> createState() => _RawSignalBrowserState();
}

class _RawSignalBrowserState extends State<RawSignalBrowser> {
  static const List<Color> _palette = <Color>[
    Colors.cyanAccent,
    Colors.orangeAccent,
    Colors.lightGreenAccent,
    Colors.pinkAccent,
    Colors.amberAccent,
    Colors.deepPurpleAccent,
    Colors.redAccent,
    Colors.tealAccent,
  ];
  static const List<double> _yScaleOptionsUv = <double>[
    10,
    25,
    50,
    100,
    200,
    500,
    1000,
  ];

  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  Object? _filterCacheKey;
  List<List<double>>? _filteredChannels;
  List<Map<String, dynamic>>? _draftMarkers;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
    _horizontalController = ScrollController();
    _ensureDefaults();
  }

  @override
  void didUpdateWidget(covariant RawSignalBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureDefaults();
    if (oldWidget.dataset.id != widget.dataset.id) {
      _draftMarkers = null;
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TimeSeriesData? timeSeries = widget.dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) {
      return const _BrowserMessage(
        title: 'No time-domain signal',
        body: 'Run an Import or signal-processing path upstream of this visualization node first.',
      );
    }

    final List<List<double>> channels = _effectiveChannels(timeSeries);
    final List<String> labels = _channelLabels(timeSeries, channels.length);
    final int channelCount = channels.length;
    final double durationSeconds = timeSeries.sampleCount / timeSeries.sampleRate;
    final int visibleChannels = _visibleChannelCount(channelCount);
    final bool markersOnly = _rawViewMode() == 'markers_only';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildControlBar(
          sampleRate: timeSeries.sampleRate,
          channelCount: channelCount,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double labelWidth =
                  markersOnly ? 0 : (constraints.maxWidth < 900 ? 112 : 160);
              final double traceWidth =
                  math.max(200, constraints.maxWidth - labelWidth);
              final double secondsPerView =
                  (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
              final double pixelsPerSecond = traceWidth / secondsPerView;
              final double totalWidth =
                  math.max(traceWidth, durationSeconds * pixelsPerSecond);
              final double timelineHeight = 28;
              final double traceAreaHeight =
                  math.max(120, constraints.maxHeight - timelineHeight - 12);
              final double totalHeight = markersOnly
                  ? traceAreaHeight
                  : math.max(
                      traceAreaHeight,
                      _channelHeight(traceAreaHeight, visibleChannels) * channelCount,
                    );
              final List<TimeMarker> markers = _currentMarkersForDataset();

              return Column(
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Scrollbar(
                          controller: _verticalController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _verticalController,
                            scrollDirection: Axis.vertical,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: totalHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (!markersOnly)
                                    SizedBox(
                                      width: labelWidth,
                                      child: _ChannelLabelColumn(
                                        labels: labels,
                                        colors: List<Color>.generate(
                                          channelCount,
                                          (int index) => _colorForChannel(index),
                                          growable: false,
                                        ),
                                        channelHeight: _channelHeight(
                                          traceAreaHeight,
                                          visibleChannels,
                                        ),
                                        onCycleColor: _cycleChannelColor,
                                      ),
                                    ),
                                  if (!markersOnly) const SizedBox(width: 8),
                                  Expanded(
                                    child: Scrollbar(
                                      controller: _horizontalController,
                                      thumbVisibility: true,
                                      notificationPredicate:
                                          (ScrollNotification notification) =>
                                              notification.metrics.axis ==
                                              Axis.horizontal,
                                      child: SingleChildScrollView(
                                        controller: _horizontalController,
                                        scrollDirection: Axis.horizontal,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTapDown: (TapDownDetails details) {
                                            _handleMarkerTap(
                                              details.localPosition,
                                              pixelsPerSecond,
                                            );
                                          },
                                          child: SizedBox(
                                            width: totalWidth,
                                            height: totalHeight,
                                            child: RepaintBoundary(
                                              child: AnimatedBuilder(
                                                animation: Listenable.merge(
                                                  <Listenable>[
                                                    _horizontalController,
                                                    _verticalController,
                                                  ],
                                                ),
                                                builder: (BuildContext context, Widget? child) {
                                                  return CustomPaint(
                                                    painter: _RawSignalPainter(
                                                      channels: channels,
                                                      channelLabels: labels,
                                                      sampleRate: timeSeries.sampleRate,
                                                      channelHeight: _channelHeight(
                                                        traceAreaHeight,
                                                        visibleChannels,
                                                      ),
                                                      pixelsPerSecond: pixelsPerSecond,
                                                      yScaleUv: _yScaleUv(),
                                                      showSignals: !markersOnly,
                                                      colors: List<Color>.generate(
                                                        channelCount,
                                                        (int index) => _colorForChannel(index),
                                                        growable: false,
                                                      ),
                                                      markers: markers,
                                                      horizontalOffset:
                                                          _horizontalController.hasClients
                                                              ? _horizontalController.offset
                                                              : 0.0,
                                                      verticalOffset:
                                                          _verticalController.hasClients
                                                              ? _verticalController.offset
                                                              : 0.0,
                                                      viewportWidth: traceWidth,
                                                      viewportHeight: traceAreaHeight,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TimelineBar(
                    controller: _horizontalController,
                    totalWidth: totalWidth,
                    viewportWidth: traceWidth,
                    durationSeconds: durationSeconds,
                  ),
                ],
              );
            },
          ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_hasMarkerDraft) ...<Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: _discardMarkerDraft,
                        child: const Text('Discard Changes'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saveMarkerDraft,
                        child: const Text('Save Markers'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                _MarkerSection(
                  expanded: (widget.params['marker_list_expanded'] as bool?) ?? false,
                  markers: _currentMarkersForDataset(),
                  onToggle: (bool expanded) =>
                      _updateParam('marker_list_expanded', expanded),
                  onDelete: _deleteMarker,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlBar({
    required double sampleRate,
    required int channelCount,
  }) {
    final double windowSeconds =
        (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
    final bool previewBandpass =
        (widget.params['preview_bandpass'] as bool?) ?? false;
    final double previewLow =
        (widget.params['preview_low'] as num?)?.toDouble() ?? 1.0;
    final double previewHigh =
        (widget.params['preview_high'] as num?)?.toDouble() ?? 40.0;
    final String markerMode =
        (widget.params['marker_mode'] ?? 'off').toString();
    final String rawViewMode = _rawViewMode();
    final bool controlsExpanded =
        (widget.params['controls_expanded'] as bool?) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '${widget.dataset.label}  •  $channelCount ch  •  ${sampleRate.toStringAsFixed(1)} Hz',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                rawViewMode == 'markers_only'
                    ? 'View: Markers only'
                    : 'View: Signals + markers',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Markers: ${markerMode == 'off' ? 'Off' : markerMode == 'event' ? 'Marker' : 'Artifact'}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            FilterChip(
              label: const Text('Preview bandpass'),
              selected: previewBandpass,
              onSelected: (bool value) {
                _updateParam('preview_bandpass', value);
              },
            ),
            _ScaleMenu(
              scaleUv: _yScaleUv(),
              optionsUv: _yScaleOptionsUv,
              onSelected: (double value) => _updateParam('y_scale_uv', value),
            ),
            OutlinedButton.icon(
              onPressed: () => _updateParam('controls_expanded', !controlsExpanded),
              icon: Icon(
                controlsExpanded ? Icons.expand_less : Icons.tune,
                size: 18,
              ),
              label: Text(controlsExpanded ? 'Hide Controls' : 'Show Controls'),
            ),
          ],
        ),
        if (controlsExpanded) ...<Widget>[
          const SizedBox(height: 8),
          _LabeledValue(
            label: 'View',
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'signals', label: Text('Signals')),
                ButtonSegment<String>(
                  value: 'markers_only',
                  label: Text('Markers Only'),
                ),
              ],
              selected: <String>{rawViewMode},
              onSelectionChanged: (Set<String> selection) {
                _updateParam('raw_view_mode', selection.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          _LabeledValue(
            label: 'Marker Mode',
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'off', label: Text('Off')),
                ButtonSegment<String>(value: 'event', label: Text('Marker')),
                ButtonSegment<String>(value: 'artifact', label: Text('Artifact')),
              ],
              selected: <String>{markerMode},
              onSelectionChanged: (Set<String> selection) {
                _updateParam('marker_mode', selection.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: 260,
                child: _LabeledSlider(
                  label: 'Time span',
                  value: windowSeconds.clamp(1.0, 30.0),
                  min: 1.0,
                  max: 30.0,
                  divisions: 29,
                  displayValue: '${windowSeconds.toStringAsFixed(0)} s',
                  onChanged: (double value) => _updateParam('window_sec', value),
                ),
              ),
              SizedBox(
                width: 260,
                child: _ScaleMenuCard(
                  scaleUv: _yScaleUv(),
                  optionsUv: _yScaleOptionsUv,
                  onSelected: (double value) => _updateParam('y_scale_uv', value),
                ),
              ),
              SizedBox(
                width: 260,
                child: _LabeledSlider(
                  label: 'Visible channels',
                  value: _visibleChannelCount(channelCount).toDouble(),
                  min: 1.0,
                  max: channelCount.toDouble(),
                  divisions: channelCount > 1 ? channelCount - 1 : null,
                  displayValue: _visibleChannelCount(channelCount).toString(),
                  onChanged: (double value) =>
                      _updateParam('visible_channel_count', value.round()),
                ),
              ),
              SizedBox(
                width: 260,
                child: _LabeledSlider(
                  label: 'Preview low',
                  value: previewLow.clamp(0.5, 40.0),
                  min: 0.5,
                  max: 40.0,
                  divisions: 79,
                  displayValue: '${previewLow.toStringAsFixed(1)} Hz',
                  onChanged: previewBandpass
                      ? (double value) => _updateParam('preview_low', value)
                      : null,
                ),
              ),
              SizedBox(
                width: 260,
                child: _LabeledSlider(
                  label: 'Preview high',
                  value: previewHigh.clamp(5.0, 80.0),
                  min: 5.0,
                  max: 80.0,
                  divisions: 75,
                  displayValue: '${previewHigh.toStringAsFixed(1)} Hz',
                  onChanged: previewBandpass
                      ? (double value) => _updateParam('preview_high', value)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _updateParam(String key, dynamic value) {
    setState(() {
      widget.params[key] = value;
      if (key == 'preview_bandpass' ||
          key == 'preview_low' ||
          key == 'preview_high') {
        _filterCacheKey = null;
      }
    });
    widget.onChanged?.call();
  }

  void _handleMarkerTap(Offset localPosition, double pixelsPerSecond) {
    final String markerMode = (widget.params['marker_mode'] ?? 'off').toString();
    if (markerMode == 'off') {
      return;
    }

    final List<TimeMarker> currentMarkers = _currentMarkersForDataset();
    final TimeMarker marker = TimeMarker(
      timeSeconds: localPosition.dx / pixelsPerSecond,
      label: markerMode == 'artifact'
          ? 'Artifact ${currentMarkers.length + 1}'
          : 'Marker ${currentMarkers.length + 1}',
      kind: markerMode,
    );

    _setDraftMarkersForDataset(<TimeMarker>[
      ...currentMarkers,
      marker,
    ]);
  }

  void _deleteMarker(TimeMarker marker) {
    _setDraftMarkersForDataset(
      _currentMarkersForDataset()
          .where((TimeMarker existing) => existing != marker)
          .toList(growable: false),
    );
  }

  List<TimeMarker> _currentMarkersForDataset() {
    final List<dynamic> rawMarkers = _effectiveRawMarkers;
    return rawMarkers
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> marker) => marker['datasetId'] == widget.dataset.id)
        .map((Map<String, dynamic> marker) {
          final Map<String, dynamic> payload = Map<String, dynamic>.from(marker);
          payload.remove('datasetId');
          return TimeMarker.fromJson(payload);
        })
        .toList(growable: false);
  }

  List<dynamic> get _effectiveRawMarkers =>
      _draftMarkers ?? (widget.params['markers'] as List<dynamic>? ?? <dynamic>[]);

  bool get _hasMarkerDraft => _draftMarkers != null;

  void _setDraftMarkersForDataset(List<TimeMarker> markers) {
    final List<dynamic> rawMarkers = _effectiveRawMarkers;
    final List<Map<String, dynamic>> preservedMarkers = rawMarkers
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> marker) => marker['datasetId'] != widget.dataset.id)
        .map((Map<String, dynamic> marker) => Map<String, dynamic>.from(marker))
        .toList(growable: true);

    for (final TimeMarker marker in markers) {
      preservedMarkers.add(<String, dynamic>{
        'datasetId': widget.dataset.id,
        ...marker.toJson(),
      });
    }

    setState(() {
      _draftMarkers = preservedMarkers;
    });
    widget.onChanged?.call();
  }

  void _saveMarkerDraft() {
    final List<Map<String, dynamic>>? draftMarkers = _draftMarkers;
    if (draftMarkers == null) {
      return;
    }
    setState(() {
      widget.params['markers'] = draftMarkers;
      _draftMarkers = null;
    });
    widget.onMarkersChanged?.call(draftMarkers);
    widget.onChanged?.call();
  }

  void _discardMarkerDraft() {
    setState(() {
      _draftMarkers = null;
    });
    widget.onChanged?.call();
  }

  void _ensureDefaults() {
    widget.params.putIfAbsent('window_sec', () => 10.0);
    widget.params.remove('gain');
    widget.params.putIfAbsent('visible_channel_count', () => 8);
    widget.params.putIfAbsent('preview_bandpass', () => false);
    widget.params.putIfAbsent('preview_low', () => 1.0);
    widget.params.putIfAbsent('preview_high', () => 40.0);
    widget.params.putIfAbsent('marker_mode', () => 'off');
    widget.params.putIfAbsent('markers', () => <Map<String, dynamic>>[]);
    widget.params.putIfAbsent('channel_colors', () => <String, dynamic>{});
    widget.params.putIfAbsent('controls_expanded', () => false);
    widget.params.putIfAbsent('marker_list_expanded', () => false);
    widget.params.putIfAbsent('y_scale_uv', () => 100.0);
    widget.params.putIfAbsent('raw_view_mode', () => 'signals');
  }

  List<List<double>> _effectiveChannels(TimeSeriesData timeSeries) {
    final bool previewBandpass =
        (widget.params['preview_bandpass'] as bool?) ?? false;
    if (!previewBandpass) {
      return timeSeries.channels;
    }

    final double previewLow =
        (widget.params['preview_low'] as num?)?.toDouble() ?? 1.0;
    final double previewHigh =
        (widget.params['preview_high'] as num?)?.toDouble() ?? 40.0;
    final Object cacheKey = Object.hash(
      widget.dataset.id,
      timeSeries.sampleRate,
      timeSeries.sampleCount,
      previewLow,
      previewHigh,
      previewBandpass,
    );
    if (_filterCacheKey == cacheKey && _filteredChannels != null) {
      return _filteredChannels!;
    }

    _filteredChannels = timeSeries.channels
        .map(
          (List<double> channel) => applyBandpassFilter(
            channel,
            sampleRate: timeSeries.sampleRate,
            lowCutHz: previewLow,
            highCutHz: previewHigh,
            steepness: 0.8,
          ),
        )
        .toList(growable: false);
    _filterCacheKey = cacheKey;
    return _filteredChannels!;
  }

  List<String> _channelLabels(TimeSeriesData timeSeries, int channelCount) {
    if (timeSeries.channelLabels.length == channelCount) {
      return timeSeries.channelLabels;
    }
    return List<String>.generate(
      channelCount,
      (int index) => index < timeSeries.channelLabels.length
          ? timeSeries.channelLabels[index]
          : 'Ch ${index + 1}',
      growable: false,
    );
  }

  int _visibleChannelCount(int channelCount) {
    final int preferred =
        (widget.params['visible_channel_count'] as num?)?.round() ?? 8;
    return preferred.clamp(1, math.max(1, channelCount));
  }

  double _channelHeight(double viewportHeight, int visibleChannels) {
    return math.max(56.0, viewportHeight / math.max(1, visibleChannels));
  }

  double _yScaleUv() {
    final double requested = (widget.params['y_scale_uv'] as num?)?.toDouble() ?? 100.0;
    double closest = _yScaleOptionsUv.first;
    double bestDistance = (requested - closest).abs();
    for (final double option in _yScaleOptionsUv.skip(1)) {
      final double distance = (requested - option).abs();
      if (distance < bestDistance) {
        closest = option;
        bestDistance = distance;
      }
    }
    return closest;
  }

  String _rawViewMode() {
    final String mode = (widget.params['raw_view_mode'] ?? 'signals').toString();
    return mode == 'markers_only' ? 'markers_only' : 'signals';
  }

  Color _colorForChannel(int channelIndex) {
    final Map<String, dynamic> colorMap =
        Map<String, dynamic>.from(widget.params['channel_colors'] as Map? ?? <String, dynamic>{});
    final String key = '${widget.dataset.id}:$channelIndex';
    final int? colorValue = colorMap[key] as int?;
    if (colorValue != null) {
      return Color(colorValue);
    }
    return _palette[channelIndex % _palette.length];
  }

  void _cycleChannelColor(int channelIndex) {
    final Color current = _colorForChannel(channelIndex);
    final int currentIndex = _palette.indexWhere(
      (Color color) => color.toARGB32() == current.toARGB32(),
    );
    final Color nextColor = _palette[(currentIndex + 1) % _palette.length];
    final Map<String, dynamic> colorMap =
        Map<String, dynamic>.from(widget.params['channel_colors'] as Map? ?? <String, dynamic>{});
    colorMap['${widget.dataset.id}:$channelIndex'] = nextColor.toARGB32();
    setState(() {
      widget.params['channel_colors'] = colorMap;
    });
    widget.onChanged?.call();
  }
}

class _ScaleMenu extends StatelessWidget {
  const _ScaleMenu({
    required this.scaleUv,
    required this.optionsUv,
    required this.onSelected,
  });

  final double scaleUv;
  final List<double> optionsUv;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Y-axis scale',
      onSelected: onSelected,
      itemBuilder: (BuildContext context) {
        return optionsUv.map((double option) {
          return PopupMenuItem<double>(
            value: option,
            child: Text('${option.toStringAsFixed(option < 100 ? 0 : 0)} uV'),
          );
        }).toList(growable: false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Scale: ${scaleUv.toStringAsFixed(0)} uV',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class _ScaleMenuCard extends StatelessWidget {
  const _ScaleMenuCard({
    required this.scaleUv,
    required this.optionsUv,
    required this.onSelected,
  });

  final double scaleUv;
  final List<double> optionsUv;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return _LabeledValue(
      label: 'Y Scale',
      child: DropdownButtonFormField<double>(
        initialValue: scaleUv,
        decoration: const InputDecoration(
          labelText: 'Microvolts per division',
        ),
        items: optionsUv
            .map(
              (double option) => DropdownMenuItem<double>(
                value: option,
                child: Text('${option.toStringAsFixed(0)} uV'),
              ),
            )
            .toList(growable: false),
        onChanged: (double? value) {
          if (value != null) {
            onSelected(value);
          }
        },
      ),
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String displayValue;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              displayValue,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: displayValue,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ChannelLabelColumn extends StatelessWidget {
  const _ChannelLabelColumn({
    required this.labels,
    required this.colors,
    required this.channelHeight,
    required this.onCycleColor,
  });

  final List<String> labels;
  final List<Color> colors;
  final double channelHeight;
  final ValueChanged<int> onCycleColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(labels.length, (int index) {
        return SizedBox(
          height: channelHeight,
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: () => onCycleColor(index),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: colors[index],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  labels[index],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }, growable: false),
    );
  }
}

class _MarkerList extends StatelessWidget {
  const _MarkerList({
    required this.markers,
    required this.onDelete,
  });

  final List<TimeMarker> markers;
  final ValueChanged<TimeMarker> onDelete;

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) {
      return const Text(
        'No markers placed yet. Switch marker mode from Off to place markers inside the trace view.',
        style: TextStyle(color: Colors.white70),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: markers.map((TimeMarker marker) {
        final bool isArtifact = marker.kind == 'artifact';
        return InputChip(
          label: Text(
            '${marker.label} @ ${marker.timeSeconds.toStringAsFixed(2)} s',
          ),
          selected: isArtifact,
          selectedColor: Colors.redAccent.withValues(alpha: 0.25),
          onDeleted: () => onDelete(marker),
        );
      }).toList(growable: false),
    );
  }
}

class _MarkerSection extends StatelessWidget {
  const _MarkerSection({
    required this.expanded,
    required this.markers,
    required this.onToggle,
    required this.onDelete,
  });

  final bool expanded;
  final List<TimeMarker> markers;
  final ValueChanged<bool> onToggle;
  final ValueChanged<TimeMarker> onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => onToggle(!expanded),
              child: Row(
                children: <Widget>[
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Markers (${markers.length})',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (expanded) ...<Widget>[
              const SizedBox(height: 8),
              _MarkerList(
                markers: markers,
                onDelete: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimelineBar extends StatelessWidget {
  const _TimelineBar({
    required this.controller,
    required this.totalWidth,
    required this.viewportWidth,
    required this.durationSeconds,
  });

  final ScrollController controller;
  final double totalWidth;
  final double viewportWidth;
  final double durationSeconds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double barWidth = constraints.maxWidth;
              final double windowFraction = totalWidth <= 0
                  ? 1.0
                  : (viewportWidth / totalWidth).clamp(0.02, 1.0);
              final double thumbWidth = math.max(18, barWidth * windowFraction);
              final double maxOffset = math.max(0, totalWidth - viewportWidth);
              final double currentOffset =
                  controller.hasClients ? controller.offset : 0.0;
              final double normalizedOffset =
                  maxOffset == 0 ? 0.0 : (currentOffset / maxOffset).clamp(0.0, 1.0);
              final double travel = math.max(0, barWidth - thumbWidth);
              final double thumbLeft = travel * normalizedOffset;
              final double startSeconds = durationSeconds * normalizedOffset;
              final double visibleSeconds = durationSeconds * windowFraction;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (DragUpdateDetails details) {
                  if (!controller.hasClients || maxOffset == 0) {
                    return;
                  }
                  final double nextLeft =
                      (thumbLeft + details.delta.dx).clamp(0.0, travel);
                  controller.jumpTo((nextLeft / travel) * maxOffset);
                },
                onTapDown: (TapDownDetails details) {
                  if (!controller.hasClients || maxOffset == 0) {
                    return;
                  }
                  final double centeredLeft =
                      (details.localPosition.dx - (thumbWidth / 2)).clamp(0.0, travel);
                  controller.jumpTo((centeredLeft / travel) * maxOffset);
                },
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: thumbWidth,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.cyanAccent.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: <Widget>[
                            Text(
                              '${startSeconds.toStringAsFixed(1)} s',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${visibleSeconds.toStringAsFixed(1)} s window / ${durationSeconds.toStringAsFixed(1)} s total',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BrowserMessage extends StatelessWidget {
  const _BrowserMessage({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _RawSignalPainter extends CustomPainter {
  const _RawSignalPainter({
    required this.channels,
    required this.channelLabels,
    required this.sampleRate,
    required this.channelHeight,
    required this.pixelsPerSecond,
    required this.yScaleUv,
    required this.showSignals,
    required this.colors,
    required this.markers,
    required this.horizontalOffset,
    required this.verticalOffset,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final List<List<double>> channels;
  final List<String> channelLabels;
  final double sampleRate;
  final double channelHeight;
  final double pixelsPerSecond;
  final double yScaleUv;
  final bool showSignals;
  final List<Color> colors;
  final List<TimeMarker> markers;
  final double horizontalOffset;
  final double verticalOffset;
  final double viewportWidth;
  final double viewportHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double startTime = horizontalOffset / pixelsPerSecond;
    final double endTime = (horizontalOffset + viewportWidth) / pixelsPerSecond;
    final int startSample = channels.isEmpty
        ? 0
        : math.max(0, (startTime * sampleRate).floor() - 1);
    final int endSample = channels.isEmpty
        ? 0
        : math.min(channels.first.length, (endTime * sampleRate).ceil() + 1);
    final int firstChannel = showSignals
        ? math.max(0, (verticalOffset / channelHeight).floor() - 1)
        : 0;
    final int lastChannel = showSignals
        ? math.min(
            channels.length - 1,
            ((verticalOffset + viewportHeight) / channelHeight).ceil() + 1,
          )
        : -1;

    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final Paint baselinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final Paint scalePaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2;

    final double firstGridSecond = startTime.floorToDouble();
    for (double second = firstGridSecond; second <= endTime + 1; second += 1) {
      final double x = second * pixelsPerSecond;
      canvas.drawLine(
        Offset(x, verticalOffset),
        Offset(x, verticalOffset + viewportHeight),
        gridPaint,
      );
    }

    for (final TimeMarker marker in markers) {
      final double x = marker.timeSeconds * pixelsPerSecond;
      if (x < horizontalOffset - 24 ||
          x > horizontalOffset + viewportWidth + 24) {
        continue;
      }
      final Paint markerPaint = Paint()
        ..color = marker.kind == 'artifact'
            ? Colors.redAccent
            : Colors.amberAccent
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(x, verticalOffset),
        Offset(x, verticalOffset + viewportHeight),
        markerPaint,
      );
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: TextStyle(
            color: markerPaint.color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x + 4, verticalOffset + 4));
    }

    if (showSignals) {
      final double verticalScale = channelHeight * 0.35;
      final double pixelsPerUv = verticalScale / math.max(1.0, yScaleUv);
      final double scaleBarHeight = yScaleUv * pixelsPerUv;
      final double scaleBarX = horizontalOffset + 10;
      final double scaleBarTop = verticalOffset + 12;
      canvas.drawLine(
        Offset(scaleBarX, scaleBarTop),
        Offset(scaleBarX, scaleBarTop + scaleBarHeight),
        scalePaint,
      );
      canvas.drawLine(
        Offset(scaleBarX - 5, scaleBarTop),
        Offset(scaleBarX + 5, scaleBarTop),
        scalePaint,
      );
      canvas.drawLine(
        Offset(scaleBarX - 5, scaleBarTop + scaleBarHeight),
        Offset(scaleBarX + 5, scaleBarTop + scaleBarHeight),
        scalePaint,
      );
      final TextPainter scaleLabelPainter = TextPainter(
        text: TextSpan(
          text: '${yScaleUv.toStringAsFixed(0)} uV',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      scaleLabelPainter.paint(
        canvas,
        Offset(scaleBarX + 8, scaleBarTop + (scaleBarHeight / 2) - (scaleLabelPainter.height / 2)),
      );
    } else {
      final double centerY = verticalOffset + (viewportHeight / 2);
      canvas.drawLine(
        Offset(horizontalOffset, centerY),
        Offset(horizontalOffset + viewportWidth, centerY),
        baselinePaint,
      );
      return;
    }

    final double verticalScale = channelHeight * 0.35;
    final double pixelsPerUv = verticalScale / math.max(1.0, yScaleUv);
    for (int channelIndex = firstChannel; channelIndex <= lastChannel; channelIndex++) {
      final double centerY = (channelIndex * channelHeight) + (channelHeight / 2);
      canvas.drawLine(
        Offset(horizontalOffset, centerY),
        Offset(horizontalOffset + viewportWidth, centerY),
        baselinePaint,
      );

      final List<double> samples = channels[channelIndex];
      if (samples.isEmpty || endSample <= startSample) {
        continue;
      }

      final Path path = Path();
      for (int sampleIndex = startSample; sampleIndex < endSample; sampleIndex++) {
        final double x = (sampleIndex / sampleRate) * pixelsPerSecond;
        final double y = centerY - (samples[sampleIndex] * pixelsPerUv);
        if (sampleIndex == startSample) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      final Paint signalPaint = Paint()
        ..color = colors[channelIndex]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(path, signalPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RawSignalPainter oldDelegate) {
    return oldDelegate.channels != channels ||
        oldDelegate.sampleRate != sampleRate ||
        oldDelegate.channelHeight != channelHeight ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.yScaleUv != yScaleUv ||
        oldDelegate.showSignals != showSignals ||
        oldDelegate.markers != markers ||
        oldDelegate.colors != colors ||
        oldDelegate.horizontalOffset != horizontalOffset ||
        oldDelegate.verticalOffset != verticalOffset ||
        oldDelegate.viewportWidth != viewportWidth ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}
