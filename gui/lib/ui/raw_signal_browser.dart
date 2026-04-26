import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/edit_channels_node.dart';
import '../nodes/interactive_artifact_detection_node.dart';
import 'viewer_interaction.dart';

class RawSignalBrowser extends StatefulWidget {
  const RawSignalBrowser({
    super.key,
    required this.dataset,
    required this.params,
    this.onChanged,
    this.onMarkersChanged,
    this.onChannelEditsSaved,
    this.onInteractiveArtifactDetectionSaved,
    this.onSaveAndQuit,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback? onChanged;
  final ValueChanged<List<dynamic>>? onMarkersChanged;
  final ValueChanged<Map<String, dynamic>>? onChannelEditsSaved;
  final String Function()? onInteractiveArtifactDetectionSaved;
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
  static const List<double> _timeSpanOptionsSec = <double>[1, 2, 5, 10, 20, 30];
  static const double _collapsedRailWidth = 28;

  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  Object? _filterCacheKey;
  List<List<double>>? _filteredChannels;
  List<Map<String, dynamic>>? _draftMarkers;
  Map<String, dynamic>? _draftChannelEditConfig;
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
  String? _hoveredMarkerReferenceId;
  String? _selectedMarkerReferenceId;
  bool _renamingMarker = false;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController(keepScrollOffset: false);
    _horizontalController = ScrollController(keepScrollOffset: false);
    _ensureDefaults();
  }

  @override
  void didUpdateWidget(covariant RawSignalBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureDefaults();
    if (oldWidget.dataset.id != widget.dataset.id) {
      _draftMarkers = null;
      _draftChannelEditConfig = null;
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
    final TimeSeriesData? baseTimeSeries = widget.dataset.timeSeries;
    final TimeSeriesData? timeSeries = baseTimeSeries;
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
    final bool showSignals = _showSignals();
    final bool showMarkers = _showMarkers();
    final bool removeDc = _removeDc();
    final bool hideSignals = !showSignals;
    final bool interactiveArtifactDetection = _interactiveArtifactWorkflowEnabled();
    final List<TimeMarker> renderedMarkers = !showMarkers
        ? const <TimeMarker>[]
        : interactiveArtifactDetection
            ? _interactiveDisplayMarkers(timeSeries)
            : _currentMarkersForDataset();
    final List<TimeMarker> listedMarkers = !showMarkers
        ? const <TimeMarker>[]
        : interactiveArtifactDetection
            ? InteractiveArtifactDetectionNodeType.acceptedMarkersForDataset(
                widget.dataset.id,
                _effectiveInteractiveArtifactParams,
                baseMarkers: timeSeries.markers,
              )
            : _currentMarkersForDataset();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildControlBar(
          timeSeries: timeSeries,
          sampleRate: timeSeries.sampleRate,
          channelCount: channelCount,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool rightCollapsed = _rightPanelCollapsed();
              final double defaultLabelWidth = _defaultLeftPanelWidth(labels);
              final double defaultSidePanelWidth =
                  _defaultRightPanelWidth(listedMarkers);
              final double labelWidth = hideSignals
                  ? 0
                  : _resolvedLeftPanelWidth(defaultLabelWidth);
              final double sidePanelWidth = rightCollapsed
                  ? _collapsedRailWidth
                  : _resolvedRightPanelWidth(defaultSidePanelWidth);
              final double leftPaneWidth =
                  math.max(260, constraints.maxWidth - sidePanelWidth - 24 - labelWidth);
              final double traceWidth = math.max(
                180,
                leftPaneWidth,
              );
              final double secondsPerView =
                  (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
              final double pixelsPerSecond = traceWidth / secondsPerView;
              final double totalWidth =
                  math.max(traceWidth, durationSeconds * pixelsPerSecond);
              const double axisHeight = 26;
              const double timelineHeight = 28;
              const double bottomChromeHeight = axisHeight + timelineHeight + 12;
              final double axisLeftInset = hideSignals ? 0 : labelWidth + 16;
              final double traceAreaHeight =
                  math.max(140, constraints.maxHeight - bottomChromeHeight);
              final double totalHeight = hideSignals
                  ? traceAreaHeight
                  : math.max(
                      traceAreaHeight,
                      _channelHeight(traceAreaHeight, channelCount) * channelCount,
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
                                        if (!hideSignals)
                                          SizedBox(
                                            width: labelWidth,
                                            child: _ChannelLabelColumn(
                                              labels: labels,
                                              colors: channelColors,
                                              channelHeight: _channelHeight(
                                                traceAreaHeight,
                                                channelCount,
                                              ),
                                              onCycleColor: _cycleChannelColor,
                                              channelEditEnabled:
                                                  _interactionMode() == 'edit',
                                              onEditChannel: _showChannelEditPanel,
                                            ),
                                          ),
                                        if (!hideSignals) const SizedBox(width: 4),
                                        if (!hideSignals)
                                          _PanelResizeHandle(
                                            onDoubleTap: () => setState(() {
                                              widget.params.remove('left_panel_width');
                                            }),
                                            onDragUpdate: (double delta) {
                                              _updateParam(
                                                'left_panel_width',
                                                (_resolvedLeftPanelWidth(defaultLabelWidth) +
                                                        delta)
                                                    .clamp(88.0, 260.0),
                                              );
                                            },
                                          ),
                                        if (!hideSignals) const SizedBox(width: 4),
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
                                              child: Listener(
                                                onPointerSignal: (PointerSignalEvent event) {
                                                  _handleTracePointerSignal(
                                                    event,
                                                    durationSeconds: durationSeconds,
                                                    pixelsPerSecond: pixelsPerSecond,
                                                    viewportWidth: traceWidth,
                                                    viewportHeight: traceAreaHeight,
                                                  );
                                                },
                                                child: MouseRegion(
                                                onHover: (PointerHoverEvent details) {
                                                  if (_interactionMode() != 'edit') {
                                                    if (_hoveredMarkerReferenceId != null) {
                                                      setState(() {
                                                        _hoveredMarkerReferenceId = null;
                                                      });
                                                    }
                                                    return;
                                                  }
                                                  final TimeMarker? hoveredMarker =
                                                      _markerAtLabelPosition(
                                                    details.localPosition,
                                                    pixelsPerSecond,
                                                  );
                                                  final String? nextId = hoveredMarker == null
                                                      ? null
                                                      : _markerReferenceId(hoveredMarker);
                                                  if (nextId != _hoveredMarkerReferenceId) {
                                                    setState(() {
                                                      _hoveredMarkerReferenceId = nextId;
                                                    });
                                                  }
                                                },
                                                onExit: (_) {
                                                  if (_hoveredMarkerReferenceId != null) {
                                                    setState(() {
                                                      _hoveredMarkerReferenceId = null;
                                                    });
                                                  }
                                                },
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onTapDown: interactiveArtifactDetection
                                                      ? null
                                                      : null,
                                                  onPanStart: interactiveArtifactDetection
                                                      ? (DragStartDetails details) {
                                                          _handleArtifactDragStart(
                                                            details.localPosition,
                                                            details.globalPosition,
                                                          );
                                                        }
                                                      : _interactionMode() == 'edit'
                                                          ? (DragStartDetails details) {
                                                              _handleMarkerDragStart(
                                                                details.localPosition,
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
                                                      : _interactionMode() == 'edit'
                                                          ? (DragUpdateDetails details) {
                                                              _handleMarkerDragUpdate(
                                                                details.localPosition,
                                                              );
                                                            }
                                                          : null,
                                                  onPanEnd: interactiveArtifactDetection
                                                      ? (DragEndDetails details) {
                                                          _handleArtifactDragEnd(
                                                            pixelsPerSecond,
                                                          );
                                                        }
                                                      : _interactionMode() == 'edit'
                                                          ? (DragEndDetails details) {
                                                              _handleMarkerDragEnd(
                                                                pixelsPerSecond,
                                                              );
                                                            }
                                                          : null,
                                                  onTapUp: interactiveArtifactDetection
                                                      ? null
                                                      : (TapUpDetails details) {
                                                          _handleMarkerTapOrRename(
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
                                                              channelCount,
                                                            ),
                                                            pixelsPerSecond: pixelsPerSecond,
                                                            yScaleUv: _yScaleUv(),
                                                            showSignals: showSignals,
                                                            removeDc: removeDc,
                                                            colors: channelColors,
                                                            markers: renderedMarkers,
                                                            selectionStartX: _dragSelectionStart?.dx,
                                                            selectionEndX: _dragSelectionCurrent?.dx,
                                                            hoveredMarkerReferenceId:
                                                                _hoveredMarkerReferenceId,
                                                            selectedMarkerReferenceId:
                                                                _selectedMarkerReferenceId,
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
                            padding: EdgeInsets.only(left: axisLeftInset),
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
                            padding: EdgeInsets.only(left: axisLeftInset),
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
                  const SizedBox(width: 8),
                  _PanelResizeHandle(
                    onDoubleTap: rightCollapsed
                        ? null
                        : () => setState(() {
                              widget.params.remove('right_panel_width');
                            }),
                    onDragUpdate: rightCollapsed
                        ? null
                        : (double delta) {
                            _updateParam(
                              'right_panel_width',
                              (_resolvedRightPanelWidth(defaultSidePanelWidth) - delta)
                                  .clamp(188.0, 420.0),
                            );
                          },
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: sidePanelWidth,
                    child: rightCollapsed
                        ? _CollapsedSideRail(
                            tooltip: 'Show markers',
                            icon: Icons.chevron_left,
                            onTap: () => _updateParam('right_panel_collapsed', false),
                          )
                        : _buildInfoPanel(
                            interactiveArtifactDetection: interactiveArtifactDetection,
                            markers: listedMarkers,
                            onCollapse: () => _updateParam('right_panel_collapsed', true),
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
    required TimeSeriesData timeSeries,
    required double sampleRate,
    required int channelCount,
  }) {
    final bool interactiveArtifactMode = _interactiveModeActive();
    final double windowSeconds =
        (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
    final bool showSignals = _showSignals();
    final bool showMarkers = _showMarkers();
    final bool removeDc = _removeDc();
    final List<_ResolvedChannelCoordinate> mappedCoordinates =
        _resolvedChannelCoordinatesForTimeSeries(timeSeries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '$channelCount ch  •  ${sampleRate.toStringAsFixed(1)} Hz',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const _ControlStripDivider(),
            _InlineToggleGroup(
              label: 'View:',
              options: <_InlineToggleOption>[
                _InlineToggleOption(
                  label: 'data',
                  selected: showSignals,
                  onPressed: () => _updateParam('raw_show_data', !showSignals),
                ),
                _InlineToggleOption(
                  label: 'markers',
                  selected: showMarkers,
                  onPressed: () => _updateParam('raw_show_markers', !showMarkers),
                ),
                _InlineToggleOption(
                  label: 'Remove DC',
                  selected: removeDc,
                  leadingGap: 10,
                  showLeadingDivider: true,
                  onPressed: () => _updateParam('raw_remove_dc', !removeDc),
                ),
              ],
            ),
            const _ControlStripDivider(),
            _InlineChoiceGroup(
              label: 'Mode:',
              options: <_InlineChoiceOption>[
                _InlineChoiceOption(
                  label: 'view',
                  selected: _interactionMode() == 'view',
                  onPressed: () => _updateParam('interaction_mode', 'view'),
                ),
                _InlineChoiceOption(
                  label: 'edit',
                  selected: _interactionMode() == 'edit',
                  onPressed: () => _updateParam('interaction_mode', 'edit'),
                ),
                _InlineChoiceOption(
                  label: 'interactive',
                  selected: _interactionMode() == 'interactive',
                  onPressed: () => _updateParam('interaction_mode', 'interactive'),
                ),
              ],
            ),
            if (interactiveArtifactMode)
              const Text(
                'Drag to label blink • Alt+drag for other artifacts',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            const _ControlStripDivider(),
            _ScaleCluster(
              timeSeconds: windowSeconds,
              timeOptionsSeconds: _timeSpanOptionsSec,
              onTimeSelected: (double value) => _updateParam('window_sec', value),
              rangeUv: _yScaleUv(),
              rangeOptionsUv: _yScaleOptionsUv,
              onRangeSelected: (double value) => _updateParam('y_scale_uv', value),
            ),
            const _ControlStripDivider(),
            Tooltip(
              message: mappedCoordinates.isEmpty
                  ? 'Run Channel Positions upstream first.'
                  : 'View mapped channel positions and XYZ coordinates',
              child: OutlinedButton.icon(
                onPressed: mappedCoordinates.isEmpty
                    ? null
                    : () => _showChannelPositionsDialog(timeSeries),
                icon: const Icon(Icons.public, size: 18),
                label: const Text('Channel positions'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoPanel({
    required bool interactiveArtifactDetection,
    required List<TimeMarker> markers,
    required VoidCallback onCollapse,
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
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Collapse panel',
                visualDensity: VisualDensity.compact,
                onPressed: onCollapse,
                icon: const Icon(
                  Icons.chevron_right,
                  color: Colors.white70,
                ),
              ),
            ),
            if (_hasAnyDraftChanges) ...<Widget>[
              if (interactiveArtifactDetection) ...<Widget>[
                _buildInteractiveDraftSummary(),
                const SizedBox(height: 10),
              ],
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
                        timeSeries: widget.dataset.timeSeries,
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
                      labelExpandedMap: Map<String, dynamic>.from(
                        widget.params['marker_label_expanded'] as Map? ?? <String, dynamic>{},
                      ),
                      onToggleLabelExpanded: (String label, bool expanded) {
                        final Map<String, dynamic> next = Map<String, dynamic>.from(
                          widget.params['marker_label_expanded'] as Map? ?? <String, dynamic>{},
                        );
                        next[label] = expanded;
                        _updateParam('marker_label_expanded', next);
                      },
                      onDelete: _deleteMarker,
                      onFocus: (TimeMarker marker) {
                        _focusMarker(marker);
                      },
                      selectedMarkerReferenceId: _selectedMarkerReferenceId,
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
            interactiveArtifactDetection
                ? 'Save'
                : _hasChannelEditDraft && !_hasMarkerDraft
                    ? 'Save Channel Edits'
                    : 'Save',
          ),
        ),
        FilledButton.tonal(
          onPressed: _saveDraftChangesAndQuit,
          child: const Text('Save and Quit'),
        ),
      ],
    );
  }

  Widget _buildInteractiveDraftSummary() {
    final int exemplarCount = _artifactExemplars().length;
    final int pendingCount = _artifactCandidates(
      statuses: const <String>{
        InteractiveArtifactDetectionNodeType.pendingStatus,
      },
    ).length;
    final int acceptedCount = _artifactCandidates(
      statuses: const <String>{
        InteractiveArtifactDetectionNodeType.acceptedStatus,
      },
    ).length;
    final int templateCount = _artifactTemplateSummaries().length;
    final bool alreadyBackedByNode = _interactiveArtifactDetectionEnabled();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Pending interactive changes',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Save will ${alreadyBackedByNode ? 'update' : 'add'} the Interactive Artifact Detection node for ${widget.dataset.label}.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _SummaryChip(label: 'Exemplars', value: '$exemplarCount'),
                _SummaryChip(label: 'Pending', value: '$pendingCount'),
                _SummaryChip(label: 'Accepted', value: '$acceptedCount'),
                _SummaryChip(label: 'Templates', value: '$templateCount'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _updateParam(String key, dynamic value) {
    setState(() {
      widget.params[key] = value;
      if (key == 'interaction_mode' && value == 'interactive') {
        widget.params.putIfAbsent('artifactExemplars', () => <Map<String, dynamic>>[]);
        widget.params.putIfAbsent('artifactCandidates', () => <Map<String, dynamic>>[]);
        widget.params.putIfAbsent('artifactTemplates', () => <Map<String, dynamic>>[]);
        widget.params.putIfAbsent('artifactThreshold', () => 0.78);
      }
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

  void _handleTracePointerSignal(
    PointerSignalEvent event, {
    required double durationSeconds,
    required double pixelsPerSecond,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    final ViewerScrollGesture? gesture =
        viewerScrollGestureFromPointerSignal(event);
    if (gesture == null) {
      return;
    }
    switch (gesture.intent) {
      case ViewerScrollIntent.timeZoom:
        _zoomTimeAtPointer(
          scrollDeltaY: gesture.primaryDelta,
          localX: gesture.localPosition.dx,
          durationSeconds: durationSeconds,
          pixelsPerSecond: pixelsPerSecond,
        );
        return;
      case ViewerScrollIntent.amplitudeZoom:
        _stepAmplitudeScale(gesture.primaryDelta);
        return;
      case ViewerScrollIntent.horizontalPan:
        scrollControllerBy(_horizontalController, gesture.primaryDelta);
        return;
      case ViewerScrollIntent.verticalPan:
        scrollControllerBy(_verticalController, gesture.primaryDelta);
        return;
    }
  }

  void _zoomTimeAtPointer({
    required double scrollDeltaY,
    required double localX,
    required double durationSeconds,
    required double pixelsPerSecond,
  }) {
    final double currentWindow =
        (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
    final double zoomFactor = scrollDeltaY < 0 ? 0.82 : 1.22;
    final double nextWindow = (currentWindow * zoomFactor).clamp(
      0.1,
      math.max(0.1, durationSeconds),
    );
    final double oldOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    final double cursorSeconds = (oldOffset + localX) / pixelsPerSecond;
    setState(() {
      widget.params['window_sec'] = nextWindow;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontalController.hasClients) {
        return;
      }
      final double viewportFraction =
          currentWindow <= 0 ? 0.5 : (localX / math.max(1.0, currentWindow * pixelsPerSecond));
      final double nextPixelsPerSecond =
          _horizontalController.position.viewportDimension / nextWindow;
      final double targetOffset =
          (cursorSeconds * nextPixelsPerSecond) -
              (viewportFraction * _horizontalController.position.viewportDimension);
      _horizontalController.jumpTo(
        targetOffset.clamp(0.0, _horizontalController.position.maxScrollExtent),
      );
    });
  }

  void _stepAmplitudeScale(double scrollDeltaY) {
    final double current = _yScaleUv();
    final int index = _nearestOptionIndex(_yScaleOptionsUv, current);
    final int direction = scrollDeltaY < 0 ? -1 : 1;
    final int nextIndex =
        (index + direction).clamp(0, _yScaleOptionsUv.length - 1);
    if (nextIndex != index) {
      _updateParam('y_scale_uv', _yScaleOptionsUv[nextIndex]);
    }
  }

  int _nearestOptionIndex(List<double> options, double value) {
    int bestIndex = 0;
    double bestDistance = (options.first - value).abs();
    for (int index = 1; index < options.length; index++) {
      final double distance = (options[index] - value).abs();
      if (distance < bestDistance) {
        bestIndex = index;
        bestDistance = distance;
      }
    }
    return bestIndex;
  }

  void _handleMarkerTapOrRename(Offset localPosition, double pixelsPerSecond) {
    if (_renamingMarker) {
      return;
    }
    if (_interactionMode() != 'edit') {
      return;
    }

    if (_dragSelectionStart != null || _dragSelectionCurrent != null) {
      return;
    }

    final TimeMarker? tappedMarker = _markerAtLabelPosition(localPosition, pixelsPerSecond);
    if (tappedMarker != null) {
      _setSelectedMarker(tappedMarker);
      _renameMarker(tappedMarker);
      return;
    }

    _createMarkerFromRange(
      startDx: localPosition.dx,
      endDx: localPosition.dx,
      pixelsPerSecond: pixelsPerSecond,
    );
  }

  void _handleMarkerDragStart(Offset localPosition) {
    if (_renamingMarker) {
      return;
    }
    setState(() {
      _dragSelectionStart = localPosition;
      _dragSelectionCurrent = localPosition;
    });
  }

  void _handleMarkerDragUpdate(Offset localPosition) {
    if (_dragSelectionStart == null) {
      return;
    }
    setState(() {
      _dragSelectionCurrent = localPosition;
    });
  }

  void _handleMarkerDragEnd(double pixelsPerSecond) {
    final Offset? start = _dragSelectionStart;
    final Offset? end = _dragSelectionCurrent;
    setState(() {
      _dragSelectionStart = null;
      _dragSelectionCurrent = null;
    });
    if (start == null || end == null) {
      return;
    }
    _createMarkerFromRange(
      startDx: start.dx,
      endDx: end.dx,
      pixelsPerSecond: pixelsPerSecond,
    );
  }

  void _createMarkerFromRange({
    required double startDx,
    required double endDx,
    required double pixelsPerSecond,
  }) {
    final String markerMode = _hiddenMarkerType();
    final List<TimeMarker> currentMarkers = _currentMarkersForDataset();
    final double leftDx = math.min(startDx, endDx);
    final double rightDx = math.max(startDx, endDx);
    final int onsetMicros = ((leftDx / pixelsPerSecond) * 1000000.0).round();
    final int durationMicros = ((math.max(0.0, rightDx - leftDx) / pixelsPerSecond) *
            1000000.0)
        .round();
    final String label = _defaultMarkerLabel();
    final TimeMarker marker = TimeMarker(
      onsetMicros: onsetMicros,
      durationMicros: markerMode == MarkerType.event ? 0 : durationMicros,
      label: label,
      markerType: markerMode,
    );

    _setDraftMarkersForDataset(<TimeMarker>[...currentMarkers, marker]);
  }

  TimeMarker? _markerAtLabelPosition(Offset localPosition, double pixelsPerSecond) {
    final double verticalOffset =
        _verticalController.hasClients ? _verticalController.offset : 0.0;
    final double labelTop = verticalOffset + 4;
    const double labelHeight = 18;
    if (localPosition.dy < labelTop || localPosition.dy > (labelTop + labelHeight)) {
      return null;
    }
    for (final TimeMarker marker in _currentMarkersForDataset().reversed) {
      final double x = marker.timeSeconds * pixelsPerSecond;
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: TextStyle(
            color: _markerDisplayColor(marker),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final Rect rect = Rect.fromLTWH(
        x + 4,
        labelTop,
        textPainter.width,
        math.max(labelHeight, textPainter.height),
      );
      if (rect.contains(localPosition)) {
        return marker;
      }
    }
    return null;
  }

  String _markerReferenceId(TimeMarker marker) {
    return markerReferenceIdFor(marker);
  }

  void _setSelectedMarker(TimeMarker marker) {
    final Map<String, dynamic> nextExpandedMap = Map<String, dynamic>.from(
      widget.params['marker_label_expanded'] as Map? ?? <String, dynamic>{},
    );
    nextExpandedMap[marker.label] = true;
    setState(() {
      _selectedMarkerReferenceId = markerReferenceIdFor(marker);
      widget.params['marker_label_expanded'] = nextExpandedMap;
    });
  }

  void _focusMarker(TimeMarker marker) {
    _setSelectedMarker(marker);
    _jumpToTimeRange(
      referenceId: markerReferenceIdFor(marker),
      onsetMicros: marker.onsetMicros,
      durationMicros: marker.durationMicros,
    );
  }

  Future<void> _renameMarker(TimeMarker marker) async {
    if (_renamingMarker) {
      return;
    }
    final String markerId = _markerReferenceId(marker);
    final TextEditingController controller = TextEditingController(text: marker.label);
    final String? nextLabel;
    setState(() {
      _renamingMarker = true;
      _dragSelectionStart = null;
      _dragSelectionCurrent = null;
    });
    try {
      nextLabel = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Rename Marker'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Marker label',
              ),
              onSubmitted: (String value) => Navigator.of(context).pop(value.trim()),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
      if (mounted) {
        setState(() {
          _renamingMarker = false;
        });
      }
    }
    if (!mounted || nextLabel == null || nextLabel.trim().isEmpty) {
      return;
    }

    final String normalized = nextLabel.trim();
    final List<TimeMarker> updated = _currentMarkersForDataset()
        .map(
          (TimeMarker existing) => _markerReferenceId(existing) == markerId
              ? existing.copyWith(label: normalized)
              : existing,
        )
        .toList(growable: false);
    _setSelectedMarker(marker.copyWith(label: normalized));
    _setDraftMarkersForDataset(updated);
    setState(() {
      widget.params['marker_default_label'] = normalized;
      _hoveredMarkerReferenceId = null;
    });
  }

  Future<void> _showChannelEditPanel(int channelIndex) async {
    if (_interactionMode() != 'edit') {
      return;
    }
    final TimeSeriesData? baseTimeSeries = widget.dataset.timeSeries;
    if (baseTimeSeries == null || baseTimeSeries.channels.isEmpty) {
      return;
    }
    final List<String> baseLabels = baseTimeSeries.channelLabels.length ==
            baseTimeSeries.channelCount
        ? baseTimeSeries.channelLabels
        : List<String>.generate(
            baseTimeSeries.channelCount,
            (int index) => index < baseTimeSeries.channelLabels.length
                ? baseTimeSeries.channelLabels[index]
                : 'Ch ${index + 1}',
            growable: false,
          );
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 980,
              maxHeight: 720,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Edit Channels',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Channel ${channelIndex + 1}: ${baseLabels[channelIndex]}',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ChannelEditConfigEditor(
                      channelLabels: baseLabels,
                      config: _effectiveChannelEditConfig(),
                      initialVisibleChannelIndices: <int>[channelIndex],
                      onChanged: (Map<String, dynamic> config) {
                        setState(() {
                          _draftChannelEditConfig = config;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChannelPositionsDialog(TimeSeriesData timeSeries) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _ChannelPositionsDialog(timeSeries: timeSeries);
      },
    );
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

  bool get _hasChannelEditDraft => _draftChannelEditConfig != null;

  bool get _hasInteractiveArtifactDraft =>
      _draftArtifactExemplars != null ||
      _draftArtifactCandidates != null ||
      _draftArtifactTemplates != null;

  bool get _hasAnyDraftChanges =>
      _hasMarkerDraft || _hasChannelEditDraft || _hasInteractiveArtifactDraft;

  Map<String, dynamic> _effectiveChannelEditConfig() {
    return _draftChannelEditConfig ??
        EditChannelsNodeType.configForDataset(widget.params, widget.dataset.id);
  }

  bool _interactiveArtifactDetectionEnabled() =>
      widget.params['interactiveArtifactDetection'] == true;

  bool _interactiveArtifactWorkflowEnabled() =>
      _interactiveArtifactDetectionEnabled() || _interactiveModeActive();

  bool _interactiveModeActive() => _interactionMode() == 'interactive';

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
      final String? message = widget.onInteractiveArtifactDetectionSaved?.call();
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return;
    }

    final Map<String, dynamic>? draftChannelEditConfig = _draftChannelEditConfig;
    if (draftChannelEditConfig != null) {
      final Map<String, dynamic> normalizedConfig =
          EditChannelsNodeType.configForDataset(
        <String, dynamic>{
          'channelEditsByDataset': <String, dynamic>{
            widget.dataset.id: draftChannelEditConfig,
          },
        },
        widget.dataset.id,
      );
      setState(() {
        EditChannelsNodeType.setConfigForDataset(
          widget.params,
          widget.dataset.id,
          normalizedConfig,
        );
        _draftChannelEditConfig = null;
      });
      widget.onChannelEditsSaved?.call(normalizedConfig);
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
      _draftChannelEditConfig = null;
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
    final ScrollPosition position = _horizontalController.position;
    final double viewportWidth = position.viewportDimension;
    final double scrollableWidth = position.maxScrollExtent + viewportWidth;
    final double pixelsPerSecond = recordingSeconds <= 0
        ? viewportWidth / secondsPerView
        : scrollableWidth / recordingSeconds;
    final double targetStartSeconds = (centerSeconds - (secondsPerView / 2)).clamp(
      0.0,
      math.max(0.0, recordingSeconds - secondsPerView),
    );
    final double targetOffset = targetStartSeconds * pixelsPerSecond;
    _horizontalController.animateTo(
      targetOffset.clamp(
        0.0,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _ensureDefaults() {
    widget.params.putIfAbsent('window_sec', () => 10.0);
    widget.params.remove('gain');
    widget.params.putIfAbsent('preview_bandpass', () => false);
    widget.params.putIfAbsent('preview_low', () => 1.0);
    widget.params.putIfAbsent('preview_high', () => 40.0);
    widget.params.putIfAbsent('marker_mode', () => 'event');
    final String legacyMarkerMode =
        (widget.params['marker_interaction_mode'] ?? 'view').toString();
    widget.params.putIfAbsent(
      'interaction_mode',
      () => widget.params['interactiveArtifactDetection'] == true
          ? 'interactive'
          : legacyMarkerMode == 'edit'
              ? 'edit'
              : 'view',
    );
    widget.params.putIfAbsent('marker_default_label', () => 'new marker');
    widget.params.putIfAbsent('markers', () => <Map<String, dynamic>>[]);
    widget.params.putIfAbsent('channel_colors', () => <String, dynamic>{});
    widget.params.putIfAbsent('marker_list_expanded', () => false);
    widget.params.putIfAbsent('marker_label_expanded', () => <String, dynamic>{});
    widget.params.putIfAbsent('artifact_exemplars_expanded', () => true);
    widget.params.putIfAbsent('artifact_candidates_expanded', () => true);
    widget.params.putIfAbsent('y_scale_uv', () => 100.0);
    widget.params.putIfAbsent('raw_show_data', () => true);
    widget.params.putIfAbsent('raw_show_markers', () => true);
    widget.params.putIfAbsent('raw_remove_dc', () => true);
    widget.params.putIfAbsent('right_panel_collapsed', () => false);
    if (_interactiveArtifactDetectionEnabled() || _interactionMode() == 'interactive') {
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

  double _channelHeight(double viewportHeight, int channelCount) {
    final double spacingFactor = _autoChannelSpacingFactor();
    return math.max(40.0, (viewportHeight / math.max(1, channelCount)) * spacingFactor);
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

  bool _showSignals() {
    return (widget.params['raw_show_data'] as bool?) ?? true;
  }

  bool _showMarkers() {
    return (widget.params['raw_show_markers'] as bool?) ?? true;
  }

  bool _removeDc() {
    return (widget.params['raw_remove_dc'] as bool?) ?? false;
  }

  double _autoChannelSpacingFactor() {
    final double rangeUv = _yScaleUv();
    final double factor = math.sqrt(100.0 / math.max(1.0, rangeUv));
    return factor.clamp(0.75, 2.4);
  }

  bool _rightPanelCollapsed() {
    return (widget.params['right_panel_collapsed'] as bool?) ?? false;
  }

  double _defaultLeftPanelWidth(List<String> labels) {
    double maxWidth = 88;
    for (final String label in labels) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      maxWidth = math.max(maxWidth, painter.width + 38);
    }
    return maxWidth.clamp(88.0, 260.0);
  }

  double _defaultRightPanelWidth(List<TimeMarker> markers) {
    double maxWidth = 188;
    for (final String text in <String>[
      'Current template',
      'Candidate matches',
      'Accepted',
      'Markers',
      'Save and Quit',
      ...markers.take(16).map((TimeMarker marker) => marker.label),
    ]) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      maxWidth = math.max(maxWidth, painter.width + 44);
    }
    return maxWidth.clamp(188.0, 360.0);
  }

  double _resolvedLeftPanelWidth(double defaultWidth) {
    return ((widget.params['left_panel_width'] as num?)?.toDouble() ?? defaultWidth)
        .clamp(88.0, 260.0);
  }

  double _resolvedRightPanelWidth(double defaultWidth) {
    return ((widget.params['right_panel_width'] as num?)?.toDouble() ?? defaultWidth)
        .clamp(188.0, 420.0);
  }

  String _interactionMode() {
    final String mode = (widget.params['interaction_mode'] ?? 'view').toString();
    if (mode == 'interactive') {
      return 'interactive';
    }
    if (mode == 'edit' || mode == 'markers' || mode == 'channels') {
      return 'edit';
    }
    return 'view';
  }

  String _hiddenMarkerType() {
    final String value = (widget.params['marker_mode'] ?? 'event').toString();
    return value == 'artifact' ? 'artifact' : 'event';
  }

  String _defaultMarkerLabel() {
    final String label = (widget.params['marker_default_label'] ?? 'new marker')
        .toString()
        .trim();
    return label.isEmpty ? 'new marker' : label;
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

class _ControlStripDivider extends StatelessWidget {
  const _ControlStripDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 16,
        thickness: 2,
        color: Colors.white.withValues(alpha: 0.22),
      ),
    );
  }
}

class _HoverHighlightFrame extends StatefulWidget {
  const _HoverHighlightFrame({
    required this.child,
    required this.glowColor,
    this.forceHighlighted = false,
  });

  final Widget child;
  final Color glowColor;
  final bool forceHighlighted;

  @override
  State<_HoverHighlightFrame> createState() => _HoverHighlightFrameState();
}

class _HoverHighlightFrameState extends State<_HoverHighlightFrame> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool highlighted = _hovered || widget.forceHighlighted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: highlighted
              ? Colors.yellow.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: highlighted
              ? Border.all(color: Colors.yellow.withValues(alpha: 0.85))
              : null,
          boxShadow: highlighted
              ? <BoxShadow>[
                  BoxShadow(
                    color: widget.glowColor.withValues(alpha: 0.45),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: widget.child,
      ),
    );
  }
}

class _CollapsedSideRail extends StatelessWidget {
  const _CollapsedSideRail({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Center(
              child: Icon(
                icon,
                color: Colors.white70,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelResizeHandle extends StatelessWidget {
  const _PanelResizeHandle({
    required this.onDragUpdate,
    required this.onDoubleTap,
  });

  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onDragUpdate == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onDoubleTap,
        onHorizontalDragUpdate: onDragUpdate == null
            ? null
            : (DragUpdateDetails details) => onDragUpdate!(details.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: 2,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScaleCluster extends StatelessWidget {
  const _ScaleCluster({
    required this.timeSeconds,
    required this.timeOptionsSeconds,
    required this.onTimeSelected,
    required this.rangeUv,
    required this.rangeOptionsUv,
    required this.onRangeSelected,
  });

  final double timeSeconds;
  final List<double> timeOptionsSeconds;
  final ValueChanged<double> onTimeSelected;
  final double rangeUv;
  final List<double> rangeOptionsUv;
  final ValueChanged<double> onRangeSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const Text(
          'Scale:',
          style: TextStyle(color: Colors.white70),
        ),
        _ScalePillMenu<double>(
          label: 'Time',
          currentValue: timeSeconds,
          valueText: '${timeSeconds.toStringAsFixed(0)}s',
          tooltip: 'Time span',
          options: timeOptionsSeconds,
          itemLabelBuilder: (double option) => '${option.toStringAsFixed(0)} s',
          onSelected: onTimeSelected,
        ),
        _ScalePillMenu<double>(
          label: 'Range',
          currentValue: rangeUv,
          valueText: '${rangeUv.toStringAsFixed(0)} uV',
          tooltip: 'Signal range',
          options: rangeOptionsUv,
          itemLabelBuilder: (double option) => '${option.toStringAsFixed(0)} uV',
          onSelected: onRangeSelected,
        ),
        Tooltip(
          message: 'Channel spacing follows signal range automatically',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Text(
              'Spacing: Auto',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScalePillMenu<T> extends StatelessWidget {
  const _ScalePillMenu({
    required this.label,
    required this.currentValue,
    required this.valueText,
    required this.tooltip,
    required this.options,
    required this.itemLabelBuilder,
    required this.onSelected,
  });

  final String label;
  final T currentValue;
  final String valueText;
  final String tooltip;
  final List<T> options;
  final String Function(T value) itemLabelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    void stepByWheel(PointerSignalEvent event) {
      if (event is! PointerScrollEvent || options.isEmpty) {
        return;
      }
      final int currentIndex = options.indexOf(currentValue);
      if (currentIndex < 0) {
        return;
      }
      final int nextIndex = event.scrollDelta.dy > 0
          ? math.min(options.length - 1, currentIndex + 1)
          : math.max(0, currentIndex - 1);
      if (nextIndex != currentIndex) {
        onSelected(options[nextIndex]);
      }
    }

    return Tooltip(
      message: tooltip,
      child: Listener(
        onPointerSignal: stepByWheel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: PopupMenuButton<T>(
            tooltip: '',
            onSelected: onSelected,
            itemBuilder: (BuildContext context) {
              return options.map((T option) {
                return PopupMenuItem<T>(
                  value: option,
                  child: Text(itemLabelBuilder(option)),
                );
              }).toList(growable: false);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  '$label: $valueText',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineToggleOption {
  const _InlineToggleOption({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.leadingGap = 0,
    this.showLeadingDivider = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final double leadingGap;
  final bool showLeadingDivider;
}

class _InlineChoiceOption {
  const _InlineChoiceOption({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
}

class _InlineToggleGroup extends StatelessWidget {
  const _InlineToggleGroup({
    required this.label,
    required this.options,
  });

  final String label;
  final List<_InlineToggleOption> options;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Colors.white70),
        ),
        ...options.map((_InlineToggleOption option) {
          final TextPainter painter = TextPainter(
            text: TextSpan(
              text: option.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();
          final double buttonWidth = painter.width + 40;
          return Padding(
            padding: EdgeInsets.only(left: option.leadingGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (option.showLeadingDivider) ...<Widget>[
                  Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.only(right: 10),
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ],
                SizedBox(
                  width: buttonWidth,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: OutlinedButton(
                      onPressed: option.onPressed,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        minimumSize: Size(buttonWidth, 34),
                        backgroundColor: option.selected
                            ? Colors.white.withValues(alpha: 0.24)
                            : Colors.white.withValues(alpha: 0.04),
                        foregroundColor: option.selected ? Colors.white : Colors.white70,
                        side: BorderSide(
                          color: option.selected
                              ? Colors.white.withValues(alpha: 0.24)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        shape: const StadiumBorder(),
                        splashFactory: NoSplash.splashFactory,
                        overlayColor: Colors.transparent,
                        animationDuration: Duration.zero,
                      ),
                      child: Text(
                        option.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: option.selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _InlineChoiceGroup extends StatelessWidget {
  const _InlineChoiceGroup({
    required this.label,
    required this.options,
  });

  final String label;
  final List<_InlineChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    final String selectedLabel = options.firstWhere(
      (_InlineChoiceOption option) => option.selected,
      orElse: () => options.first,
    ).label;

    return RadioGroup<String>(
      groupValue: selectedLabel,
      onChanged: (String? value) {
        if (value == null) {
          return;
        }
        for (final _InlineChoiceOption option in options) {
          if (option.label == value) {
            option.onPressed();
            break;
          }
        }
      },
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
          ...options.map((_InlineChoiceOption option) {
            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: option.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Radio<String>(
                      value: option.label,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      fillColor: WidgetStateProperty.resolveWith<Color?>(
                        (Set<WidgetState> states) =>
                            option.selected ? Colors.white : Colors.white70,
                      ),
                    ),
                    Text(
                      option.label,
                      style: TextStyle(
                        color: option.selected ? Colors.white : Colors.white70,
                        fontWeight: option.selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ChannelLabelColumn extends StatefulWidget {
  const _ChannelLabelColumn({
    required this.labels,
    required this.colors,
    required this.channelHeight,
    required this.onCycleColor,
    required this.channelEditEnabled,
    required this.onEditChannel,
  });

  final List<String> labels;
  final List<Color> colors;
  final double channelHeight;
  final ValueChanged<int> onCycleColor;
  final bool channelEditEnabled;
  final ValueChanged<int> onEditChannel;

  @override
  State<_ChannelLabelColumn> createState() => _ChannelLabelColumnState();
}

class _ChannelLabelColumnState extends State<_ChannelLabelColumn> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(widget.labels.length, (int index) {
          return SizedBox(
            height: widget.channelHeight,
            child: Row(
              children: <Widget>[
                GestureDetector(
                  onTap: () => widget.onCycleColor(index),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.colors[index],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MouseRegion(
                    cursor: widget.channelEditEnabled
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    onEnter: (_) {
                      if (!widget.channelEditEnabled) {
                        return;
                      }
                      setState(() {
                        _hoveredIndex = index;
                      });
                    },
                    onExit: (_) {
                      if (_hoveredIndex == index) {
                        setState(() {
                          _hoveredIndex = null;
                        });
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      curve: Curves.linear,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      decoration: BoxDecoration(
                        color: widget.channelEditEnabled && _hoveredIndex == index
                            ? Colors.yellow.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: widget.channelEditEnabled && _hoveredIndex == index
                            ? Border.all(
                                color: Colors.yellow.withValues(alpha: 0.85),
                              )
                            : null,
                        boxShadow: widget.channelEditEnabled && _hoveredIndex == index
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: widget.colors[index]
                                      .withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : const <BoxShadow>[],
                      ),
                      child: InkWell(
                        onTap: widget.channelEditEnabled
                            ? () => widget.onEditChannel(index)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        child: Text(
                          widget.labels[index],
                          style: TextStyle(
                            color: widget.channelEditEnabled
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.95),
                            fontSize: 12,
                            fontWeight: widget.channelEditEnabled
                                ? FontWeight.w700
                                : FontWeight.w500,
                            decoration: widget.channelEditEnabled
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationColor: Colors.white70,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
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
    required this.selectedMarkerReferenceId,
  });

  final List<TimeMarker> markers;
  final ValueChanged<TimeMarker> onDelete;
  final ValueChanged<TimeMarker> onFocus;
  final String? selectedMarkerReferenceId;

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) {
      return const Text(
        'No markers placed yet. Switch mode to edit to place markers inside the trace view.',
        style: TextStyle(color: Colors.white70),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: markers.map((TimeMarker marker) {
        final bool isArtifact = marker.markerType == MarkerType.artifact;
        final Color markerColor = _markerDisplayColor(marker);
        final bool selected =
            selectedMarkerReferenceId == markerReferenceIdFor(marker);
        return _HoverHighlightFrame(
          glowColor: markerColor,
          forceHighlighted: selected,
          child: InputChip(
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
            selected: isArtifact || selected,
            selectedColor: markerColor.withValues(alpha: 0.22),
            onPressed: () => onFocus(marker),
            onDeleted: () => onDelete(marker),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _MarkerLabelGroup {
  const _MarkerLabelGroup({
    required this.label,
    required this.markers,
  });

  final String label;
  final List<TimeMarker> markers;
}

class _MarkerSection extends StatelessWidget {
  const _MarkerSection({
    required this.expanded,
    required this.markers,
    required this.labelExpandedMap,
    required this.selectedMarkerReferenceId,
    required this.onToggleLabelExpanded,
    required this.onToggle,
    required this.onDelete,
    required this.onFocus,
  });

  final bool expanded;
  final List<TimeMarker> markers;
  final Map<String, dynamic> labelExpandedMap;
  final String? selectedMarkerReferenceId;
  final void Function(String label, bool expanded) onToggleLabelExpanded;
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
              ..._groupedMarkers().map((_MarkerLabelGroup group) {
                final bool isExpanded =
                    (labelExpandedMap[group.label] as bool?) ?? false;
                final Color groupColor = _markerDisplayColor(group.markers.first);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _HoverHighlightFrame(
                            glowColor: groupColor,
                            child: InkWell(
                              onTap: () =>
                                  onToggleLabelExpanded(group.label, !isExpanded),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      isExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: groupColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        group.label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${group.markers.length}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (isExpanded) ...<Widget>[
                            const SizedBox(height: 8),
                            _MarkerList(
                              markers: group.markers,
                              onDelete: onDelete,
                              onFocus: onFocus,
                              selectedMarkerReferenceId: selectedMarkerReferenceId,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  List<_MarkerLabelGroup> _groupedMarkers() {
    final Map<String, List<TimeMarker>> grouped = <String, List<TimeMarker>>{};
    for (final TimeMarker marker in markers) {
      grouped.putIfAbsent(marker.label, () => <TimeMarker>[]).add(marker);
    }
    return grouped.entries
        .map(
          (MapEntry<String, List<TimeMarker>> entry) => _MarkerLabelGroup(
            label: entry.key,
            markers: entry.value,
          ),
        )
        .toList(growable: false);
  }
}

String markerReferenceIdFor(TimeMarker marker) {
  return '${marker.label}:${marker.onsetMicros}:${marker.durationMicros}:${marker.markerType}';
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
  double extraStrokeWidth = 0.0,
  required String? interactiveStatus,
  required String? interactiveSource,
}) {
  final Paint paint = Paint()
    ..color = color.withValues(alpha: 0.95)
    ..strokeWidth = 2.4 + extraStrokeWidth;
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
    required this.timeSeries,
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
  final TimeSeriesData? timeSeries;
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
            _ArtifactTemplatePreview(
              templates: templates,
              timeSeries: timeSeries,
            ),
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
                  const Color candidateDotColor = Color(0xFFFFD54F);
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
                                  color: candidateDotColor,
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
                  const Color candidateDotColor = Color(0xFFFFD54F);
                  final Color labelColor = _artifactTemplateColor(candidate.label);
                  return InputChip(
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: candidateDotColor,
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
          Expanded(
            child: Text(
              '$title ($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: RichText(
          text: TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: '$label: ',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtifactTemplatePreview extends StatelessWidget {
  const _ArtifactTemplatePreview({
    required this.templates,
    required this.timeSeries,
  });

  final List<ArtifactTemplateSummary> templates;
  final TimeSeriesData? timeSeries;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
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
            'Current template summary',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: templates.map((ArtifactTemplateSummary template) {
                      return SizedBox(
                        width: math.max(132, math.min(180, constraints.maxWidth * 0.72)),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: CustomPaint(
                            painter: _ArtifactTemplateTopomapPainter(
                              template: template,
                              timeSeries: timeSeries,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactTemplateTopomapPainter extends CustomPainter {
  const _ArtifactTemplateTopomapPainter({
    required this.template,
    required this.timeSeries,
  });

  final ArtifactTemplateSummary template;
  final TimeSeriesData? timeSeries;

  @override
  void paint(Canvas canvas, Size size) {
    final List<_ArtifactTemplateTopoPoint> points =
        _artifactTemplateTopoPoints(template, timeSeries);
    if (points.length < 2) {
      _paintTemplateFallbackTrace(canvas, size, template);
      return;
    }

    final double mapTop = 16;
    final double mapHeight = math.max(24, size.height - 28);
    final Offset center = Offset(size.width / 2, mapTop + mapHeight / 2);
    final double radius = math.min(size.width, mapHeight) * 0.42;
    final Rect headRect = Rect.fromCircle(center: center, radius: radius);
    final double maxAbsValue = math.max(
      1e-9,
      points.map((_ArtifactTemplateTopoPoint point) => point.value.abs()).reduce(math.max),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(headRect));
    final int grid = math.max(32, math.min(60, (radius * 2 / 4).round()));
    final double cell = (radius * 2) / grid;
    for (int row = 0; row < grid; row++) {
      for (int column = 0; column < grid; column++) {
        final Offset pixel = Offset(
          center.dx - radius + (column + 0.5) * cell,
          center.dy - radius + (row + 0.5) * cell,
        );
        final Offset normalized = Offset(
          (pixel.dx - center.dx) / radius,
          (pixel.dy - center.dy) / radius,
        );
        if (normalized.distance > 1.0) {
          continue;
        }
        final double value = _interpolatedTemplateTopoValue(points, normalized);
        canvas.drawRect(
          Rect.fromLTWH(
            pixel.dx - cell / 2,
            pixel.dy - cell / 2,
            cell + 0.5,
            cell + 0.5,
          ),
          Paint()..color = _artifactTemplateTopoColor(value / maxAbsValue),
        );
      }
    }
    canvas.restore();

    final Color labelColor = _artifactTemplateColor(template.label);
    final Paint outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.76)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawOval(headRect, outlinePaint);
    _drawMiniHeadLandmarks(canvas, center, radius, outlinePaint);

    for (final _ArtifactTemplateTopoPoint point in points) {
      final Offset projected = center + point.position * radius;
      canvas.drawCircle(
        projected,
        3.0,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.72)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        projected,
        3.0,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final TextPainter titlePainter = TextPainter(
      text: TextSpan(
        text: template.label,
        style: TextStyle(
          color: labelColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          shadows: const <Shadow>[Shadow(blurRadius: 6, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    titlePainter.paint(canvas, const Offset(0, 0));

    final TextPainter detailPainter = TextPainter(
      text: TextSpan(
        text: '${template.exemplarCount} ex • peak GFP',
        style: const TextStyle(color: Colors.white70, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    detailPainter.paint(
      canvas,
      Offset(0, size.height - detailPainter.height),
    );
  }

  @override
  bool shouldRepaint(covariant _ArtifactTemplateTopomapPainter oldDelegate) {
    return oldDelegate.template != template ||
        oldDelegate.timeSeries != timeSeries;
  }
}

class _ArtifactTemplateTopoPoint {
  const _ArtifactTemplateTopoPoint({
    required this.position,
    required this.value,
  });

  final Offset position;
  final double value;
}

List<_ArtifactTemplateTopoPoint> _artifactTemplateTopoPoints(
  ArtifactTemplateSummary template,
  TimeSeriesData? timeSeries,
) {
  final List<List<double>> channels = template.previewChannels;
  if (channels.isEmpty || timeSeries == null) {
    return const <_ArtifactTemplateTopoPoint>[];
  }
  final List<_ResolvedChannelCoordinate> resolvedCoordinates =
      _resolvedChannelCoordinatesForTimeSeries(timeSeries);
  if (resolvedCoordinates.length < 3) {
    return const <_ArtifactTemplateTopoPoint>[];
  }

  return resolvedCoordinates
      .where(
        (_ResolvedChannelCoordinate coordinate) =>
            coordinate.index < channels.length && channels[coordinate.index].isNotEmpty,
      )
      .map((_ResolvedChannelCoordinate coordinate) {
        final List<double> samples = channels[coordinate.index];
        final int peakIndex =
            template.peakGfpPreviewIndex.clamp(0, samples.length - 1);
        return _ArtifactTemplateTopoPoint(
          position: coordinate.position,
          value: samples[peakIndex],
        );
      })
      .toList(growable: false);
}

ChannelCoordinate? _templateCoordinateForLabel(
  Map<String, ChannelCoordinate> coordinates,
  String label,
) {
  final ChannelCoordinate? direct = coordinates[label];
  if (direct != null) {
    return direct;
  }
  final String normalizedLabel = _normalizeTemplateChannelLabel(label);
  for (final MapEntry<String, ChannelCoordinate> entry in coordinates.entries) {
    final String normalizedCoordinateLabel =
        _normalizeTemplateChannelLabel(entry.key);
    if (normalizedCoordinateLabel == normalizedLabel ||
        normalizedLabel.startsWith('$normalizedCoordinateLabel-')) {
      return entry.value;
    }
  }
  return null;
}

String _normalizeTemplateChannelLabel(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');
}

class _ResolvedChannelCoordinate {
  const _ResolvedChannelCoordinate({
    required this.index,
    required this.label,
    required this.coordinate,
    required this.position,
  });

  final int index;
  final String label;
  final ChannelCoordinate coordinate;
  final Offset position;
}

List<_ResolvedChannelCoordinate> _resolvedChannelCoordinatesForTimeSeries(
  TimeSeriesData timeSeries,
) {
  if (timeSeries.channelCoordinates.isEmpty) {
    return const <_ResolvedChannelCoordinate>[];
  }
  double maxRadius = 1.0;
  for (final ChannelCoordinate coordinate in timeSeries.channelCoordinates.values) {
    maxRadius = math.max(
      maxRadius,
      math.sqrt(coordinate.x * coordinate.x + coordinate.y * coordinate.y),
    );
  }
  final List<_ResolvedChannelCoordinate> resolved = <_ResolvedChannelCoordinate>[];
  for (int index = 0; index < timeSeries.channelCount; index++) {
    final String label = index < timeSeries.channelLabels.length
        ? timeSeries.channelLabels[index]
        : 'Ch ${index + 1}';
    final ChannelCoordinate? coordinate = _templateCoordinateForLabel(
      timeSeries.channelCoordinates,
      label,
    );
    if (coordinate == null) {
      continue;
    }
    resolved.add(
      _ResolvedChannelCoordinate(
        index: index,
        label: label,
        coordinate: coordinate,
        position: Offset(coordinate.x / maxRadius, -coordinate.y / maxRadius),
      ),
    );
  }
  return resolved;
}

double _interpolatedTemplateTopoValue(
  List<_ArtifactTemplateTopoPoint> points,
  Offset position,
) {
  double weightedSum = 0.0;
  double weightTotal = 0.0;
  for (final _ArtifactTemplateTopoPoint point in points) {
    final double distance = (position - point.position).distance;
    if (distance < 0.001) {
      return point.value;
    }
    final double weight = 1.0 / math.pow(distance, 2.35);
    weightedSum += point.value * weight;
    weightTotal += weight;
  }
  return weightTotal == 0.0 ? 0.0 : weightedSum / weightTotal;
}

Color _artifactTemplateTopoColor(double normalizedValue) {
  final double value = normalizedValue.clamp(-1.0, 1.0);
  if (value < 0) {
    return Color.lerp(
      const Color(0xFF1E4FA8),
      Colors.white,
      (value + 1.0).clamp(0.0, 1.0),
    )!;
  }
  return Color.lerp(
    Colors.white,
    const Color(0xFFFF5A36),
    value,
  )!;
}

void _drawMiniHeadLandmarks(
  Canvas canvas,
  Offset center,
  double radius,
  Paint outlinePaint,
) {
  final Path nose = Path()
    ..moveTo(center.dx - radius * 0.10, center.dy - radius * 0.98)
    ..lineTo(center.dx, center.dy - radius * 1.12)
    ..lineTo(center.dx + radius * 0.10, center.dy - radius * 0.98);
  canvas.drawPath(nose, outlinePaint);
  canvas.drawArc(
    Rect.fromCenter(
      center: Offset(center.dx - radius * 1.02, center.dy),
      width: radius * 0.18,
      height: radius * 0.38,
    ),
    math.pi / 2,
    math.pi,
    false,
    outlinePaint,
  );
  canvas.drawArc(
    Rect.fromCenter(
      center: Offset(center.dx + radius * 1.02, center.dy),
      width: radius * 0.18,
      height: radius * 0.38,
    ),
    -math.pi / 2,
    math.pi,
    false,
    outlinePaint,
  );
}

void _paintTemplateFallbackTrace(
  Canvas canvas,
  Size size,
  ArtifactTemplateSummary template,
) {
  final List<double> samples = template.previewSamples;
  if (samples.length < 2) {
    final TextPainter painter = TextPainter(
      text: const TextSpan(
        text: 'No template preview',
        style: TextStyle(color: Colors.white54, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    painter.paint(canvas, Offset(0, size.height / 2 - painter.height / 2));
    return;
  }
  final double maxValue = math.max(
    1.0,
    samples.map((double value) => value.abs()).reduce(math.max),
  );
  final double baselineY = size.height / 2;
  final Path path = Path();
  for (int index = 0; index < samples.length; index++) {
    final double x = (index / (samples.length - 1)) * size.width;
    final double y = baselineY - (samples[index] / maxValue) * (size.height * 0.42);
    if (index == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = _artifactTemplateColor(template.label).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
}

class _ChannelPositionsDialog extends StatelessWidget {
  const _ChannelPositionsDialog({
    required this.timeSeries,
  });

  final TimeSeriesData timeSeries;

  @override
  Widget build(BuildContext context) {
    final List<_ResolvedChannelCoordinate> coordinates =
        _resolvedChannelCoordinatesForTimeSeries(timeSeries);
    final String units = coordinates.isEmpty ? '' : coordinates.first.coordinate.units;
    final String coordinateSystem = coordinates.isEmpty
        ? ''
        : coordinates.first.coordinate.coordinateSystem;

    return Dialog(
      backgroundColor: const Color(0xFF10151D),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 1120,
          maxHeight: 760,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Channel positions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${coordinates.length}/${timeSeries.channelCount} channels mapped'
                '${units.isEmpty ? '' : ' • $units'}'
                '${coordinateSystem.isEmpty ? '' : ' • $coordinateSystem'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: coordinates.isEmpty
                    ? const Center(
                        child: Text(
                          'No channel coordinates are available for this dataset yet.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final bool stacked = constraints.maxWidth < 920;
                          final Widget topomap = _ChannelPositionsTopomap(
                            coordinates: coordinates,
                          );
                          final Widget table = _ChannelPositionsTable(
                            coordinates: coordinates,
                          );
                          if (stacked) {
                            return Column(
                              children: <Widget>[
                                SizedBox(
                                  height: math.min(320, constraints.maxHeight * 0.44),
                                  child: topomap,
                                ),
                                const SizedBox(height: 12),
                                Expanded(child: table),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(
                                width: math.min(380, constraints.maxWidth * 0.38),
                                child: topomap,
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: table),
                            ],
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelPositionsTopomap extends StatelessWidget {
  const _ChannelPositionsTopomap({
    required this.coordinates,
  });

  final List<_ResolvedChannelCoordinate> coordinates;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(12),
      child: CustomPaint(
        painter: _ChannelPositionHeadPainter(
          coordinates: coordinates,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ChannelPositionHeadPainter extends CustomPainter {
  const _ChannelPositionHeadPainter({
    required this.coordinates,
  });

  final List<_ResolvedChannelCoordinate> coordinates;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = side * 0.40;
    final Rect headRect = Rect.fromCircle(center: center, radius: radius);
    final Paint outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawOval(headRect, outlinePaint);
    _drawMiniHeadLandmarks(canvas, center, radius, outlinePaint);

    double minZ = coordinates.first.coordinate.z;
    double maxZ = minZ;
    for (final _ResolvedChannelCoordinate coordinate in coordinates) {
      minZ = math.min(minZ, coordinate.coordinate.z);
      maxZ = math.max(maxZ, coordinate.coordinate.z);
    }

    for (final _ResolvedChannelCoordinate coordinate in coordinates) {
      final Offset projected = center + coordinate.position * radius;
      final Color fillColor = _coordinateAxisColor(
        coordinate.coordinate.z,
        minZ,
        maxZ,
        const Color(0xFFF3D94C),
        const Color(0xFF2F7DFF),
      );
      canvas.drawCircle(
        projected,
        5.0,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        projected,
        5.0,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.78)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );

      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: coordinate.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            shadows: <Shadow>[Shadow(blurRadius: 6, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 88);
      textPainter.paint(
        canvas,
        projected + const Offset(6, -8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChannelPositionHeadPainter oldDelegate) {
    return oldDelegate.coordinates != coordinates;
  }
}

class _ChannelPositionsTable extends StatelessWidget {
  const _ChannelPositionsTable({
    required this.coordinates,
  });

  final List<_ResolvedChannelCoordinate> coordinates;

  @override
  Widget build(BuildContext context) {
    double minX = coordinates.first.coordinate.x;
    double maxX = minX;
    double minY = coordinates.first.coordinate.y;
    double maxY = minY;
    double minZ = coordinates.first.coordinate.z;
    double maxZ = minZ;
    for (final _ResolvedChannelCoordinate coordinate in coordinates) {
      minX = math.min(minX, coordinate.coordinate.x);
      maxX = math.max(maxX, coordinate.coordinate.x);
      minY = math.min(minY, coordinate.coordinate.y);
      maxY = math.max(maxY, coordinate.coordinate.y);
      minZ = math.min(minZ, coordinate.coordinate.z);
      maxZ = math.max(maxZ, coordinate.coordinate.z);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'XYZ coordinates',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'X: left-right • Y: posterior-anterior • Z: inferior-superior',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          const _CoordinateTableHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: coordinates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (BuildContext context, int index) {
                final _ResolvedChannelCoordinate coordinate = coordinates[index];
                return Row(
                  children: <Widget>[
                    SizedBox(
                      width: 118,
                      child: Text(
                        coordinate.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CoordinateValueCell(
                        value: coordinate.coordinate.x,
                        minValue: minX,
                        maxValue: maxX,
                        lowColor: const Color(0xFF37E0FF),
                        highColor: const Color(0xFFFF5A36),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CoordinateValueCell(
                        value: coordinate.coordinate.y,
                        minValue: minY,
                        maxValue: maxY,
                        lowColor: const Color(0xFFE945FF),
                        highColor: const Color(0xFF43E36E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CoordinateValueCell(
                        value: coordinate.coordinate.z,
                        minValue: minZ,
                        maxValue: maxZ,
                        lowColor: const Color(0xFFF3D94C),
                        highColor: const Color(0xFF2F7DFF),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinateTableHeader extends StatelessWidget {
  const _CoordinateTableHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        SizedBox(
          width: 118,
          child: Text(
            'Channel',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'X',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Y',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Z',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _CoordinateValueCell extends StatelessWidget {
  const _CoordinateValueCell({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.lowColor,
    required this.highColor,
  });

  final double value;
  final double minValue;
  final double maxValue;
  final Color lowColor;
  final Color highColor;

  @override
  Widget build(BuildContext context) {
    final Color background = _coordinateAxisColor(
      value,
      minValue,
      maxValue,
      lowColor,
      highColor,
    );
    final Brightness brightness =
        ThemeData.estimateBrightnessForColor(background);
    final Color textColor =
        brightness == Brightness.dark ? Colors.white : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value.toStringAsFixed(1),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _coordinateAxisColor(
  double value,
  double minValue,
  double maxValue,
  Color lowColor,
  Color highColor,
) {
  final double normalized = maxValue <= minValue
      ? 0.5
      : ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
  return Color.lerp(lowColor, highColor, normalized)!.withValues(alpha: 0.92);
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
                      left: (second * pixelsPerSecond) - offset - 22,
                      top: 0,
                      child: SizedBox(
                        width: 44,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              width: 1,
                              height: 8,
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${second}s',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
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

class _VisibleMarkerPaintData {
  const _VisibleMarkerPaintData({
    required this.marker,
    required this.label,
    required this.referenceId,
    required this.color,
    required this.complementColor,
    required this.x,
    required this.endX,
    required this.interactiveStatus,
    required this.interactiveSource,
  });

  final TimeMarker marker;
  final String label;
  final String referenceId;
  final Color color;
  final Color complementColor;
  final double x;
  final double endX;
  final String? interactiveStatus;
  final String? interactiveSource;

  bool get hasDuration => marker.durationMicros > 0;
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
    required this.removeDc,
    required this.colors,
    required this.markers,
    this.selectionStartX,
    this.selectionEndX,
    this.hoveredMarkerReferenceId,
    this.selectedMarkerReferenceId,
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
  final bool removeDc;
  final List<Color> colors;
  final List<TimeMarker> markers;
  final double? selectionStartX;
  final double? selectionEndX;
  final String? hoveredMarkerReferenceId;
  final String? selectedMarkerReferenceId;
  final double horizontalOffset;
  final double verticalOffset;
  final double viewportWidth;
  final double viewportHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double startTime = horizontalOffset / pixelsPerSecond;
    final double endTime = (horizontalOffset + viewportWidth) / pixelsPerSecond;
    final double sampleToPixel = sampleRate <= 0 ? 0.0 : pixelsPerSecond / sampleRate;
    final double microsToPixel = pixelsPerSecond / 1000000.0;
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
    final Paint rangePaint = Paint()..style = PaintingStyle.fill;
    final Paint signalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Paint overlaySignalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9;

    final double firstGridSecond = startTime.floorToDouble();
    for (double second = firstGridSecond; second <= endTime + 1; second += 1) {
      final double x = second * pixelsPerSecond;
      canvas.drawLine(
        Offset(x, verticalOffset),
        Offset(x, verticalOffset + viewportHeight),
        gridPaint,
      );
    }

    final List<_VisibleMarkerPaintData> visibleMarkers = <_VisibleMarkerPaintData>[];
    for (final TimeMarker marker in markers) {
      final double x = marker.onsetMicros * microsToPixel;
      final double markerEndX =
          (marker.onsetMicros + marker.durationMicros) * microsToPixel;
      if (markerEndX < horizontalOffset - 24 ||
          x > horizontalOffset + viewportWidth + 24) {
        continue;
      }
      final Color markerColor = _markerDisplayColor(marker);
      visibleMarkers.add(
        _VisibleMarkerPaintData(
          marker: marker,
          label: marker.label,
          referenceId: markerReferenceIdFor(marker),
          color: markerColor,
          complementColor: _complementColor(markerColor),
          x: x,
          endX: markerEndX,
          interactiveStatus:
              marker.attributes['brainstory.artifactStatus']?.toString(),
          interactiveSource:
              marker.attributes['brainstory.artifactSource']?.toString(),
        ),
      );
      if (marker.durationMicros > 0) {
        rangePaint.color = markerColor.withValues(alpha: 0.24);
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
    }

    if (showSignals) {
      final double verticalScale = channelHeight * 0.35;
      final double pixelsPerUv = verticalScale / math.max(1.0, yScaleUv);
      final List<_VisibleMarkerPaintData> durationMarkers = visibleMarkers
          .where((_VisibleMarkerPaintData marker) => marker.hasDuration)
          .toList(growable: false);
      final int visibleChannelCount =
          lastChannel >= firstChannel ? (lastChannel - firstChannel + 1) : 0;
      final int overlayMarkerLimit = visibleChannelCount <= 0
          ? 0
          : math.max(1, 96 ~/ visibleChannelCount);
      final List<_VisibleMarkerPaintData> overlayMarkers =
          durationMarkers.length <= overlayMarkerLimit
              ? durationMarkers
              : durationMarkers.take(overlayMarkerLimit).toList(growable: false);
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

        double dcOffset = 0;
        if (removeDc) {
          dcOffset = samples[startSample];
        }

        final Path path = Path();
        final int visibleSampleCount = endSample - startSample;
        final int stride = math.max(
          1,
          (visibleSampleCount / math.max(1.0, viewportWidth * 2)).ceil(),
        );
        for (int sampleIndex = startSample; sampleIndex < endSample; sampleIndex += stride) {
          final double x = sampleIndex * sampleToPixel;
          final double y = centerY - ((samples[sampleIndex] - dcOffset) * pixelsPerUv);
          if (sampleIndex == startSample) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        if ((endSample - 1) > startSample) {
          final int lastSampleIndex = endSample - 1;
          path.lineTo(
            lastSampleIndex * sampleToPixel,
            centerY - ((samples[lastSampleIndex] - dcOffset) * pixelsPerUv),
          );
        }

        signalPaint.color = colors[channelIndex];
        canvas.drawPath(path, signalPaint);

        for (final _VisibleMarkerPaintData marker in overlayMarkers) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTRB(
              marker.x,
              centerY - (channelHeight * 0.48),
              math.max(marker.x + 1, marker.endX),
              centerY + (channelHeight * 0.48),
            ),
          );
          overlaySignalPaint.color = marker.complementColor;
          canvas.drawPath(path, overlaySignalPaint);
          canvas.restore();
        }
      }
    }

    for (final _VisibleMarkerPaintData marker in visibleMarkers) {
      final bool hovered = hoveredMarkerReferenceId == marker.referenceId;
      final bool selected = selectedMarkerReferenceId == marker.referenceId;
      final bool emphasized = hovered || selected;
      _drawMarkerGuideLine(
        canvas: canvas,
        x: marker.x,
        top: verticalOffset,
        bottom: verticalOffset + viewportHeight,
        color: marker.color,
        extraStrokeWidth: emphasized ? 1.2 : 0.0,
        interactiveStatus: marker.interactiveStatus,
        interactiveSource: marker.interactiveSource,
      );
      if (marker.hasDuration) {
        _drawMarkerGuideLine(
          canvas: canvas,
          x: marker.endX,
          top: verticalOffset,
          bottom: verticalOffset + viewportHeight,
          color: marker.color,
          extraStrokeWidth: emphasized ? 1.2 : 0.0,
          interactiveStatus: marker.interactiveStatus,
          interactiveSource: marker.interactiveSource,
        );
      }
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: TextStyle(
            color: marker.color,
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
      if (emphasized) {
        final Rect highlightRect = Rect.fromLTWH(
          marker.x,
          verticalOffset + 2,
          textPainter.width + 10,
          textPainter.height + 6,
        );
        final RRect highlightRRect = RRect.fromRectAndRadius(
          highlightRect,
          const Radius.circular(6),
        );
        canvas.drawRRect(
          highlightRRect,
          Paint()
            ..color = Colors.yellow.withValues(alpha: 0.18)
            ..style = PaintingStyle.fill,
        );
        canvas.drawRRect(
          highlightRRect,
          Paint()
            ..color = Colors.yellow.withValues(alpha: 0.9)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
      }
      textPainter.paint(canvas, Offset(marker.x + 4, verticalOffset + 4));
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
        oldDelegate.removeDc != removeDc ||
        oldDelegate.markers != markers ||
        oldDelegate.colors != colors ||
        oldDelegate.selectionStartX != selectionStartX ||
        oldDelegate.selectionEndX != selectionEndX ||
        oldDelegate.hoveredMarkerReferenceId != hoveredMarkerReferenceId ||
        oldDelegate.horizontalOffset != horizontalOffset ||
        oldDelegate.verticalOffset != verticalOffset ||
        oldDelegate.viewportWidth != viewportWidth ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}
