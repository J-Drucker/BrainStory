import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/interactive_artifact_detection_node.dart';

class RawSignalBrowser extends StatefulWidget {
  const RawSignalBrowser({
    super.key,
    required this.dataset,
    required this.params,
    this.onChanged,
    this.onMarkersChanged,
    this.onInteractiveArtifactDetectionSaved,
    this.onSaveAndQuit,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback? onChanged;
  final ValueChanged<List<dynamic>>? onMarkersChanged;
  final VoidCallback? onInteractiveArtifactDetectionSaved;
  final VoidCallback? onSaveAndQuit;

  @override
  State<RawSignalBrowser> createState() => _RawSignalBrowserState();
}

class _RawSignalBrowserState extends State<RawSignalBrowser> {
  static const List<Color> _palette = <Color>[
    Color(0xFF7FDBFF),
    Color(0xFF39CCCC),
    Color(0xFF00B5D8),
    Color(0xFF3A86FF),
    Color(0xFF4CC9F0),
    Color(0xFF6C63FF),
    Color(0xFF7B6DFF),
    Color(0xFF8E7CFF),
    Color(0xFF5E60CE),
    Color(0xFF4EA8DE),
    Color(0xFF48CAE4),
    Color(0xFF2EC4B6),
    Color(0xFF00F5D4),
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
  Object? _markerCacheKey;
  List<TimeMarker>? _cachedMarkers;
  Object? _colorCacheKey;
  List<Color>? _cachedChannelColors;
  List<Map<String, dynamic>>? _draftArtifactExemplars;
  List<Map<String, dynamic>>? _draftArtifactCandidates;
  List<Map<String, dynamic>>? _draftArtifactTemplates;
  Offset? _dragSelectionStart;
  Offset? _dragSelectionCurrent;
  Offset? _dragSelectionGlobal;
  String? _lastFocusedReferenceId;

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
    final List<Color> channelColors = _channelColors(channels.length);
    final int channelCount = channels.length;
    final double durationSeconds = timeSeries.sampleCount / timeSeries.sampleRate;
    final int visibleChannels = _visibleChannelCount(channelCount);
    final bool markersOnly = _rawViewMode() == 'markers_only';
    final bool interactiveArtifactDetection = _interactiveArtifactDetectionEnabled();
    final List<TimeMarker> markers = interactiveArtifactDetection
        ? _interactiveDisplayMarkers(timeSeries)
        : _currentMarkersForDataset();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildControlBar(
          sampleRate: timeSeries.sampleRate,
          channelCount: channelCount,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double sidePanelWidth = math.min(
                320,
                math.max(240, constraints.maxWidth * 0.28),
              );
              final double leftPaneWidth =
                  math.max(260, constraints.maxWidth - sidePanelWidth - 12);
              final double labelWidth =
                  markersOnly ? 0 : (leftPaneWidth < 860 ? 112 : 160);
              final double traceWidth = math.max(
                180,
                leftPaneWidth - labelWidth - (markersOnly ? 0 : 8),
              );
              final double secondsPerView =
                  (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
              final double pixelsPerSecond = traceWidth / secondsPerView;
              final double totalWidth =
                  math.max(traceWidth, durationSeconds * pixelsPerSecond);
              const double axisHeight = 26;
              const double timelineHeight = 28;
              const double bottomChromeHeight = axisHeight + timelineHeight + 12;
              final double traceAreaHeight =
                  math.max(140, constraints.maxHeight - bottomChromeHeight);
              final double totalHeight = markersOnly
                  ? traceAreaHeight
                  : math.max(
                      traceAreaHeight,
                      _channelHeight(traceAreaHeight, visibleChannels) * channelCount,
                    );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Scrollbar(
                                controller: _verticalController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _verticalController,
                                  scrollDirection: Axis.vertical,
                                  child: SizedBox(
                                    width: leftPaneWidth,
                                    height: totalHeight,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        if (!markersOnly)
                                          SizedBox(
                                            width: labelWidth,
                                            child: _ChannelLabelColumn(
                                              labels: labels,
                                              colors: channelColors,
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
                                                onTapDown: interactiveArtifactDetection
                                                    ? null
                                                    : (TapDownDetails details) {
                                                        _handleMarkerTap(
                                                          details.localPosition,
                                                          pixelsPerSecond,
                                                        );
                                                      },
                                                onPanStart: interactiveArtifactDetection
                                                    ? (DragStartDetails details) {
                                                        _handleArtifactDragStart(
                                                          details.localPosition,
                                                          details.globalPosition,
                                                        );
                                                      }
                                                    : null,
                                                onPanUpdate: interactiveArtifactDetection
                                                    ? (DragUpdateDetails details) {
                                                        _handleArtifactDragUpdate(
                                                          details.localPosition,
                                                          details.globalPosition,
                                                        );
                                                      }
                                                    : null,
                                                onPanEnd: interactiveArtifactDetection
                                                    ? (DragEndDetails details) {
                                                        _handleArtifactDragEnd(
                                                          pixelsPerSecond,
                                                        );
                                                      }
                                                    : null,
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
                                                            colors: channelColors,
                                                            markers: markers,
                                                            selectionStartX: _dragSelectionStart?.dx,
                                                            selectionEndX: _dragSelectionCurrent?.dx,
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
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: markersOnly ? 0 : labelWidth + 8),
                            child: SizedBox(
                              width: traceWidth,
                              child: _TimeAxisBar(
                                controller: _horizontalController,
                                pixelsPerSecond: pixelsPerSecond,
                                viewportWidth: traceWidth,
                                durationSeconds: durationSeconds,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: markersOnly ? 0 : labelWidth + 8),
                            child: SizedBox(
                              width: traceWidth,
                              child: _TimelineBar(
                                controller: _horizontalController,
                                totalWidth: totalWidth,
                                viewportWidth: traceWidth,
                                durationSeconds: durationSeconds,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: sidePanelWidth,
                    child: _buildInfoPanel(
                      interactiveArtifactDetection: interactiveArtifactDetection,
                      markers: markers,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControlBar({
    required double sampleRate,
    required int channelCount,
  }) {
    final bool interactiveArtifactDetection = _interactiveArtifactDetectionEnabled();
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
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '${widget.dataset.label}  •  $channelCount ch  •  ${sampleRate.toStringAsFixed(1)} Hz',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            if (interactiveArtifactDetection)
              const Text(
                'Drag to label blink • Alt+drag for other artifacts',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          if (!interactiveArtifactDetection) ...<Widget>[
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
          ],
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

  Widget _buildInfoPanel({
    required bool interactiveArtifactDetection,
    required List<TimeMarker> markers,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_hasAnyDraftChanges) ...<Widget>[
              _buildDraftActions(interactiveArtifactDetection),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (interactiveArtifactDetection) ...<Widget>[
                      _InteractiveArtifactReviewSection(
                        labelChoices:
                            InteractiveArtifactDetectionNodeType.supportedLabels,
                        exemplarsExpanded:
                            (widget.params['artifact_exemplars_expanded'] as bool?) ?? true,
                        candidatesExpanded:
                            (widget.params['artifact_candidates_expanded'] as bool?) ?? true,
                        templates: _artifactTemplateSummaries(),
                        exemplars: _artifactExemplars(),
                        pendingCandidates: _artifactCandidates(
                          statuses: const <String>{
                            InteractiveArtifactDetectionNodeType.pendingStatus,
                          },
                        ),
                        acceptedCandidates: _artifactCandidates(
                          statuses: const <String>{
                            InteractiveArtifactDetectionNodeType.acceptedStatus,
                          },
                        ),
                        onDeleteExemplar: _deleteInteractiveArtifactExemplar,
                        onAcceptCandidate: _acceptInteractiveArtifactCandidate,
                        onRejectCandidate: _rejectInteractiveArtifactCandidate,
                        onUndoAccepted: _undoAcceptedInteractiveArtifactCandidate,
                        onAcceptAll: _acceptAllInteractiveArtifactCandidates,
                        onFocusExemplar: (ArtifactExemplarData exemplar) {
                          _jumpToTimeRange(
                            referenceId: 'exemplar:${exemplar.id}',
                            onsetMicros: exemplar.onsetMicros,
                            durationMicros: exemplar.durationMicros,
                          );
                        },
                        onFocusPendingCandidate: (ArtifactCandidateData candidate) {
                          _jumpToTimeRange(
                            referenceId: 'pending:${candidate.id}',
                            onsetMicros: candidate.onsetMicros,
                            durationMicros: candidate.durationMicros,
                          );
                        },
                        onFocusAcceptedCandidate: (ArtifactCandidateData candidate) {
                          _jumpToTimeRange(
                            referenceId: 'accepted:${candidate.id}',
                            onsetMicros: candidate.onsetMicros,
                            durationMicros: candidate.durationMicros,
                          );
                        },
                        onToggleExemplars: (bool expanded) =>
                            _updateParam('artifact_exemplars_expanded', expanded),
                        onToggleCandidates: (bool expanded) =>
                            _updateParam('artifact_candidates_expanded', expanded),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _MarkerSection(
                      expanded:
                          (widget.params['marker_list_expanded'] as bool?) ?? false,
                      markers: markers,
                      onToggle: (bool expanded) =>
                          _updateParam('marker_list_expanded', expanded),
                      onDelete: _deleteMarker,
                      onFocus: (TimeMarker marker) {
                        _jumpToTimeRange(
                          referenceId:
                              'marker:${marker.label}:${marker.onsetMicros}:${marker.durationMicros}',
                          onsetMicros: marker.onsetMicros,
                          durationMicros: marker.durationMicros,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftActions(bool interactiveArtifactDetection) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton(
          onPressed: _discardDraftChanges,
          child: const Text('Discard'),
        ),
        ElevatedButton(
          onPressed: _saveDraftChanges,
          child: Text(
            interactiveArtifactDetection ? 'Save' : 'Save Markers',
          ),
        ),
        FilledButton.tonal(
          onPressed: _saveDraftChangesAndQuit,
          child: const Text('Save and Quit'),
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
      if (key == 'channel_colors') {
        _colorCacheKey = null;
      }
    });
  }

  void _handleMarkerTap(Offset localPosition, double pixelsPerSecond) {
    final String markerMode = (widget.params['marker_mode'] ?? 'off').toString();
    if (markerMode == 'off') {
      return;
    }

    final List<TimeMarker> currentMarkers = _currentMarkersForDataset();
    final TimeMarker marker = TimeMarker(
      onsetMicros: ((localPosition.dx / pixelsPerSecond) * 1000000.0).round(),
      durationMicros: 0,
      label: markerMode == 'artifact'
          ? 'Artifact ${currentMarkers.length + 1}'
          : 'Marker ${currentMarkers.length + 1}',
      markerType: markerMode,
    );

    _setDraftMarkersForDataset(<TimeMarker>[
      ...currentMarkers,
      marker,
    ]);
  }

  void _handleArtifactDragStart(Offset localPosition, Offset globalPosition) {
    setState(() {
      _dragSelectionStart = localPosition;
      _dragSelectionCurrent = localPosition;
      _dragSelectionGlobal = globalPosition;
    });
  }

  void _handleArtifactDragUpdate(Offset localPosition, Offset globalPosition) {
    if (_dragSelectionStart == null) {
      return;
    }
    setState(() {
      _dragSelectionCurrent = localPosition;
      _dragSelectionGlobal = globalPosition;
    });
  }

  Future<void> _handleArtifactDragEnd(double pixelsPerSecond) async {
    final Offset? start = _dragSelectionStart;
    final Offset? end = _dragSelectionCurrent;
    final Offset? global = _dragSelectionGlobal;
    setState(() {
      _dragSelectionStart = null;
      _dragSelectionCurrent = null;
      _dragSelectionGlobal = null;
    });
    if (start == null || end == null) {
      return;
    }
    final double dragWidth = (end.dx - start.dx).abs();
    if (dragWidth < 6) {
      return;
    }

    String label = 'blink';
    if (HardwareKeyboard.instance.isAltPressed && global != null && mounted) {
      final String? chosenLabel = await _promptInteractiveArtifactLabel(global);
      if (chosenLabel == null) {
        return;
      }
      label = chosenLabel;
    }
    _addInteractiveArtifactExemplar(
      onsetMicros: ((math.min(start.dx, end.dx) / pixelsPerSecond) * 1000000.0).round(),
      durationMicros: ((dragWidth / pixelsPerSecond) * 1000000.0).round(),
      label: label,
    );
  }

  void _deleteMarker(TimeMarker marker) {
    _setDraftMarkersForDataset(
      _currentMarkersForDataset()
          .where((TimeMarker existing) => existing != marker)
          .toList(growable: false),
    );
  }

  Future<String?> _promptInteractiveArtifactLabel(Offset globalPosition) async {
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: InteractiveArtifactDetectionNodeType.supportedLabels
          .map(
            (String label) => PopupMenuItem<String>(
              value: label,
              child: Text(label),
            ),
          )
          .toList(growable: false),
    );
  }

  List<TimeMarker> _currentMarkersForDataset() {
    final Object cacheKey = Object.hash(
      widget.dataset.id,
      widget.dataset.timeSeries?.markers,
      _draftMarkers,
      widget.params['markers'],
    );
    if (_markerCacheKey == cacheKey && _cachedMarkers != null) {
      return _cachedMarkers!;
    }
    final List<dynamic> rawMarkers = _effectiveRawMarkers;
    final List<TimeMarker> editedMarkers = rawMarkers
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> marker) => marker['datasetId'] == widget.dataset.id)
        .map((Map<String, dynamic> marker) {
          final Map<String, dynamic> payload = Map<String, dynamic>.from(marker);
          payload.remove('datasetId');
          return TimeMarker.fromJson(payload);
        })
        .toList(growable: false);
    if (editedMarkers.isNotEmpty) {
      _markerCacheKey = cacheKey;
      _cachedMarkers = editedMarkers;
      return editedMarkers;
    }
    _markerCacheKey = cacheKey;
    _cachedMarkers = widget.dataset.timeSeries?.markers ?? const <TimeMarker>[];
    return _cachedMarkers!;
  }

  List<TimeMarker> _interactiveDisplayMarkers(TimeSeriesData timeSeries) {
    return InteractiveArtifactDetectionNodeType.displayMarkersForDataset(
      widget.dataset.id,
      _effectiveInteractiveArtifactParams,
      baseMarkers: timeSeries.markers,
    );
  }

  List<dynamic> get _effectiveRawMarkers =>
      _draftMarkers ?? (widget.params['markers'] as List<dynamic>? ?? <dynamic>[]);

  bool get _hasMarkerDraft => _draftMarkers != null;

  bool get _hasInteractiveArtifactDraft =>
      _draftArtifactExemplars != null ||
      _draftArtifactCandidates != null ||
      _draftArtifactTemplates != null;

  bool get _hasAnyDraftChanges => _hasMarkerDraft || _hasInteractiveArtifactDraft;

  bool _interactiveArtifactDetectionEnabled() =>
      widget.params['interactiveArtifactDetection'] == true;

  Map<String, dynamic> get _effectiveInteractiveArtifactParams =>
      <String, dynamic>{
        ...widget.params,
        if (_draftArtifactExemplars != null)
          'artifactExemplars': _draftArtifactExemplars,
        if (_draftArtifactCandidates != null)
          'artifactCandidates': _draftArtifactCandidates,
        if (_draftArtifactTemplates != null)
          'artifactTemplates': _draftArtifactTemplates,
      };

  List<ArtifactExemplarData> _artifactExemplars() {
    return InteractiveArtifactDetectionNodeType.exemplarsForDataset(
      widget.dataset.id,
      _effectiveInteractiveArtifactParams,
    );
  }

  List<ArtifactCandidateData> _artifactCandidates({
    Set<String>? statuses,
  }) {
    return InteractiveArtifactDetectionNodeType.candidatesForDataset(
      widget.dataset.id,
      _effectiveInteractiveArtifactParams,
      statuses: statuses,
    );
  }

  List<ArtifactTemplateSummary> _artifactTemplateSummaries() {
    return InteractiveArtifactDetectionNodeType.templateSummariesForDataset(
      widget.dataset.id,
      _effectiveInteractiveArtifactParams,
    );
  }

  void _setInteractiveArtifactDraftState({
    required List<ArtifactExemplarData> currentDatasetExemplars,
    required List<ArtifactCandidateData> currentDatasetCandidates,
    required List<ArtifactTemplateSummary> currentDatasetTemplates,
  }) {
    final List<Map<String, dynamic>> preservedExemplars =
        (widget.params['artifactExemplars'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where((Map<String, dynamic> item) => item['datasetId'] != widget.dataset.id)
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: true);
    final List<Map<String, dynamic>> preservedCandidates =
        (widget.params['artifactCandidates'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where((Map<String, dynamic> item) => item['datasetId'] != widget.dataset.id)
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: true);
    final List<Map<String, dynamic>> preservedTemplates =
        (widget.params['artifactTemplates'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where((Map<String, dynamic> item) => item['datasetId'] != widget.dataset.id)
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: true);

    preservedExemplars.addAll(
      currentDatasetExemplars.map((ArtifactExemplarData item) => item.toJson()),
    );
    preservedCandidates.addAll(
      currentDatasetCandidates.map((ArtifactCandidateData item) => item.toJson()),
    );
    preservedTemplates.addAll(
      currentDatasetTemplates.map((ArtifactTemplateSummary item) => item.toJson()),
    );

    setState(() {
      _draftArtifactExemplars = preservedExemplars;
      _draftArtifactCandidates = preservedCandidates;
      _draftArtifactTemplates = preservedTemplates;
      _markerCacheKey = null;
    });
  }

  void _recomputeInteractiveArtifactDraft({
    required List<ArtifactExemplarData> exemplars,
    List<ArtifactCandidateData>? currentCandidates,
  }) {
    final TimeSeriesData? timeSeries = widget.dataset.timeSeries;
    if (timeSeries == null) {
      return;
    }
    final ArtifactDetectionComputation computation =
        InteractiveArtifactDetectionNodeType.recomputeDetectionsForDataset(
      datasetId: widget.dataset.id,
      timeSeries: timeSeries,
      exemplars: exemplars,
      existingCandidates: currentCandidates ?? _artifactCandidates(),
      threshold:
          (widget.params['artifactThreshold'] as num?)?.toDouble() ?? 0.78,
    );
    _setInteractiveArtifactDraftState(
      currentDatasetExemplars: exemplars,
      currentDatasetCandidates: computation.candidates,
      currentDatasetTemplates: computation.templates,
    );
  }

  void _addInteractiveArtifactExemplar({
    required int onsetMicros,
    required int durationMicros,
    required String label,
  }) {
    final List<ArtifactExemplarData> exemplars = <ArtifactExemplarData>[
      ..._artifactExemplars(),
      ArtifactExemplarData(
        id: '${widget.dataset.id}:${DateTime.now().microsecondsSinceEpoch}',
        datasetId: widget.dataset.id,
        label: label,
        onsetMicros: onsetMicros,
        durationMicros: math.max(1000, durationMicros),
      ),
    ];
    _recomputeInteractiveArtifactDraft(exemplars: exemplars);
  }

  void _deleteInteractiveArtifactExemplar(ArtifactExemplarData exemplar) {
    final List<ArtifactExemplarData> exemplars = _artifactExemplars()
        .where((ArtifactExemplarData item) => item.id != exemplar.id)
        .toList(growable: false);
    _recomputeInteractiveArtifactDraft(exemplars: exemplars);
  }

  void _updateInteractiveArtifactCandidateStatus(
    ArtifactCandidateData candidate,
    String status,
  ) {
    final List<ArtifactCandidateData> candidates = _artifactCandidates()
        .map(
          (ArtifactCandidateData item) => item.id == candidate.id
              ? item.copyWith(status: status)
              : item,
        )
        .toList(growable: false);
    _setInteractiveArtifactDraftState(
      currentDatasetExemplars: _artifactExemplars(),
      currentDatasetCandidates: candidates,
      currentDatasetTemplates: _artifactTemplateSummaries(),
    );
  }

  void _acceptInteractiveArtifactCandidate(ArtifactCandidateData candidate) {
    final List<ArtifactExemplarData> exemplars = <ArtifactExemplarData>[
      ..._artifactExemplars(),
      ArtifactExemplarData(
        id: '${widget.dataset.id}:${candidate.id}',
        datasetId: widget.dataset.id,
        label: candidate.label,
        onsetMicros: candidate.onsetMicros,
        durationMicros: candidate.durationMicros,
        channelMask: candidate.channelMask,
      ),
    ];
    _recomputeInteractiveArtifactDraft(
      exemplars: exemplars,
      currentCandidates: _artifactCandidates()
          .where((ArtifactCandidateData item) => item.id != candidate.id)
          .toList(growable: false),
    );
  }

  void _rejectInteractiveArtifactCandidate(ArtifactCandidateData candidate) {
    _updateInteractiveArtifactCandidateStatus(
      candidate,
      InteractiveArtifactDetectionNodeType.rejectedStatus,
    );
  }

  void _undoAcceptedInteractiveArtifactCandidate(ArtifactCandidateData candidate) {
    _updateInteractiveArtifactCandidateStatus(
      candidate,
      InteractiveArtifactDetectionNodeType.pendingStatus,
    );
  }

  void _acceptAllInteractiveArtifactCandidates() {
    final List<ArtifactCandidateData> pendingCandidates = _artifactCandidates(
      statuses: const <String>{
        InteractiveArtifactDetectionNodeType.pendingStatus,
      },
    );
    final List<ArtifactExemplarData> exemplars = <ArtifactExemplarData>[
      ..._artifactExemplars(),
      ...pendingCandidates.map(
        (ArtifactCandidateData candidate) => ArtifactExemplarData(
          id: '${widget.dataset.id}:${candidate.id}',
          datasetId: widget.dataset.id,
          label: candidate.label,
          onsetMicros: candidate.onsetMicros,
          durationMicros: candidate.durationMicros,
          channelMask: candidate.channelMask,
        ),
      ),
    ];
    _recomputeInteractiveArtifactDraft(
      exemplars: exemplars,
      currentCandidates: _artifactCandidates()
          .where(
            (ArtifactCandidateData candidate) =>
                candidate.status !=
                InteractiveArtifactDetectionNodeType.pendingStatus,
          )
          .toList(growable: false),
    );
  }

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
      _markerCacheKey = null;
    });
  }

  void _saveDraftChanges() {
    if (_hasInteractiveArtifactDraft) {
      setState(() {
        widget.params['artifactExemplars'] =
            _draftArtifactExemplars ?? widget.params['artifactExemplars'];
        widget.params['artifactCandidates'] =
            _draftArtifactCandidates ?? widget.params['artifactCandidates'];
        widget.params['artifactTemplates'] =
            _draftArtifactTemplates ?? widget.params['artifactTemplates'];
        _draftArtifactExemplars = null;
        _draftArtifactCandidates = null;
        _draftArtifactTemplates = null;
        _markerCacheKey = null;
      });
      widget.onInteractiveArtifactDetectionSaved?.call();
      return;
    }

    final List<Map<String, dynamic>>? draftMarkers = _draftMarkers;
    if (draftMarkers == null) {
      return;
    }
    setState(() {
      widget.params['markers'] = draftMarkers;
      _draftMarkers = null;
      _markerCacheKey = null;
    });
    widget.onMarkersChanged?.call(draftMarkers);
  }

  void _saveDraftChangesAndQuit() {
    _saveDraftChanges();
    widget.onSaveAndQuit?.call();
  }

  void _discardDraftChanges() {
    setState(() {
      _draftMarkers = null;
      _draftArtifactExemplars = null;
      _draftArtifactCandidates = null;
      _draftArtifactTemplates = null;
      _dragSelectionStart = null;
      _dragSelectionCurrent = null;
      _dragSelectionGlobal = null;
      _markerCacheKey = null;
    });
  }

  void _jumpToTimeRange({
    required String referenceId,
    required int onsetMicros,
    required int durationMicros,
  }) {
    if (!_horizontalController.hasClients) {
      return;
    }
    final TimeSeriesData? timeSeries = widget.dataset.timeSeries;
    if (timeSeries == null || timeSeries.sampleRate <= 0) {
      return;
    }
    final double secondsPerView =
        (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
    final double onsetSeconds = onsetMicros / 1000000.0;
    final double durationSeconds = durationMicros / 1000000.0;
    final double centerSeconds = onsetSeconds + (durationSeconds / 2);
    final double recordingSeconds = timeSeries.sampleCount / timeSeries.sampleRate;
    final double viewportWidth = _horizontalController.position.viewportDimension;
    final double pixelsPerSecond = viewportWidth / secondsPerView;
    final double currentStartSeconds =
        _horizontalController.offset / pixelsPerSecond;
    final double currentEndSeconds = currentStartSeconds + secondsPerView;
    final bool alreadyVisible =
        onsetSeconds >= currentStartSeconds &&
        (onsetSeconds + math.max(durationSeconds, 0.001)) <= currentEndSeconds;
    final bool centerThisTime = _lastFocusedReferenceId == referenceId && alreadyVisible;
    final double targetStartSeconds = centerThisTime
        ? (centerSeconds - (secondsPerView / 2)).clamp(
            0.0,
            math.max(0.0, recordingSeconds - secondsPerView),
          )
        : onsetSeconds.clamp(
            0.0,
            math.max(0.0, recordingSeconds - secondsPerView),
          );
    final double targetOffset = targetStartSeconds * pixelsPerSecond;
    _lastFocusedReferenceId = referenceId;
    _horizontalController.animateTo(
      targetOffset.clamp(
        0.0,
        _horizontalController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
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
    widget.params.putIfAbsent('artifact_exemplars_expanded', () => true);
    widget.params.putIfAbsent('artifact_candidates_expanded', () => true);
    widget.params.putIfAbsent('y_scale_uv', () => 100.0);
    widget.params.putIfAbsent('raw_view_mode', () => 'signals');
    if (_interactiveArtifactDetectionEnabled()) {
      widget.params.putIfAbsent(
        'artifactExemplars',
        () => <Map<String, dynamic>>[],
      );
      widget.params.putIfAbsent(
        'artifactCandidates',
        () => <Map<String, dynamic>>[],
      );
      widget.params.putIfAbsent(
        'artifactTemplates',
        () => <Map<String, dynamic>>[],
      );
      widget.params.putIfAbsent('artifactThreshold', () => 0.78);
    }
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

  List<Color> _channelColors(int channelCount) {
    final Object cacheKey = Object.hash(
      widget.dataset.id,
      channelCount,
      widget.params['channel_colors'],
    );
    if (_colorCacheKey == cacheKey && _cachedChannelColors != null) {
      return _cachedChannelColors!;
    }
    final List<Color> colors = List<Color>.generate(
      channelCount,
      _colorForChannel,
      growable: false,
    );
    _colorCacheKey = cacheKey;
    _cachedChannelColors = colors;
    return colors;
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
      _colorCacheKey = null;
    });
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
    required this.onFocus,
  });

  final List<TimeMarker> markers;
  final ValueChanged<TimeMarker> onDelete;
  final ValueChanged<TimeMarker> onFocus;

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
        final bool isArtifact = marker.markerType == MarkerType.artifact;
        final Color markerColor = _markerDisplayColor(marker);
        return InputChip(
          avatar: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
            ),
          ),
          label: Text(
            '${marker.label} @ ${marker.timeSeconds.toStringAsFixed(2)} s',
          ),
          selected: isArtifact,
          selectedColor: markerColor.withValues(alpha: 0.22),
          onPressed: () => onFocus(marker),
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
    required this.onFocus,
  });

  final bool expanded;
  final List<TimeMarker> markers;
  final ValueChanged<bool> onToggle;
  final ValueChanged<TimeMarker> onDelete;
  final ValueChanged<TimeMarker> onFocus;

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
                onFocus: onFocus,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _markerDisplayColor(TimeMarker marker) {
  final String? interactiveStatus =
      marker.attributes['brainstory.artifactStatus']?.toString();
  final String? interactiveSource =
      marker.attributes['brainstory.artifactSource']?.toString();
  if (interactiveStatus == InteractiveArtifactDetectionNodeType.pendingStatus) {
    return const Color(0xFFFFA630);
  }
  if (interactiveSource == 'exemplar') {
    return const Color(0xFFFF4D8D);
  }
  if (interactiveStatus == InteractiveArtifactDetectionNodeType.acceptedStatus) {
    return const Color(0xFFFF5A36);
  }
  return marker.markerType == MarkerType.artifact
      ? const Color(0xFFFF6B35)
      : const Color(0xFFFFC145);
}

Color _complementColor(Color color) {
  final int argb = color.toARGB32();
  final int alpha = (argb >> 24) & 0xFF;
  final int red = (argb >> 16) & 0xFF;
  final int green = (argb >> 8) & 0xFF;
  final int blue = argb & 0xFF;
  return Color.fromARGB(
    alpha,
    255 - red,
    255 - green,
    255 - blue,
  );
}

void _drawMarkerGuideLine({
  required Canvas canvas,
  required double x,
  required double top,
  required double bottom,
  required Color color,
  required String? interactiveStatus,
  required String? interactiveSource,
}) {
  final Paint paint = Paint()
    ..color = color.withValues(alpha: 0.95)
    ..strokeWidth = 2.4;
  if (interactiveStatus == InteractiveArtifactDetectionNodeType.pendingStatus) {
    const double dot = 2.5;
    const double gap = 5.0;
    for (double y = top; y < bottom; y += dot + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(bottom, y + dot)),
        paint,
      );
    }
    return;
  }
  if (interactiveSource == 'exemplar' ||
      interactiveStatus == InteractiveArtifactDetectionNodeType.acceptedStatus) {
    const double dash = 8.0;
    const double gap = 4.0;
    for (double y = top; y < bottom; y += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(bottom, y + dash)),
        paint,
      );
    }
    return;
  }
  canvas.drawLine(
    Offset(x, top),
    Offset(x, bottom),
    paint,
  );
}

Color _artifactTemplateColor(String label) {
  switch (label) {
    case 'blink':
      return const Color(0xFFFF4D8D);
    case 'saccade_vertical':
      return const Color(0xFFFF8C42);
    case 'saccade_horizontal':
      return const Color(0xFFFFC145);
    case 'motion':
      return const Color(0xFFFF5A36);
    default:
      return const Color(0xFFFF9F1C);
  }
}

class _InteractiveArtifactReviewSection extends StatelessWidget {
  const _InteractiveArtifactReviewSection({
    required this.labelChoices,
    required this.exemplarsExpanded,
    required this.candidatesExpanded,
    required this.templates,
    required this.exemplars,
    required this.pendingCandidates,
    required this.acceptedCandidates,
    required this.onDeleteExemplar,
    required this.onAcceptCandidate,
    required this.onRejectCandidate,
    required this.onUndoAccepted,
    required this.onAcceptAll,
    required this.onFocusExemplar,
    required this.onFocusPendingCandidate,
    required this.onFocusAcceptedCandidate,
    required this.onToggleExemplars,
    required this.onToggleCandidates,
  });

  final List<String> labelChoices;
  final bool exemplarsExpanded;
  final bool candidatesExpanded;
  final List<ArtifactTemplateSummary> templates;
  final List<ArtifactExemplarData> exemplars;
  final List<ArtifactCandidateData> pendingCandidates;
  final List<ArtifactCandidateData> acceptedCandidates;
  final ValueChanged<ArtifactExemplarData> onDeleteExemplar;
  final ValueChanged<ArtifactCandidateData> onAcceptCandidate;
  final ValueChanged<ArtifactCandidateData> onRejectCandidate;
  final ValueChanged<ArtifactCandidateData> onUndoAccepted;
  final VoidCallback onAcceptAll;
  final ValueChanged<ArtifactExemplarData> onFocusExemplar;
  final ValueChanged<ArtifactCandidateData> onFocusPendingCandidate;
  final ValueChanged<ArtifactCandidateData> onFocusAcceptedCandidate;
  final ValueChanged<bool> onToggleExemplars;
  final ValueChanged<bool> onToggleCandidates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Interactive artifact detection',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap any exemplar or candidate to jump there. Alt+drag adds ${labelChoices.where((String label) => label != 'blink').join(', ')}.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (templates.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _ArtifactTemplatePreview(templates: templates),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: templates.map((ArtifactTemplateSummary template) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _artifactTemplateColor(template.label).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _artifactTemplateColor(template.label).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '${template.label}: ${template.exemplarCount} exemplar${template.exemplarCount == 1 ? '' : 's'} • ${template.sampleCount} samples',
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }).toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          _SectionHeader(
            title: 'Exemplars',
            count: exemplars.length,
            expanded: exemplarsExpanded,
            onToggle: () => onToggleExemplars(!exemplarsExpanded),
          ),
          if (exemplarsExpanded) ...<Widget>[
            const SizedBox(height: 8),
            if (exemplars.isEmpty)
              const Text(
                'No exemplars yet.',
                style: TextStyle(color: Colors.white54),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: exemplars.map((ArtifactExemplarData exemplar) {
                  final Color labelColor = _artifactTemplateColor(exemplar.label);
                  return InputChip(
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: labelColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: Text(
                      '${exemplar.label} @ ${(exemplar.onsetMicros / 1000000.0).toStringAsFixed(2)} s',
                    ),
                    selected: true,
                    selectedColor: labelColor.withValues(alpha: 0.22),
                    onPressed: () => onFocusExemplar(exemplar),
                    onDeleted: () => onDeleteExemplar(exemplar),
                  );
                }).toList(growable: false),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _SectionHeader(
                  title: 'Candidate matches',
                  count: pendingCandidates.length + acceptedCandidates.length,
                  expanded: candidatesExpanded,
                  onToggle: () => onToggleCandidates(!candidatesExpanded),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: pendingCandidates.isEmpty ? null : onAcceptAll,
                child: const Text('Accept All'),
              ),
            ],
          ),
          if (candidatesExpanded) ...<Widget>[
            const SizedBox(height: 8),
            if (pendingCandidates.isEmpty)
              const Text(
                'No pending candidates.',
                style: TextStyle(color: Colors.white54),
              )
            else
              Column(
                children: pendingCandidates.map((ArtifactCandidateData candidate) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: _artifactTemplateColor(candidate.label).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onFocusPendingCandidate(candidate),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _artifactTemplateColor(candidate.label),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${candidate.label} @ ${(candidate.onsetMicros / 1000000.0).toStringAsFixed(2)} s • score ${candidate.score.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => onRejectCandidate(candidate),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton(
                                onPressed: () => onAcceptCandidate(candidate),
                                child: const Text('Accept'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
            if (acceptedCandidates.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                'Accepted candidates',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: acceptedCandidates.map((ArtifactCandidateData candidate) {
                  final Color labelColor = _artifactTemplateColor(candidate.label);
                  return InputChip(
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: labelColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: Text(
                      '${candidate.label} @ ${(candidate.onsetMicros / 1000000.0).toStringAsFixed(2)} s',
                    ),
                    selected: true,
                    selectedColor: labelColor.withValues(alpha: 0.22),
                    onPressed: () => onFocusAcceptedCandidate(candidate),
                    onDeleted: () => onUndoAccepted(candidate),
                  );
                }).toList(growable: false),
              ),
            ],
          ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Row(
        children: <Widget>[
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '$title ($count)',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactTemplatePreview extends StatelessWidget {
  const _ArtifactTemplatePreview({
    required this.templates,
  });

  final List<ArtifactTemplateSummary> templates;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Current template',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              painter: _ArtifactTemplatePainter(templates: templates),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactTemplatePainter extends CustomPainter {
  const _ArtifactTemplatePainter({
    required this.templates,
  });

  final List<ArtifactTemplateSummary> templates;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final Paint baselinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;

    final double centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), baselinePaint);
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), gridPaint);

    double maxAbs = 1.0;
    for (final ArtifactTemplateSummary template in templates) {
      final List<List<double>> channels = template.previewChannels.isNotEmpty
          ? template.previewChannels
          : <List<double>>[template.previewSamples];
      for (final List<double> channel in channels) {
        for (final double sample in channel) {
          final double absValue = sample.abs();
          if (absValue > maxAbs) {
            maxAbs = absValue;
          }
        }
      }
    }

    for (final ArtifactTemplateSummary template in templates) {
      final List<List<double>> channels = template.previewChannels.isNotEmpty
          ? template.previewChannels
          : <List<double>>[template.previewSamples];
      for (final List<double> samples in channels) {
        if (samples.length < 2) {
          continue;
        }
        final Path path = Path();
        for (int index = 0; index < samples.length; index++) {
          final double x = samples.length == 1
              ? 0
              : (index / (samples.length - 1)) * size.width;
          final double y =
              centerY - ((samples[index] / maxAbs) * (size.height * 0.38));
          if (index == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        final Paint paint = Paint()
          ..color = _artifactTemplateColor(template.label).withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArtifactTemplatePainter oldDelegate) {
    return oldDelegate.templates != templates;
  }
}

class _TimeAxisBar extends StatelessWidget {
  const _TimeAxisBar({
    required this.controller,
    required this.pixelsPerSecond,
    required this.viewportWidth,
    required this.durationSeconds,
  });

  final ScrollController controller;
  final double pixelsPerSecond;
  final double viewportWidth;
  final double durationSeconds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final double offset = controller.hasClients ? controller.offset : 0.0;
          final double startSeconds = offset / pixelsPerSecond;
          final double endSeconds = (offset + viewportWidth) / pixelsPerSecond;
          final int firstTick = math.max(0, startSeconds.floor());
          final int lastTick = math.min(durationSeconds.ceil(), endSeconds.ceil());

          return Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: ClipRect(
              child: Stack(
                children: <Widget>[
                  for (int second = firstTick; second <= lastTick; second++)
                    Positioned(
                      left: (second * pixelsPerSecond) - offset - 1,
                      top: 0,
                      child: SizedBox(
                        width: 44,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 1,
                              height: 8,
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${second}s',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
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
    this.selectionStartX,
    this.selectionEndX,
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
  final double? selectionStartX;
  final double? selectionEndX;
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

    final List<TimeMarker> visibleMarkers = <TimeMarker>[];
    for (final TimeMarker marker in markers) {
      final double x = marker.timeSeconds * pixelsPerSecond;
      final double markerEndX = ((marker.onsetMicros + marker.durationMicros) / 1000000.0) *
          pixelsPerSecond;
      if (markerEndX < horizontalOffset - 24 ||
          x > horizontalOffset + viewportWidth + 24) {
        continue;
      }
      visibleMarkers.add(marker);
      final Color markerColor = _markerDisplayColor(marker);
      if (marker.durationMicros > 0) {
        final Paint rangePaint = Paint()
          ..color = markerColor.withValues(alpha: 0.24)
          ..style = PaintingStyle.fill;
        final Rect rangeRect = Rect.fromLTRB(
          x,
          verticalOffset,
          math.max(x + 1, markerEndX),
          verticalOffset + viewportHeight,
        );
        canvas.drawRect(rangeRect, rangePaint);
      }
    }

    if (selectionStartX != null && selectionEndX != null) {
      final double left = math.min(selectionStartX!, selectionEndX!);
      final double right = math.max(selectionStartX!, selectionEndX!);
      final Paint selectionPaint = Paint()
        ..color = Colors.pinkAccent.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final Paint selectionBorderPaint = Paint()
        ..color = Colors.pinkAccent.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final Rect selectionRect = Rect.fromLTRB(
        left,
        verticalOffset,
        right,
        verticalOffset + viewportHeight,
      );
      canvas.drawRect(selectionRect, selectionPaint);
      canvas.drawRect(selectionRect, selectionBorderPaint);
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
      final int visibleSampleCount = endSample - startSample;
      final int stride = math.max(
        1,
        (visibleSampleCount / math.max(1.0, viewportWidth * 2)).ceil(),
      );
      for (int sampleIndex = startSample; sampleIndex < endSample; sampleIndex += stride) {
        final double x = (sampleIndex / sampleRate) * pixelsPerSecond;
        final double y = centerY - (samples[sampleIndex] * pixelsPerUv);
        if (sampleIndex == startSample) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if ((endSample - 1) > startSample) {
        final int lastSampleIndex = endSample - 1;
        path.lineTo(
          (lastSampleIndex / sampleRate) * pixelsPerSecond,
          centerY - (samples[lastSampleIndex] * pixelsPerUv),
        );
      }

      final Paint signalPaint = Paint()
        ..color = colors[channelIndex]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(path, signalPaint);

      for (final TimeMarker marker in visibleMarkers) {
        if (marker.durationMicros <= 0) {
          continue;
        }
        final double markerStartX = marker.timeSeconds * pixelsPerSecond;
        final double markerEndX =
            ((marker.onsetMicros + marker.durationMicros) / 1000000.0) *
                pixelsPerSecond;
        canvas.save();
        canvas.clipRect(
          Rect.fromLTRB(
            markerStartX,
            centerY - (channelHeight * 0.48),
            math.max(markerStartX + 1, markerEndX),
            centerY + (channelHeight * 0.48),
          ),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = _complementColor(_markerDisplayColor(marker))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.9,
        );
        canvas.restore();
      }
    }

    for (final TimeMarker marker in visibleMarkers) {
      final double x = marker.timeSeconds * pixelsPerSecond;
      final double markerEndX =
          ((marker.onsetMicros + marker.durationMicros) / 1000000.0) *
              pixelsPerSecond;
      final Color markerColor = _markerDisplayColor(marker);
      final String? interactiveStatus =
          marker.attributes['brainstory.artifactStatus']?.toString();
      final String? interactiveSource =
          marker.attributes['brainstory.artifactSource']?.toString();
      _drawMarkerGuideLine(
        canvas: canvas,
        x: x,
        top: verticalOffset,
        bottom: verticalOffset + viewportHeight,
        color: markerColor,
        interactiveStatus: interactiveStatus,
        interactiveSource: interactiveSource,
      );
      if (marker.durationMicros > 0) {
        _drawMarkerGuideLine(
          canvas: canvas,
          x: markerEndX,
          top: verticalOffset,
          bottom: verticalOffset + viewportHeight,
          color: markerColor,
          interactiveStatus: interactiveStatus,
          interactiveSource: interactiveSource,
        );
      }
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: TextStyle(
            color: markerColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: const <Shadow>[
              Shadow(
                blurRadius: 8,
                color: Colors.black,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x + 4, verticalOffset + 4));
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
        oldDelegate.selectionStartX != selectionStartX ||
        oldDelegate.selectionEndX != selectionEndX ||
        oldDelegate.horizontalOffset != horizontalOffset ||
        oldDelegate.verticalOffset != verticalOffset ||
        oldDelegate.viewportWidth != viewportWidth ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}
