import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/channel_coordinates_node.dart';
import 'viewer_chrome.dart';

class BridgeViewer extends StatefulWidget {
  const BridgeViewer({
    super.key,
    required this.dataset,
    required this.params,
    required this.onChanged,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback onChanged;

  @override
  State<BridgeViewer> createState() => _BridgeViewerState();
}

class _BridgeViewerState extends State<BridgeViewer> {
  static const List<double> _timeOptions = <double>[30, 60, 120, 300, 600];
  late final ScrollController _horizontalController;
  Offset? _hoverPosition;
  int? _hoveredPairIndex;
  int? _hoveredEpochIndex;
  BridgeDetectionData? _cachedBridge;
  TimeSeriesData? _cachedTimeSeries;
  List<_BridgePair> _cachedPairs = const <_BridgePair>[];
  _BridgeColorEncoding _cachedColorEncoding =
      const _BridgeColorEncoding.channelNumber();
  _BridgeValueBounds _cachedValueBounds = const _BridgeValueBounds(
    center: 0,
    range: 1,
  );

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController(keepScrollOffset: false);
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BridgeDetectionData? bridge = widget.dataset.bridgeDetection;
    if (bridge == null || bridge.frames.isEmpty || bridge.pairCount == 0) {
      return const Center(
        child: Text(
          'Run Bridge Detector to create pair traces.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    _ensureDisplayCache(bridge, widget.dataset.timeSeries);
    final List<_BridgePair> pairs = _cachedPairs;
    final List<Color> colors = _cachedColorEncoding.colors;
    final double signalDurationSeconds = widget.dataset.timeSeries == null
        ? 0
        : widget.dataset.timeSeries!.sampleCount /
              widget.dataset.timeSeries!.sampleRate;
    final double durationSeconds = math.max(
      signalDurationSeconds,
      math.max(
        bridge.epochSeconds,
        bridge.frames.last.endSampleExclusive / bridge.sampleRate,
      ),
    );
    final double dataRange = _cachedValueBounds.range;
    final List<double> rangeOptions = <double>[
      dataRange * 0.25,
      dataRange * 0.5,
      dataRange,
      dataRange * 2,
      dataRange * 4,
    ];
    final List<double> timeOptions = _timeOptionsForDuration(durationSeconds);
    final double secondsPerView = _nearestOption(
      (widget.params['bridgeViewer.secondsPerView'] as num?)?.toDouble() ??
          durationSeconds,
      timeOptions,
    );
    final double scoreRange = _nearestOption(
      (widget.params['bridgeViewer.scoreRange'] as num?)?.toDouble() ??
          dataRange,
      rangeOptions,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double axisWidth = 76;
        const double plotGap = 8;
        final double viewportWidth = math.max(
          160,
          constraints.maxWidth - axisWidth - plotGap - 20,
        );
        final double pixelsPerSecond = viewportWidth / secondsPerView;
        final double totalWidth = math.max(
          viewportWidth,
          durationSeconds * pixelsPerSecond,
        );
        final double traceHeight = math.max(150, constraints.maxHeight - 154);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  '${bridge.channelCount} channels • ${bridge.pairCount} pairs • ${bridge.frameCount} epochs',
                  style: const TextStyle(color: Colors.white70),
                ),
                const ViewerControlStripDivider(),
                const Text('Scale:', style: TextStyle(color: Colors.white70)),
                ViewerScalePillMenu<double>(
                  label: 'Time',
                  currentValue: secondsPerView,
                  valueText: _secondsLabel(secondsPerView),
                  tooltip: 'Time span',
                  options: timeOptions,
                  itemLabelBuilder: _secondsLabel,
                  onSelected: (double value) =>
                      _setParam('bridgeViewer.secondsPerView', value),
                ),
                ViewerScalePillMenu<double>(
                  label: 'Score',
                  currentValue: scoreRange,
                  valueText: scoreRange.toStringAsFixed(1),
                  tooltip: 'Score scale',
                  options: rangeOptions,
                  itemLabelBuilder: (double value) => value.toStringAsFixed(1),
                  onSelected: (double value) =>
                      _setParam('bridgeViewer.scoreRange', value),
                ),
                Text(
                  bridge.distanceNormalizedPairs.any((bool value) => value)
                      ? 'Coordinate distance normalized'
                      : 'No coordinate normalization',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: axisWidth,
                    child: _BridgeScoreAxis(
                      center: _cachedValueBounds.center,
                      range: scoreRange,
                    ),
                  ),
                  const SizedBox(width: plotGap),
                  Expanded(
                    child: ViewerTraceSurface(
                      child: SingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: MouseRegion(
                          key: const ValueKey<String>('bridge-trace-region'),
                          onHover: (PointerHoverEvent event) {
                            _updateHover(
                              event.localPosition,
                              bridge,
                              traceHeight,
                              pixelsPerSecond,
                            );
                          },
                          onExit: (_) => setState(() {
                            _hoverPosition = null;
                            _hoveredPairIndex = null;
                            _hoveredEpochIndex = null;
                          }),
                          child: SizedBox(
                            width: totalWidth,
                            height: traceHeight,
                            child: Stack(
                              clipBehavior: Clip.hardEdge,
                              children: <Widget>[
                                Positioned.fill(
                                  child: CustomPaint(
                                    key: const ValueKey<String>(
                                      'bridge-butterfly-plot',
                                    ),
                                    painter: _BridgeTracePainter(
                                      bridge: bridge,
                                      colors: colors,
                                      pixelsPerSecond: pixelsPerSecond,
                                      scoreRange: scoreRange,
                                      scoreCenter: _cachedValueBounds.center,
                                      hoveredPairIndex: _hoveredPairIndex,
                                    ),
                                  ),
                                ),
                                if (_hoverPosition != null &&
                                    _hoveredPairIndex != null &&
                                    _hoveredEpochIndex != null)
                                  _BridgeHoverCard(
                                    position: _hoverPosition!,
                                    pair: pairs[_hoveredPairIndex!],
                                    frame: bridge.frames[_hoveredEpochIndex!],
                                    score: bridge
                                        .frames[_hoveredEpochIndex!]
                                        .pairValues[_hoveredPairIndex!],
                                    sampleRate: bridge.sampleRate,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const SizedBox(width: axisWidth + plotGap),
                Expanded(
                  child: ViewerTimeAxisBar(
                    controller: _horizontalController,
                    pixelsPerSecond: pixelsPerSecond,
                    viewportWidth: viewportWidth,
                    durationSeconds: durationSeconds,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const SizedBox(width: axisWidth + plotGap),
                Expanded(
                  child: ViewerTimelineBar(
                    controller: _horizontalController,
                    totalWidth: totalWidth,
                    viewportWidth: viewportWidth,
                    durationSeconds: durationSeconds,
                    accentColor: const Color(0xFF8E7CFF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: axisWidth + plotGap),
              child: _BridgeColorLegend(encoding: _cachedColorEncoding),
            ),
          ],
        );
      },
    );
  }

  void _setParam(String key, double value) {
    setState(() => widget.params[key] = value);
    widget.onChanged();
  }

  void _ensureDisplayCache(
    BridgeDetectionData bridge,
    TimeSeriesData? timeSeries,
  ) {
    if (identical(_cachedBridge, bridge) &&
        identical(_cachedTimeSeries, timeSeries)) {
      return;
    }
    _cachedBridge = bridge;
    _cachedTimeSeries = timeSeries;
    _cachedPairs = _pairs(bridge);
    _cachedColorEncoding = _pairColorEncoding(
      _cachedPairs,
      bridge.channelCoordinates,
      timeSeries,
    );
    _cachedValueBounds = _valueBounds(bridge);
  }

  void _updateHover(
    Offset position,
    BridgeDetectionData bridge,
    double traceHeight,
    double pixelsPerSecond,
  ) {
    final double sample = (position.dx / pixelsPerSecond) * bridge.sampleRate;
    int epochIndex = 0;
    double bestDistance = double.infinity;
    for (int index = 0; index < bridge.frames.length; index++) {
      final double center =
          (bridge.frames[index].startSample +
              bridge.frames[index].endSampleExclusive) /
          2;
      final double distance = (center - sample).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        epochIndex = index;
      }
    }
    final BridgeEpochFrameData frame = bridge.frames[epochIndex];
    int pairIndex = 0;
    double nearestTraceDistance = double.infinity;
    for (int pair = 0; pair < frame.pairValues.length; pair++) {
      final double value = frame.pairValues[pair];
      if (!value.isFinite) continue;
      final double normalized =
          ((value - _cachedValueBounds.center) /
                  _resolvedScoreRange(_cachedValueBounds.range))
              .clamp(-0.5, 0.5);
      final double traceY =
          (traceHeight / 2) - (normalized * traceHeight * 0.82);
      final double distance = (traceY - position.dy).abs();
      if (distance < nearestTraceDistance) {
        nearestTraceDistance = distance;
        pairIndex = pair;
      }
    }
    setState(() {
      _hoverPosition = position;
      _hoveredPairIndex = pairIndex;
      _hoveredEpochIndex = epochIndex;
    });
  }

  double _resolvedScoreRange(double dataRange) {
    final List<double> options = <double>[
      dataRange * 0.25,
      dataRange * 0.5,
      dataRange,
      dataRange * 2,
      dataRange * 4,
    ];
    return _nearestOption(
      (widget.params['bridgeViewer.scoreRange'] as num?)?.toDouble() ??
          dataRange,
      options,
    );
  }
}

class _BridgePair {
  const _BridgePair({
    required this.firstIndex,
    required this.secondIndex,
    required this.firstLabel,
    required this.secondLabel,
  });

  final int firstIndex;
  final int secondIndex;
  final String firstLabel;
  final String secondLabel;
}

List<_BridgePair> _pairs(BridgeDetectionData bridge) {
  final List<_BridgePair> result = <_BridgePair>[];
  for (int first = 0; first < bridge.channelCount; first++) {
    for (int second = first + 1; second < bridge.channelCount; second++) {
      result.add(
        _BridgePair(
          firstIndex: first,
          secondIndex: second,
          firstLabel: bridge.channelLabels[first],
          secondLabel: bridge.channelLabels[second],
        ),
      );
    }
  }
  return result;
}

class _BridgeColorEncoding {
  const _BridgeColorEncoding({
    required this.colors,
    required this.label,
    required this.minimum,
    required this.maximum,
    this.units = '',
  });

  const _BridgeColorEncoding.channelNumber()
    : colors = const <Color>[],
      label = 'Mean channel number',
      minimum = 1,
      maximum = 1,
      units = '';

  final List<Color> colors;
  final String label;
  final double minimum;
  final double maximum;
  final String units;
}

_BridgeColorEncoding _pairColorEncoding(
  List<_BridgePair> pairs,
  Map<String, ChannelCoordinate> bridgeCoordinates,
  TimeSeriesData? timeSeries,
) {
  final Map<String, ChannelCoordinate> coordinates =
      Map<String, ChannelCoordinate>.from(bridgeCoordinates);
  if (timeSeries != null) {
    for (final _BridgePair pair in pairs) {
      for (final String label in <String>[pair.firstLabel, pair.secondLabel]) {
        final ChannelCoordinate? coordinate =
            ChannelCoordinatesNodeType.coordinateForChannelLabel(
              timeSeries.channelCoordinates,
              label,
            );
        if (coordinate != null) {
          coordinates.putIfAbsent(label, () => coordinate);
        }
      }
    }
  }
  final Set<String> requiredLabels = pairs
      .expand((_BridgePair pair) => <String>[pair.firstLabel, pair.secondLabel])
      .toSet();
  if (requiredLabels.isNotEmpty &&
      requiredLabels.every(coordinates.containsKey)) {
    final List<double> distances = pairs
        .map((_BridgePair pair) {
          final ChannelCoordinate first = coordinates[pair.firstLabel]!;
          final ChannelCoordinate second = coordinates[pair.secondLabel]!;
          final double dx = first.x - second.x;
          final double dy = first.y - second.y;
          final double dz = first.z - second.z;
          return math.sqrt((dx * dx) + (dy * dy) + (dz * dz));
        })
        .toList(growable: false);
    final Set<String> units = coordinates.values
        .map((ChannelCoordinate coordinate) => coordinate.units)
        .where((String units) => units.isNotEmpty)
        .toSet();
    return _continuousColorEncoding(
      distances,
      label: 'Electrode distance',
      units: units.length == 1 ? units.single : '',
    );
  }

  return _continuousColorEncoding(
    pairs
        .map(
          (_BridgePair pair) =>
              ((pair.firstIndex + 1) + (pair.secondIndex + 1)) / 2,
        )
        .toList(growable: false),
    label: 'Mean channel number',
  );
}

_BridgeColorEncoding _continuousColorEncoding(
  List<double> values, {
  required String label,
  String units = '',
}) {
  if (values.isEmpty) {
    return _BridgeColorEncoding(
      colors: const <Color>[],
      label: label,
      minimum: 0,
      maximum: 0,
      units: units,
    );
  }
  final double minimum = values.reduce(math.min);
  final double maximum = values.reduce(math.max);
  final double span = maximum - minimum;
  return _BridgeColorEncoding(
    colors: values
        .map(
          (double value) =>
              _darkRainbowColor(span == 0 ? 0.5 : (value - minimum) / span),
        )
        .toList(growable: false),
    label: label,
    minimum: minimum,
    maximum: maximum,
    units: units,
  );
}

Color _darkRainbowColor(double position) {
  final double hue = (240 + (position.clamp(0, 1) * 300)) % 360;
  return HSVColor.fromAHSV(1, hue, 0.62, 0.72).toColor();
}

class _BridgeValueBounds {
  const _BridgeValueBounds({required this.center, required this.range});

  final double center;
  final double range;
}

_BridgeValueBounds _valueBounds(BridgeDetectionData bridge) {
  final Iterable<double> values = bridge.frames.expand(
    (BridgeEpochFrameData frame) => frame.pairValues,
  );
  double minValue = double.infinity;
  double maxValue = double.negativeInfinity;
  for (final double value in values) {
    if (!value.isFinite) continue;
    minValue = math.min(minValue, value);
    maxValue = math.max(maxValue, value);
  }
  if (!minValue.isFinite || !maxValue.isFinite) {
    return const _BridgeValueBounds(center: 0, range: 1);
  }
  return _BridgeValueBounds(
    center: (minValue + maxValue) / 2,
    range: math.max(0.1, maxValue - minValue),
  );
}

double _nearestOption(double value, List<double> options) {
  return options.reduce(
    (double first, double second) =>
        (first - value).abs() <= (second - value).abs() ? first : second,
  );
}

List<double> _timeOptionsForDuration(double durationSeconds) {
  final Set<double> values = <double>{durationSeconds};
  values.addAll(
    _BridgeViewerState._timeOptions.where(
      (double option) => option < durationSeconds,
    ),
  );
  final List<double> sorted = values.toList(growable: false)..sort();
  return sorted;
}

String _secondsLabel(double seconds) {
  final int decimals = seconds == seconds.roundToDouble() ? 0 : 1;
  return '${seconds.toStringAsFixed(decimals)} s';
}

class _BridgeScoreAxis extends StatelessWidget {
  const _BridgeScoreAxis({required this.center, required this.range});

  final double center;
  final double range;

  @override
  Widget build(BuildContext context) {
    final TextStyle valueStyle = Theme.of(
      context,
    ).textTheme.labelSmall!.copyWith(color: Colors.white60, fontSize: 10);
    return Semantics(
      label: 'Bridge score. Higher means more similar and more suspicious.',
      child: Container(
        key: const ValueKey<String>('bridge-score-axis'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Icon(Icons.arrow_upward, size: 11, color: Colors.white70),
                      Text(
                        'More\nsimilar',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(_scoreLabel(center + (range / 2)), style: valueStyle),
                  const Spacer(),
                  Text(_scoreLabel(center), style: valueStyle),
                  const Spacer(),
                  Text(_scoreLabel(center - (range / 2)), style: valueStyle),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Container(width: 1, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

class _BridgeColorLegend extends StatelessWidget {
  const _BridgeColorLegend({required this.encoding});

  final _BridgeColorEncoding encoding;

  @override
  Widget build(BuildContext context) {
    final String suffix = encoding.units.isEmpty ? '' : ' ${encoding.units}';
    return SizedBox(
      key: const ValueKey<String>('bridge-color-legend'),
      height: 30,
      child: Row(
        children: <Widget>[
          Text(
            encoding.label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(width: 10),
          Text(
            '${_legendLabel(encoding.minimum)}$suffix',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(width: 6),
          Container(
            width: 180,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: List<Color>.generate(
                  13,
                  (int index) => _darkRainbowColor(index / 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${_legendLabel(encoding.maximum)}$suffix',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

String _scoreLabel(double value) => value.toStringAsFixed(2);

String _legendLabel(double value) {
  if (value.abs() >= 100) return value.toStringAsFixed(0);
  if (value.abs() >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

class _BridgeTracePainter extends CustomPainter {
  const _BridgeTracePainter({
    required this.bridge,
    required this.colors,
    required this.pixelsPerSecond,
    required this.scoreRange,
    required this.scoreCenter,
    required this.hoveredPairIndex,
  });

  final BridgeDetectionData bridge;
  final List<Color> colors;
  final double pixelsPerSecond;
  final double scoreRange;
  final double scoreCenter;
  final int? hoveredPairIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect visible = canvas.getLocalClipBounds();
    final Paint grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final int pairCount = colors.length;
    final double plotCenter = size.height / 2;
    canvas.drawLine(
      Offset(visible.left, plotCenter),
      Offset(visible.right, plotCenter),
      grid,
    );
    final double firstVisibleSecond = math.max(
      0,
      visible.left / pixelsPerSecond,
    );
    final double lastVisibleSecond = visible.right / pixelsPerSecond;
    for (int pair = 0; pair < pairCount; pair++) {
      final Path path = Path();
      bool started = false;
      for (final BridgeEpochFrameData frame in bridge.frames) {
        if (pair >= frame.pairValues.length) continue;
        final double value = frame.pairValues[pair];
        if (!value.isFinite) continue;
        final double seconds =
            ((frame.startSample + frame.endSampleExclusive) / 2) /
            bridge.sampleRate;
        if (seconds < firstVisibleSecond - bridge.intervalSeconds ||
            seconds > lastVisibleSecond + bridge.intervalSeconds) {
          continue;
        }
        final double x = seconds * pixelsPerSecond;
        final double normalized = ((value - scoreCenter) / scoreRange).clamp(
          -0.5,
          0.5,
        );
        final double y = plotCenter - (normalized * size.height * 0.82);
        if (started) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          started = true;
        }
      }
      final Paint trace = Paint()
        ..color = colors[pair].withValues(
          alpha: hoveredPairIndex == null || hoveredPairIndex == pair
              ? 0.95
              : 0.32,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = hoveredPairIndex == pair ? 2.4 : 1.4
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, trace);
      for (final BridgeEpochFrameData frame in bridge.frames) {
        if (pair >= frame.pairValues.length) continue;
        final double value = frame.pairValues[pair];
        if (!value.isFinite) continue;
        final double seconds =
            ((frame.startSample + frame.endSampleExclusive) / 2) /
            bridge.sampleRate;
        if (seconds < firstVisibleSecond - bridge.intervalSeconds ||
            seconds > lastVisibleSecond + bridge.intervalSeconds) {
          continue;
        }
        final double normalized = ((value - scoreCenter) / scoreRange).clamp(
          -0.5,
          0.5,
        );
        canvas.drawCircle(
          Offset(
            seconds * pixelsPerSecond,
            plotCenter - (normalized * size.height * 0.82),
          ),
          hoveredPairIndex == pair ? 2.6 : 1.8,
          Paint()..color = trace.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BridgeTracePainter oldDelegate) {
    return oldDelegate.bridge != bridge ||
        oldDelegate.colors != colors ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.scoreRange != scoreRange ||
        oldDelegate.scoreCenter != scoreCenter ||
        oldDelegate.hoveredPairIndex != hoveredPairIndex;
  }
}

class _BridgeHoverCard extends StatelessWidget {
  const _BridgeHoverCard({
    required this.position,
    required this.pair,
    required this.frame,
    required this.score,
    required this.sampleRate,
  });

  final Offset position;
  final _BridgePair pair;
  final BridgeEpochFrameData frame;
  final double score;
  final double sampleRate;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx + 12,
      top: math.max(0, position.dy - 54),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xEE202027),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(
              '${pair.firstLabel} / ${pair.secondLabel}\n'
              '${(frame.startSample / sampleRate).toStringAsFixed(1)} s • ${score.toStringAsFixed(3)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }
}
