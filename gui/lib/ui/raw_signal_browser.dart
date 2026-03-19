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
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback? onChanged;

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

  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  Object? _filterCacheKey;
  List<List<double>>? _filteredChannels;

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
              final double labelWidth = 160;
              final double traceWidth =
                  math.max(200, constraints.maxWidth - labelWidth);
              final double secondsPerView =
                  (widget.params['window_sec'] as num?)?.toDouble() ?? 5.0;
              final double pixelsPerSecond = traceWidth / secondsPerView;
              final double totalWidth =
                  math.max(traceWidth, durationSeconds * pixelsPerSecond);
              final double totalHeight = math.max(
                constraints.maxHeight,
                _channelHeight(constraints.maxHeight, visibleChannels) *
                    channelCount,
              );
              final List<TimeMarker> markers = _markersForDataset();

              return DecoratedBox(
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
                                  constraints.maxHeight,
                                  visibleChannels,
                                ),
                                onCycleColor: _cycleChannelColor,
                              ),
                            ),
                            const SizedBox(width: 8),
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
                                                  constraints.maxHeight,
                                                  visibleChannels,
                                                ),
                                                pixelsPerSecond: pixelsPerSecond,
                                                gain: (widget.params['gain'] as num?)
                                                        ?.toDouble() ??
                                                    1.0,
                                                colors: List<Color>.generate(
                                                  channelCount,
                                                  (int index) => _colorForChannel(index),
                                                  growable: false,
                                                ),
                                                markers: markers,
                                                amplitudeReference:
                                                    _amplitudeReference(channels),
                                                horizontalOffset:
                                                    _horizontalController.hasClients
                                                        ? _horizontalController.offset
                                                        : 0.0,
                                                verticalOffset:
                                                    _verticalController.hasClients
                                                        ? _verticalController.offset
                                                        : 0.0,
                                                viewportWidth: traceWidth,
                                                viewportHeight: constraints.maxHeight,
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
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _MarkerList(
          markers: _markersForDataset(),
          onDelete: _deleteMarker,
        ),
      ],
    );
  }

  Widget _buildControlBar({
    required double sampleRate,
    required int channelCount,
  }) {
    final double windowSeconds =
        (widget.params['window_sec'] as num?)?.toDouble() ?? 5.0;
    final double gain = (widget.params['gain'] as num?)?.toDouble() ?? 1.0;
    final bool previewBandpass =
        (widget.params['preview_bandpass'] as bool?) ?? false;
    final double previewLow =
        (widget.params['preview_low'] as num?)?.toDouble() ?? 1.0;
    final double previewHigh =
        (widget.params['preview_high'] as num?)?.toDouble() ?? 40.0;
    final String markerMode =
        (widget.params['marker_mode'] ?? 'off').toString();

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
            Switch(
              value: previewBandpass,
              onChanged: (bool value) {
                _updateParam('preview_bandpass', value);
              },
            ),
            const Text(
              'Preview bandpass',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
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
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledSlider(
                label: 'Gain',
                value: gain.clamp(0.5, 6.0),
                min: 0.5,
                max: 6.0,
                divisions: 22,
                displayValue: '${gain.toStringAsFixed(2)}x',
                onChanged: (double value) => _updateParam('gain', value),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
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
            const SizedBox(width: 12),
            Expanded(
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
            const SizedBox(width: 12),
            Expanded(
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

    final List<TimeMarker> currentMarkers = _markersForDataset();
    final TimeMarker marker = TimeMarker(
      timeSeconds: localPosition.dx / pixelsPerSecond,
      label: markerMode == 'artifact'
          ? 'Artifact ${currentMarkers.length + 1}'
          : 'Marker ${currentMarkers.length + 1}',
      kind: markerMode,
    );

    _setMarkersForDataset(<TimeMarker>[
      ...currentMarkers,
      marker,
    ]);
  }

  void _deleteMarker(TimeMarker marker) {
    _setMarkersForDataset(
      _markersForDataset()
          .where((TimeMarker existing) => existing != marker)
          .toList(growable: false),
    );
  }

  List<TimeMarker> _markersForDataset() {
    final List<dynamic> rawMarkers =
        widget.params['markers'] as List<dynamic>? ?? <dynamic>[];
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

  void _setMarkersForDataset(List<TimeMarker> markers) {
    final List<dynamic> rawMarkers =
        widget.params['markers'] as List<dynamic>? ?? <dynamic>[];
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
      widget.params['markers'] = preservedMarkers;
      final TimeSeriesData? timeSeries = widget.dataset.timeSeries;
      if (timeSeries != null) {
        widget.dataset.timeSeries = timeSeries.copyWith(markers: markers);
      }
    });
    widget.onChanged?.call();
  }

  void _ensureDefaults() {
    widget.params.putIfAbsent('window_sec', () => 5.0);
    widget.params.putIfAbsent('gain', () => 1.0);
    widget.params.putIfAbsent('visible_channel_count', () => 8);
    widget.params.putIfAbsent('preview_bandpass', () => false);
    widget.params.putIfAbsent('preview_low', () => 1.0);
    widget.params.putIfAbsent('preview_high', () => 40.0);
    widget.params.putIfAbsent('marker_mode', () => 'off');
    widget.params.putIfAbsent('markers', () => <Map<String, dynamic>>[]);
    widget.params.putIfAbsent('channel_colors', () => <String, dynamic>{});
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

  double _amplitudeReference(List<List<double>> channels) {
    double maxAbs = 0.0;
    for (final List<double> channel in channels) {
      final int step = math.max(1, channel.length ~/ 2000);
      for (int index = 0; index < channel.length; index += step) {
        final double absValue = channel[index].abs();
        if (absValue > maxAbs) {
          maxAbs = absValue;
        }
      }
    }
    return maxAbs == 0 ? 1.0 : maxAbs;
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
        Row(
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
            const Spacer(),
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
    required this.gain,
    required this.colors,
    required this.markers,
    required this.amplitudeReference,
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
  final double gain;
  final List<Color> colors;
  final List<TimeMarker> markers;
  final double amplitudeReference;
  final double horizontalOffset;
  final double verticalOffset;
  final double viewportWidth;
  final double viewportHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double startTime = horizontalOffset / pixelsPerSecond;
    final double endTime = (horizontalOffset + viewportWidth) / pixelsPerSecond;
    final int startSample =
        math.max(0, (startTime * sampleRate).floor() - 1);
    final int endSample =
        math.min(channels.first.length, (endTime * sampleRate).ceil() + 1);
    final int firstChannel =
        math.max(0, (verticalOffset / channelHeight).floor() - 1);
    final int lastChannel =
        math.min(
          channels.length - 1,
          ((verticalOffset + viewportHeight) / channelHeight).ceil() + 1,
        );

    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final Paint baselinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;

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

    final double verticalScale = (channelHeight * 0.35) * gain;
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
        final double y =
            centerY - ((samples[sampleIndex] / amplitudeReference) * verticalScale);
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
        oldDelegate.gain != gain ||
        oldDelegate.markers != markers ||
        oldDelegate.amplitudeReference != amplitudeReference ||
        oldDelegate.colors != colors ||
        oldDelegate.horizontalOffset != horizontalOffset ||
        oldDelegate.verticalOffset != verticalOffset ||
        oldDelegate.viewportWidth != viewportWidth ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}
