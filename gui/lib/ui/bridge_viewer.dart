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
    final String requestedViewMode =
        widget.params['bridgeViewer.mode']?.toString() ?? 'butterfly';
    final String viewMode =
        <String>{
          'butterfly',
          'scatter',
          'classification',
        }.contains(requestedViewMode)
        ? requestedViewMode
        : 'butterfly';
    final List<double?> pairDistances = _pairDistances(
      pairs,
      bridge.channelCoordinates,
      widget.dataset.timeSeries,
    );
    final List<double> pairOpacities = _pairOpacities(pairs, pairDistances);
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
        final double traceHeight = math.max(150, constraints.maxHeight - 166);

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
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'butterfly',
                      icon: Icon(Icons.show_chart),
                      label: Text('Butterfly'),
                    ),
                    ButtonSegment<String>(
                      value: 'scatter',
                      icon: Icon(Icons.scatter_plot),
                      label: Text('Distance'),
                    ),
                    ButtonSegment<String>(
                      value: 'classification',
                      icon: Icon(Icons.rule),
                      label: Text('Classification'),
                    ),
                  ],
                  selected: <String>{viewMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<String> selected) =>
                      _setStringParam('bridgeViewer.mode', selected.single),
                ),
                if (viewMode == 'butterfly')
                  const Text('Scale:', style: TextStyle(color: Colors.white70)),
                if (viewMode == 'butterfly')
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
                if (viewMode == 'butterfly')
                  ViewerScalePillMenu<double>(
                    label: 'Score',
                    currentValue: scoreRange,
                    valueText: scoreRange.toStringAsFixed(1),
                    tooltip: 'Score scale',
                    options: rangeOptions,
                    itemLabelBuilder: (double value) =>
                        value.toStringAsFixed(1),
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
            if (viewMode == 'scatter')
              Expanded(
                child: _BridgeScatterChart(
                  bridge: bridge,
                  pairs: pairs,
                  pairDistances: pairDistances,
                  colors: colors,
                  coordinateUnits: _cachedColorEncoding.units,
                ),
              )
            else if (viewMode == 'classification')
              Expanded(
                child: _BridgeClassificationView(bridge: bridge, pairs: pairs),
              )
            else
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
                                        pairOpacities: pairOpacities,
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
                                      electricalDistance:
                                          _hoveredPairIndex! <
                                              bridge
                                                  .frames[_hoveredEpochIndex!]
                                                  .pairElectricalDistances
                                                  .length
                                          ? bridge
                                                .frames[_hoveredEpochIndex!]
                                                .pairElectricalDistances[_hoveredPairIndex!]
                                          : null,
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
            if (viewMode == 'butterfly') const SizedBox(height: 6),
            if (viewMode == 'butterfly')
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
            if (viewMode == 'butterfly') const SizedBox(height: 6),
            if (viewMode == 'butterfly')
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

  void _setStringParam(String key, String value) {
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

List<double> _pairOpacities(
  List<_BridgePair> pairs,
  List<double?> pairDistances,
) {
  final List<double> finiteDistances = pairDistances
      .whereType<double>()
      .where((double value) => value.isFinite && value >= 0)
      .toList(growable: false);
  final double? minimumDistance = finiteDistances.isEmpty
      ? null
      : finiteDistances.reduce(math.min);
  final double? maximumDistance = finiteDistances.isEmpty
      ? null
      : finiteDistances.reduce(math.max);
  final int maximumSeparation = pairs.fold<int>(
    1,
    (int maximum, _BridgePair pair) =>
        math.max(maximum, (pair.secondIndex - pair.firstIndex).abs()),
  );
  return List<double>.generate(pairs.length, (int index) {
    final double? distance = index < pairDistances.length
        ? pairDistances[index]
        : null;
    final double proximity;
    if (distance != null &&
        distance.isFinite &&
        minimumDistance != null &&
        maximumDistance != null &&
        maximumDistance > minimumDistance) {
      proximity =
          1 -
          ((distance - minimumDistance) / (maximumDistance - minimumDistance))
              .clamp(0.0, 1.0);
    } else {
      final int separation =
          (pairs[index].secondIndex - pairs[index].firstIndex).abs();
      proximity = 1 - ((separation - 1) / maximumSeparation).clamp(0.0, 1.0);
    }
    return 0.16 + (0.46 * proximity);
  }, growable: false);
}

class _BridgeColorEncoding {
  const _BridgeColorEncoding({
    required this.colors,
    required this.label,
    required this.minimum,
    required this.maximum,
    this.units = '',
    this.channelNumberFallbackCount = 0,
  });

  const _BridgeColorEncoding.channelNumber()
    : colors = const <Color>[],
      label = 'Mean channel number',
      minimum = 1,
      maximum = 1,
      units = '',
      channelNumberFallbackCount = 0;

  final List<Color> colors;
  final String label;
  final double minimum;
  final double maximum;
  final String units;
  final int channelNumberFallbackCount;
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
  final List<double?> distances = pairs
      .map((_BridgePair pair) {
        final ChannelCoordinate? first = coordinates[pair.firstLabel];
        final ChannelCoordinate? second = coordinates[pair.secondLabel];
        if (first == null || second == null) return null;
        final double dx = first.x - second.x;
        final double dy = first.y - second.y;
        final double dz = first.z - second.z;
        return math.sqrt((dx * dx) + (dy * dy) + (dz * dz));
      })
      .toList(growable: false);
  final List<double> availableDistances = distances.whereType<double>().toList(
    growable: false,
  );
  if (availableDistances.isNotEmpty) {
    final Set<String> units = coordinates.values
        .map((ChannelCoordinate coordinate) => coordinate.units)
        .where((String units) => units.isNotEmpty)
        .toSet();
    final double minimum = availableDistances.reduce(math.min);
    final double maximum = availableDistances.reduce(math.max);
    final double span = maximum - minimum;
    final List<double> channelNumbers = pairs
        .map(
          (_BridgePair pair) =>
              ((pair.firstIndex + 1) + (pair.secondIndex + 1)) / 2,
        )
        .toList(growable: false);
    final double minimumChannel = channelNumbers.reduce(math.min);
    final double channelSpan = channelNumbers.reduce(math.max) - minimumChannel;
    return _BridgeColorEncoding(
      colors: List<Color>.generate(pairs.length, (int index) {
        final double? distance = distances[index];
        final double position = distance == null
            ? (channelSpan == 0
                  ? 0.5
                  : (channelNumbers[index] - minimumChannel) / channelSpan)
            : (span == 0 ? 0.5 : (distance - minimum) / span);
        return _darkRainbowColor(position);
      }, growable: false),
      label: 'Electrode distance',
      minimum: minimum,
      maximum: maximum,
      units: units.length == 1 ? units.single : '',
      channelNumberFallbackCount: distances
          .where((value) => value == null)
          .length,
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
      channelNumberFallbackCount: 0,
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
    channelNumberFallbackCount: 0,
  );
}

Color _darkRainbowColor(double position) {
  final double hue = position.clamp(0, 1) * 275;
  return HSVColor.fromAHSV(1, hue, 0.62, 0.72).toColor();
}

List<double?> _pairDistances(
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
  return pairs
      .map((_BridgePair pair) {
        final ChannelCoordinate? first = coordinates[pair.firstLabel];
        final ChannelCoordinate? second = coordinates[pair.secondLabel];
        if (first == null || second == null) return null;
        final double dx = first.x - second.x;
        final double dy = first.y - second.y;
        final double dz = first.z - second.z;
        return math.sqrt((dx * dx) + (dy * dy) + (dz * dz));
      })
      .toList(growable: false);
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

class _BridgeClassificationView extends StatelessWidget {
  const _BridgeClassificationView({required this.bridge, required this.pairs});

  final BridgeDetectionData bridge;
  final List<_BridgePair> pairs;

  @override
  Widget build(BuildContext context) {
    final List<int> flaggedPairIndices =
        <int>[
          for (int index = 0; index < bridge.bridgedPairs.length; index++)
            if (bridge.bridgedPairs[index] && index < pairs.length) index,
        ]..sort((int left, int right) {
          final double leftFraction =
              left < bridge.pairBelowCutoffFractions.length
              ? bridge.pairBelowCutoffFractions[left]
              : 0;
          final double rightFraction =
              right < bridge.pairBelowCutoffFractions.length
              ? bridge.pairBelowCutoffFractions[right]
              : 0;
          return rightFraction.compareTo(leftFraction);
        });
    final Set<String> flaggedChannels = <String>{
      for (final int index in flaggedPairIndices) pairs[index].firstLabel,
      for (final int index in flaggedPairIndices) pairs[index].secondLabel,
    };
    final bool hasDistribution =
        bridge.distributionElectricalDistances.length > 1 &&
        bridge.distributionElectricalDistances.length ==
            bridge.distributionCounts.length;

    final Widget distribution = ViewerTraceSurface(
      child: hasDistribution
          ? Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey<String>(
                      'bridge-classification-distribution',
                    ),
                    painter: _BridgeDistributionPainter(
                      electricalDistances:
                          bridge.distributionElectricalDistances,
                      counts: bridge.distributionCounts,
                      peak: bridge.distributionPeak,
                      cutoff: bridge.electricalDistanceCutoff,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 14,
                  child: _BridgeClassificationStatus(
                    cutoff: bridge.electricalDistanceCutoff,
                  ),
                ),
              ],
            )
          : const Center(
              child: Text(
                'Rerun Bridge Detector to calculate classification.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
    );
    final Widget findings = Container(
      key: const ValueKey<String>('bridge-classification-findings'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${flaggedPairIndices.length} flagged pair${flaggedPairIndices.length == 1 ? '' : 's'}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${flaggedChannels.length} implicated channel${flaggedChannels.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          if (flaggedChannels.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: flaggedChannels
                  .map(
                    (String label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF322A16),
                        border: Border.all(color: const Color(0xFFCE9D36)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFFFD77D),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          const Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Pair',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              Text(
                'Epochs below cutoff',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 12),
          Expanded(
            child: flaggedPairIndices.isEmpty
                ? Center(
                    child: Text(
                      bridge.electricalDistanceCutoff == null
                          ? 'No near-zero peak and cutoff were found.'
                          : 'No pair met the 50% criterion.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    itemCount: flaggedPairIndices.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (BuildContext context, int row) {
                      final int index = flaggedPairIndices[row];
                      final double fraction =
                          index < bridge.pairBelowCutoffFractions.length
                          ? bridge.pairBelowCutoffFractions[index]
                          : 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '${pairs[index].firstLabel} / ${pairs[index].secondLabel}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            Text(
                              '${(fraction * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Color(0xFFFFD77D),
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Screening result only. No channels are modified.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: distribution),
              const SizedBox(width: 10),
              SizedBox(width: 320, child: findings),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: distribution),
            const SizedBox(height: 10),
            SizedBox(height: 230, child: findings),
          ],
        );
      },
    );
  }
}

class _BridgeClassificationStatus extends StatelessWidget {
  const _BridgeClassificationStatus({required this.cutoff});

  final double? cutoff;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE6222228),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        cutoff == null
            ? 'No cutoff found'
            : 'Cutoff ${cutoff!.toStringAsFixed(2)}',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}

class _BridgeDistributionPainter extends CustomPainter {
  const _BridgeDistributionPainter({
    required this.electricalDistances,
    required this.counts,
    required this.peak,
    required this.cutoff,
  });

  final List<double> electricalDistances;
  final List<double> counts;
  final double? peak;
  final double? cutoff;

  @override
  void paint(Canvas canvas, Size size) {
    const double left = 62;
    const double top = 24;
    const double right = 18;
    const double bottom = 48;
    final Rect plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;
    final double maxX = math.max(10, electricalDistances.last);
    final double maxY = math.max(1, counts.reduce(math.max));
    final Paint grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (int tick = 0; tick <= 5; tick++) {
      final double fraction = tick / 5;
      final double x = plot.left + plot.width * fraction;
      final double y = plot.bottom - plot.height * fraction;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _paintBridgeChartText(
        canvas,
        (maxX * fraction).toStringAsFixed(0),
        Offset(x, plot.bottom + 7),
        centered: true,
      );
      _paintBridgeChartText(
        canvas,
        (maxY * fraction).toStringAsFixed(0),
        Offset(plot.left - 8, y - 6),
        rightAligned: true,
      );
    }
    final Path curve = Path();
    for (int index = 0; index < electricalDistances.length; index++) {
      final double x =
          plot.left + electricalDistances[index] / maxX * plot.width;
      final double y = plot.bottom - counts[index] / maxY * plot.height;
      if (index == 0) {
        curve.moveTo(x, y);
      } else {
        curve.lineTo(x, y);
      }
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = const Color(0xFF64C7C1)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    void marker(double value, Color color, String label) {
      final double x = plot.left + value / maxX * plot.width;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = color
          ..strokeWidth = 1.5,
      );
      _paintBridgeChartText(
        canvas,
        '$label ${value.toStringAsFixed(2)}',
        Offset(x + 5, plot.top + (label == 'Peak' ? 6 : 22)),
        color: color,
      );
    }

    if (peak != null) marker(peak!, const Color(0xFF9CCBFF), 'Peak');
    if (cutoff != null) marker(cutoff!, const Color(0xFFFFD166), 'Cutoff');
    _paintBridgeChartText(
      canvas,
      'Scaled electrical distance',
      Offset(plot.center.dx, size.height - 17),
      centered: true,
      color: Colors.white70,
    );
    canvas.save();
    canvas.translate(16, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _paintBridgeChartText(
      canvas,
      'Epoch-pair count',
      Offset.zero,
      centered: true,
      color: Colors.white70,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BridgeDistributionPainter oldDelegate) {
    return oldDelegate.electricalDistances != electricalDistances ||
        oldDelegate.counts != counts ||
        oldDelegate.peak != peak ||
        oldDelegate.cutoff != cutoff;
  }
}

void _paintBridgeChartText(
  Canvas canvas,
  String text,
  Offset anchor, {
  bool centered = false,
  bool rightAligned = false,
  Color color = Colors.white54,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: 10),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final double dx = centered
      ? anchor.dx - painter.width / 2
      : rightAligned
      ? anchor.dx - painter.width
      : anchor.dx;
  painter.paint(canvas, Offset(dx, anchor.dy));
}

class _BridgeScatterChart extends StatefulWidget {
  const _BridgeScatterChart({
    required this.bridge,
    required this.pairs,
    required this.pairDistances,
    required this.colors,
    required this.coordinateUnits,
  });

  final BridgeDetectionData bridge;
  final List<_BridgePair> pairs;
  final List<double?> pairDistances;
  final List<Color> colors;
  final String coordinateUnits;

  @override
  State<_BridgeScatterChart> createState() => _BridgeScatterChartState();
}

class _BridgeScatterChartState extends State<_BridgeScatterChart> {
  bool _regressionHovered = false;

  @override
  Widget build(BuildContext context) {
    final List<_BridgeScatterPoint> points = <_BridgeScatterPoint>[];
    for (int pairIndex = 0; pairIndex < widget.pairs.length; pairIndex++) {
      final double? distance = pairIndex < widget.pairDistances.length
          ? widget.pairDistances[pairIndex]
          : null;
      if (distance == null || !distance.isFinite || distance <= 0) continue;
      final List<double> scores = <double>[];
      for (final BridgeEpochFrameData frame in widget.bridge.frames) {
        if (pairIndex >= frame.pairValues.length) continue;
        final double score;
        if (pairIndex < frame.pairElectricalDistances.length) {
          score = -math.log(
            math.max(1.0e-300, frame.pairElectricalDistances[pairIndex]),
          );
        } else {
          double legacyScore = frame.pairValues[pairIndex];
          if (pairIndex < widget.bridge.distanceNormalizedPairs.length &&
              widget.bridge.distanceNormalizedPairs[pairIndex]) {
            legacyScore -= math.log(distance);
          }
          score = legacyScore;
        }
        if (!score.isFinite) continue;
        scores.add(score);
      }
      if (scores.isNotEmpty) {
        final double mean =
            scores.reduce((double a, double b) => a + b) / scores.length;
        final double variance = scores.length < 2
            ? 0
            : scores.fold<double>(
                    0,
                    (double sum, double value) =>
                        sum + math.pow(value - mean, 2).toDouble(),
                  ) /
                  (scores.length - 1);
        points.add(
          _BridgeScatterPoint(
            distance: distance,
            score: mean,
            scoreStandardDeviation: math.sqrt(variance),
            color: widget.colors[pairIndex],
          ),
        );
      }
    }
    if (points.isEmpty) {
      return const ViewerTraceSurface(
        child: Center(
          child: Text(
            'Scatter view requires coordinates for at least two channels.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final _BridgeRegression? regression = _bridgeRegression(points);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final Offset? labelCenter = regression == null
            ? null
            : _regressionLineMidpoint(size, points, regression);
        return ViewerTraceSurface(
          child: MouseRegion(
            key: const ValueKey<String>('bridge-distance-region'),
            onHover: (PointerHoverEvent event) {
              final bool hovered =
                  regression != null &&
                  _isNearRegressionLine(
                    event.localPosition,
                    size,
                    points,
                    regression,
                  );
              if (hovered != _regressionHovered) {
                setState(() => _regressionHovered = hovered);
              }
            },
            onExit: (_) {
              if (_regressionHovered) {
                setState(() => _regressionHovered = false);
              }
            },
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey<String>('bridge-distance-scatter'),
                    painter: _BridgeScatterPainter(
                      points: points,
                      coordinateUnits: widget.coordinateUnits,
                      regression: regression,
                    ),
                  ),
                ),
                if (_regressionHovered &&
                    regression != null &&
                    labelCenter != null)
                  Positioned(
                    left: labelCenter.dx - 33,
                    top: labelCenter.dy - 13,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey<String>('bridge-regression-label'),
                        width: 66,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xE6222228),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Text(
                          'r = ${regression.pearsonR.toStringAsFixed(3)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BridgeScatterPoint {
  const _BridgeScatterPoint({
    required this.distance,
    required this.score,
    required this.scoreStandardDeviation,
    required this.color,
  });

  final double distance;
  final double score;
  final double scoreStandardDeviation;
  final Color color;
}

class _BridgeRegression {
  const _BridgeRegression({
    required this.slope,
    required this.intercept,
    required this.pearsonR,
  });

  final double slope;
  final double intercept;
  final double pearsonR;
}

_BridgeRegression? _bridgeRegression(List<_BridgeScatterPoint> points) {
  if (points.length < 2) return null;
  final double meanX =
      points.fold<double>(0, (double sum, point) => sum + point.distance) /
      points.length;
  final double meanY =
      points.fold<double>(0, (double sum, point) => sum + point.score) /
      points.length;
  double covariance = 0;
  double xVariance = 0;
  double yVariance = 0;
  for (final _BridgeScatterPoint point in points) {
    final double centeredX = point.distance - meanX;
    final double centeredY = point.score - meanY;
    covariance += centeredX * centeredY;
    xVariance += centeredX * centeredX;
    yVariance += centeredY * centeredY;
  }
  if (xVariance <= 0 || yVariance <= 0) return null;
  return _BridgeRegression(
    slope: covariance / xVariance,
    intercept: meanY - ((covariance / xVariance) * meanX),
    pearsonR: covariance / math.sqrt(xVariance * yVariance),
  );
}

Rect _bridgeScatterPlot(Size size) =>
    Rect.fromLTRB(76, 18, size.width - 18, size.height - 48);

(double, double, double, double) _bridgeScatterBounds(
  List<_BridgeScatterPoint> points,
) {
  final double minX = points.map((point) => point.distance).reduce(math.min);
  final double maxX = points.map((point) => point.distance).reduce(math.max);
  final double minY = points
      .map((point) => point.score - (2 * point.scoreStandardDeviation))
      .reduce(math.min);
  final double maxY = points
      .map((point) => point.score + (2 * point.scoreStandardDeviation))
      .reduce(math.max);
  return (minX, maxX, minY, maxY);
}

(Offset, Offset)? _regressionLineSegment(
  Size size,
  List<_BridgeScatterPoint> points,
  _BridgeRegression regression,
) {
  final Rect plot = _bridgeScatterPlot(size);
  if (plot.width <= 0 || plot.height <= 0 || points.isEmpty) return null;
  final (double minX, double maxX, double minY, double maxY) =
      _bridgeScatterBounds(points);
  final double ySpan = math.max(0.1, maxY - minY);
  double mapY(double score) =>
      plot.bottom - (((score - minY) / ySpan) * plot.height);
  return (
    Offset(plot.left, mapY((regression.slope * minX) + regression.intercept)),
    Offset(plot.right, mapY((regression.slope * maxX) + regression.intercept)),
  );
}

Offset _regressionLineMidpoint(
  Size size,
  List<_BridgeScatterPoint> points,
  _BridgeRegression regression,
) {
  final (Offset start, Offset end) = _regressionLineSegment(
    size,
    points,
    regression,
  )!;
  return Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
}

bool _isNearRegressionLine(
  Offset pointer,
  Size size,
  List<_BridgeScatterPoint> points,
  _BridgeRegression regression,
) {
  final (Offset start, Offset end) = _regressionLineSegment(
    size,
    points,
    regression,
  )!;
  final Offset segment = end - start;
  final double lengthSquared =
      segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared <= 0) return false;
  final Offset relative = pointer - start;
  final double fraction =
      ((relative.dx * segment.dx + relative.dy * segment.dy) / lengthSquared)
          .clamp(0.0, 1.0);
  final Offset nearest = start + segment * fraction;
  return (pointer - nearest).distance <= 8;
}

class _BridgeScatterPainter extends CustomPainter {
  const _BridgeScatterPainter({
    required this.points,
    required this.coordinateUnits,
    required this.regression,
  });

  final List<_BridgeScatterPoint> points;
  final String coordinateUnits;
  final _BridgeRegression? regression;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = _bridgeScatterPlot(size);
    if (plot.width <= 0 || plot.height <= 0) return;
    final (double minX, double maxX, double minY, double maxY) =
        _bridgeScatterBounds(points);
    final double xSpan = math.max(1.0e-12, maxX - minX);
    final double ySpan = math.max(0.1, maxY - minY);
    final Paint grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = 1;
    for (int tick = 0; tick <= 4; tick++) {
      final double fraction = tick / 4;
      final double x = plot.left + (plot.width * fraction);
      final double y = plot.bottom - (plot.height * fraction);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _paintText(
        canvas,
        _legendLabel(minX + (xSpan * fraction)),
        Offset(x, plot.bottom + 7),
        centered: true,
      );
      _paintText(
        canvas,
        _scoreLabel(minY + (ySpan * fraction)),
        Offset(plot.left - 8, y - 6),
        rightAligned: true,
      );
    }
    for (final _BridgeScatterPoint point in points) {
      final double x =
          plot.left + (((point.distance - minX) / xSpan) * plot.width);
      final double y =
          plot.bottom - (((point.score - minY) / ySpan) * plot.height);
      final double twoSdPixels = math.max(
        4,
        (2 * point.scoreStandardDeviation / ySpan) * plot.height,
      );
      const double glowHalfWidth = 9;
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(1, twoSdPixels / glowHalfWidth);
      canvas.drawCircle(
        Offset.zero,
        glowHalfWidth,
        Paint()
          ..shader =
              RadialGradient(
                colors: <Color>[
                  point.color.withValues(alpha: 0.30),
                  point.color.withValues(alpha: 0.12),
                  point.color.withValues(alpha: 0),
                ],
                stops: const <double>[0, 0.5, 1],
              ).createShader(
                Rect.fromCircle(center: Offset.zero, radius: glowHalfWidth),
              ),
      );
      canvas.restore();
      canvas.drawCircle(
        Offset(x, y),
        3.1,
        Paint()..color = point.color.withValues(alpha: 0.92),
      );
    }
    if (regression != null) {
      final Paint line = Paint()
        ..color = Colors.white.withValues(alpha: 0.84)
        ..strokeWidth = 1.8;
      final (Offset start, Offset end) = _regressionLineSegment(
        size,
        points,
        regression!,
      )!;
      canvas.save();
      canvas.clipRect(plot);
      canvas.drawLine(start, end, line);
      canvas.restore();
    }
    _paintText(
      canvas,
      coordinateUnits.isEmpty
          ? 'Euclidean distance'
          : 'Euclidean distance ($coordinateUnits)',
      Offset(plot.center.dx, size.height - 17),
      centered: true,
      color: Colors.white70,
    );
    canvas.save();
    canvas.translate(17, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _paintText(
      canvas,
      '-ln(ED)',
      Offset.zero,
      centered: true,
      color: Colors.white70,
    );
    canvas.restore();
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool centered = false,
    bool rightAligned = false,
    Color color = Colors.white54,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double dx = centered
        ? anchor.dx - (painter.width / 2)
        : rightAligned
        ? anchor.dx - painter.width
        : anchor.dx;
    painter.paint(canvas, Offset(dx, anchor.dy));
  }

  @override
  bool shouldRepaint(covariant _BridgeScatterPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.coordinateUnits != coordinateUnits ||
        oldDelegate.regression != regression;
  }
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
      height: 42,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
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
          if (encoding.channelNumberFallbackCount > 0) ...<Widget>[
            const SizedBox(width: 10),
            Text(
              '${encoding.channelNumberFallbackCount} pair(s) use channel number',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
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
    required this.pairOpacities,
  });

  final BridgeDetectionData bridge;
  final List<Color> colors;
  final double pixelsPerSecond;
  final double scoreRange;
  final double scoreCenter;
  final int? hoveredPairIndex;
  final List<double> pairOpacities;

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
    final List<int> paintOrder = List<int>.generate(pairCount, (int i) => i)
      ..sort((int left, int right) {
        if (left == hoveredPairIndex) return 1;
        if (right == hoveredPairIndex) return -1;
        final double leftOpacity = left < pairOpacities.length
            ? pairOpacities[left]
            : 0.3;
        final double rightOpacity = right < pairOpacities.length
            ? pairOpacities[right]
            : 0.3;
        return leftOpacity.compareTo(rightOpacity);
      });
    for (final int pair in paintOrder) {
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
          alpha: hoveredPairIndex == pair
              ? 0.95
              : (pair < pairOpacities.length ? pairOpacities[pair] : 0.3) *
                    (hoveredPairIndex == null ? 1 : 0.42),
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
        oldDelegate.hoveredPairIndex != hoveredPairIndex ||
        oldDelegate.pairOpacities != pairOpacities;
  }
}

class _BridgeHoverCard extends StatelessWidget {
  const _BridgeHoverCard({
    required this.position,
    required this.pair,
    required this.frame,
    required this.score,
    required this.electricalDistance,
    required this.sampleRate,
  });

  final Offset position;
  final _BridgePair pair;
  final BridgeEpochFrameData frame;
  final double score;
  final double? electricalDistance;
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
              '${(frame.startSample / sampleRate).toStringAsFixed(1)} s • ${score.toStringAsFixed(3)}'
              '${electricalDistance == null ? '' : '\nED ${electricalDistance!.toStringAsPrecision(4)}'}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }
}
