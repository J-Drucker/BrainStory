import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/add_remove_markers_node.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/channel_marker_edit_config_editor.dart';
import '../nodes/edit_channels_node.dart';
import '../nodes/interactive_artifact_detection_node.dart';
import 'artifact_template_preview.dart';
import 'channel_positions_dialog.dart';

class RawSignalBrowser extends StatefulWidget {
  const RawSignalBrowser({
    super.key,
    required this.dataset,
    required this.params,
    this.onChanged,
    this.onPersistDrafts,
    this.onQuit,
  });

  final Dataset dataset;
  final Map<String, dynamic> params;
  final VoidCallback? onChanged;
  final Future<void> Function(ViewerDraftSaveRequest request)? onPersistDrafts;
  final VoidCallback? onQuit;

  @override
  State<RawSignalBrowser> createState() => _RawSignalBrowserState();
}

class ViewerDraftSaveRequest {
  const ViewerDraftSaveRequest({
    this.markerEdits,
    this.channelEditConfig,
    this.interactiveArtifactParams,
    this.runAfterSave = false,
  });

  final List<Map<String, dynamic>>? markerEdits;
  final Map<String, dynamic>? channelEditConfig;
  final Map<String, dynamic>? interactiveArtifactParams;
  final bool runAfterSave;

  bool get hasMarkerEdits => markerEdits != null;
  bool get hasChannelEdits => channelEditConfig != null;
  bool get hasInteractiveArtifactEdits => interactiveArtifactParams != null;
}

class _ChannelDisplayRow {
  const _ChannelDisplayRow({
    required this.sourceIndex,
    required this.label,
    required this.samples,
    required this.removed,
  });

  final int sourceIndex;
  final String label;
  final List<double> samples;
  final bool removed;
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
  static const List<double> _channelSpacingOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];
  static const double _collapsedRailWidth = 28;

  late final FocusNode _focusNode;
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
  String? _lastPersistedDraftFingerprint;
  Offset? _dragSelectionStart;
  Offset? _dragSelectionCurrent;
  Offset? _dragSelectionGlobal;
  bool _artifactDragActive = false;
  String? _hoveredMarkerReferenceId;
  String? _viewIdentity;
  bool _renamingMarker = false;
  bool _draftSummaryExpanded = true;
  _SavedChangesSummary? _savedChangesSummary;
  double _lastTraceViewportWidth = 180;
  bool _traceViewportSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _verticalController = ScrollController(keepScrollOffset: false);
    _horizontalController = ScrollController(keepScrollOffset: false);
    _viewIdentity = _currentViewIdentity();
    _ensureDefaults();
    _scheduleViewportReset();
  }

  @override
  void didUpdateWidget(covariant RawSignalBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureDefaults();
    final String nextIdentity = _currentViewIdentity();
    if (_viewIdentity != nextIdentity) {
      _viewIdentity = nextIdentity;
      _draftMarkers = null;
      _draftChannelEditConfig = null;
      _lastPersistedDraftFingerprint = null;
      _scheduleViewportReset();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
        body:
            'Run an Import or signal-processing path upstream of this visualization node first.',
      );
    }

    final List<_ChannelDisplayRow> channelRows = _channelDisplayRows(
      timeSeries,
    );
    final List<List<double>> channels = channelRows
        .map(((_ChannelDisplayRow row) => row.samples))
        .toList(growable: false);
    final List<String> labels = channelRows
        .map(((_ChannelDisplayRow row) => row.label))
        .toList(growable: false);
    final List<bool> removedRows = channelRows
        .map(((_ChannelDisplayRow row) => row.removed))
        .toList(growable: false);
    final List<Color> baseChannelColors = _channelColors(
      timeSeries.channelCount,
    );
    final List<Color> channelColors = channelRows
        .map(((_ChannelDisplayRow row) => baseChannelColors[row.sourceIndex]))
        .toList(growable: false);
    final int channelCount = channelRows.length;
    final double durationSeconds =
        timeSeries.sampleCount / timeSeries.sampleRate;
    final bool showSignals = _showSignals();
    final bool showMarkers = _showMarkers();
    final bool removeDc = _removeDc();
    final bool hideSignals = !showSignals;
    final bool interactiveArtifactDetection =
        _interactiveArtifactDetectionEnabled();
    final bool markerEditingEnabled = _markerEditingEnabled();
    final bool interactiveMatchingEnabled = _interactiveMatchingEnabled();
    final List<TimeMarker> markers = !showMarkers
        ? const <TimeMarker>[]
        : interactiveArtifactDetection
        ? _interactiveDisplayMarkers(timeSeries)
        : _currentMarkersForDataset();

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _focusNode.requestFocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool rightCollapsed = _rightPanelCollapsed();
                  final double defaultLabelWidth = _defaultLeftPanelWidth(
                    labels,
                  );
                  final double defaultSidePanelWidth = _defaultRightPanelWidth(
                    markers,
                  );
                  final double labelWidth = hideSignals
                      ? 0
                      : _resolvedLeftPanelWidth(defaultLabelWidth);
                  final double sidePanelWidth = rightCollapsed
                      ? _collapsedRailWidth
                      : _resolvedRightPanelWidth(defaultSidePanelWidth);
                  const double traceContainerInset = 10;
                  const double canvasSideChromeWidth = 20;
                  final double leftPaneWidth = math.max(
                    260,
                    constraints.maxWidth -
                        sidePanelWidth -
                        canvasSideChromeWidth,
                  );
                  final double leftContentWidth = math.max(
                    180,
                    leftPaneWidth - (traceContainerInset * 2),
                  );
                  final double traceViewportWidth = math.max(
                    180,
                    leftContentWidth - labelWidth - (hideSignals ? 0 : 16),
                  );
                  final double secondsPerView =
                      (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
                  _syncTraceViewportWidth(
                    nextWidth: traceViewportWidth,
                    secondsPerView: secondsPerView,
                  );
                  final double effectiveViewportWidth = traceViewportWidth;
                  final double pixelsPerSecond =
                      effectiveViewportWidth / secondsPerView;
                  final double totalWidth = math.max(
                    effectiveViewportWidth,
                    durationSeconds * pixelsPerSecond,
                  );
                  const double axisHeight = 26;
                  const double timelineHeight = 28;
                  const double bottomChromeHeight =
                      axisHeight + timelineHeight + 12;
                  final double traceAreaHeight = math.max(
                    140,
                    constraints.maxHeight - bottomChromeHeight - 48,
                  );
                  final double totalHeight = hideSignals
                      ? traceAreaHeight
                      : math.max(
                          traceAreaHeight,
                          _channelHeight(traceAreaHeight, channelCount) *
                              channelCount,
                        );

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            _buildControlBar(
                              sampleRate: timeSeries.sampleRate,
                              channelCount: channelCount,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Listener(
                                key: const ValueKey<String>(
                                  'raw-trace-viewport',
                                ),
                                onPointerSignal: _handleTracePointerSignal,
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
                                          width: leftContentWidth,
                                          height: totalHeight,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              if (!hideSignals)
                                                SizedBox(
                                                  width: labelWidth,
                                                  child: _ChannelLabelColumn(
                                                    labels: labels,
                                                    colors: channelColors,
                                                    removed: removedRows,
                                                    channelHeight:
                                                        _channelHeight(
                                                          traceAreaHeight,
                                                          channelCount,
                                                        ),
                                                    onCycleColor:
                                                        _cycleChannelColor,
                                                    channelEditEnabled:
                                                        markerEditingEnabled,
                                                    onEditChannel:
                                                        (
                                                          int rowIndex,
                                                        ) => _showChannelEditPanel(
                                                          channelRows[rowIndex]
                                                              .sourceIndex,
                                                        ),
                                                  ),
                                                ),
                                              if (!hideSignals)
                                                const SizedBox(width: 4),
                                              if (!hideSignals)
                                                _PanelResizeHandle(
                                                  onDoubleTap: () =>
                                                      setState(() {
                                                        widget.params.remove(
                                                          'left_panel_width',
                                                        );
                                                      }),
                                                  onDragUpdate: (double delta) {
                                                    _updateParam(
                                                      'left_panel_width',
                                                      (_resolvedLeftPanelWidth(
                                                                defaultLabelWidth,
                                                              ) +
                                                              delta)
                                                          .clamp(88.0, 260.0),
                                                    );
                                                  },
                                                ),
                                              if (!hideSignals)
                                                const SizedBox(width: 4),
                                              Expanded(
                                                child: Scrollbar(
                                                  controller:
                                                      _horizontalController,
                                                  thumbVisibility: true,
                                                  notificationPredicate:
                                                      (
                                                        ScrollNotification
                                                        notification,
                                                      ) =>
                                                          notification
                                                              .metrics
                                                              .axis ==
                                                          Axis.horizontal,
                                                  child: SingleChildScrollView(
                                                    controller:
                                                        _horizontalController,
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: MouseRegion(
                                                      onHover:
                                                          (
                                                            PointerHoverEvent
                                                            details,
                                                          ) {
                                                            if (!markerEditingEnabled) {
                                                              if (_hoveredMarkerReferenceId !=
                                                                  null) {
                                                                setState(() {
                                                                  _hoveredMarkerReferenceId =
                                                                      null;
                                                                });
                                                              }
                                                              return;
                                                            }
                                                            final TimeMarker?
                                                            hoveredMarker =
                                                                _markerAtLabelPosition(
                                                                  details
                                                                      .localPosition,
                                                                  pixelsPerSecond,
                                                                );
                                                            final String?
                                                            nextId =
                                                                hoveredMarker ==
                                                                    null
                                                                ? null
                                                                : _markerReferenceId(
                                                                    hoveredMarker,
                                                                  );
                                                            if (nextId !=
                                                                _hoveredMarkerReferenceId) {
                                                              setState(() {
                                                                _hoveredMarkerReferenceId =
                                                                    nextId;
                                                              });
                                                            }
                                                          },
                                                      onExit: (_) {
                                                        if (_hoveredMarkerReferenceId !=
                                                            null) {
                                                          setState(() {
                                                            _hoveredMarkerReferenceId =
                                                                null;
                                                          });
                                                        }
                                                      },
                                                      child: GestureDetector(
                                                        behavior:
                                                            HitTestBehavior
                                                                .opaque,
                                                        onTapDown: null,
                                                        onPanStart:
                                                            markerEditingEnabled
                                                            ? (
                                                                DragStartDetails
                                                                details,
                                                              ) {
                                                                _artifactDragActive =
                                                                    interactiveMatchingEnabled &&
                                                                    !HardwareKeyboard
                                                                        .instance
                                                                        .isShiftPressed;
                                                                if (_artifactDragActive) {
                                                                  _handleArtifactDragStart(
                                                                    details
                                                                        .localPosition,
                                                                    details
                                                                        .globalPosition,
                                                                  );
                                                                } else {
                                                                  _handleMarkerDragStart(
                                                                    details
                                                                        .localPosition,
                                                                  );
                                                                }
                                                              }
                                                            : null,
                                                        onPanUpdate:
                                                            markerEditingEnabled
                                                            ? (
                                                                DragUpdateDetails
                                                                details,
                                                              ) {
                                                                if (_artifactDragActive) {
                                                                  _handleArtifactDragUpdate(
                                                                    details
                                                                        .localPosition,
                                                                    details
                                                                        .globalPosition,
                                                                  );
                                                                } else {
                                                                  _handleMarkerDragUpdate(
                                                                    details
                                                                        .localPosition,
                                                                  );
                                                                }
                                                              }
                                                            : null,
                                                        onPanEnd:
                                                            markerEditingEnabled
                                                            ? (
                                                                DragEndDetails
                                                                details,
                                                              ) {
                                                                final bool
                                                                artifactDrag =
                                                                    _artifactDragActive;
                                                                _artifactDragActive =
                                                                    false;
                                                                if (artifactDrag) {
                                                                  _handleArtifactDragEnd(
                                                                    pixelsPerSecond,
                                                                  );
                                                                } else {
                                                                  _handleMarkerDragEnd(
                                                                    pixelsPerSecond,
                                                                  );
                                                                }
                                                              }
                                                            : null,
                                                        onTapUp:
                                                            markerEditingEnabled
                                                            ? (
                                                                TapUpDetails
                                                                details,
                                                              ) {
                                                                _handleMarkerTapOrRename(
                                                                  details
                                                                      .localPosition,
                                                                  pixelsPerSecond,
                                                                );
                                                              }
                                                            : null,
                                                        child: SizedBox(
                                                          width: totalWidth,
                                                          height: totalHeight,
                                                          child: RepaintBoundary(
                                                            child: AnimatedBuilder(
                                                              animation: Listenable.merge(<
                                                                Listenable
                                                              >[
                                                                _horizontalController,
                                                                _verticalController,
                                                              ]),
                                                              builder:
                                                                  (
                                                                    BuildContext
                                                                    context,
                                                                    Widget?
                                                                    child,
                                                                  ) {
                                                                    return CustomPaint(
                                                                      painter: _RawSignalPainter(
                                                                        channels:
                                                                            channels,
                                                                        channelLabels:
                                                                            labels,
                                                                        sampleCount:
                                                                            timeSeries.sampleCount,
                                                                        sampleRate:
                                                                            timeSeries.sampleRate,
                                                                        channelHeight: _channelHeight(
                                                                          traceAreaHeight,
                                                                          channelCount,
                                                                        ),
                                                                        pixelsPerSecond:
                                                                            pixelsPerSecond,
                                                                        yScaleUv:
                                                                            _yScaleUv(),
                                                                        showSignals:
                                                                            showSignals,
                                                                        removeDc:
                                                                            removeDc,
                                                                        colors:
                                                                            channelColors,
                                                                        removedRows:
                                                                            removedRows,
                                                                        markers:
                                                                            markers,
                                                                        selectionStartX:
                                                                            _dragSelectionStart?.dx,
                                                                        selectionEndX:
                                                                            _dragSelectionCurrent?.dx,
                                                                        hoveredMarkerReferenceId:
                                                                            _hoveredMarkerReferenceId,
                                                                        horizontalOffset:
                                                                            _horizontalController.hasClients
                                                                            ? _horizontalController.offset
                                                                            : 0.0,
                                                                        verticalOffset:
                                                                            _verticalController.hasClients
                                                                            ? _verticalController.offset
                                                                            : 0.0,
                                                                        viewportWidth:
                                                                            effectiveViewportWidth,
                                                                        viewportHeight:
                                                                            traceAreaHeight,
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
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: traceContainerInset,
                              ),
                              child: Row(
                                children: <Widget>[
                                  if (!hideSignals) SizedBox(width: labelWidth),
                                  if (!hideSignals) const SizedBox(width: 4),
                                  if (!hideSignals) const SizedBox(width: 8),
                                  if (!hideSignals) const SizedBox(width: 4),
                                  Expanded(
                                    child: SizedBox(
                                      width: effectiveViewportWidth,
                                      child: _TimeAxisBar(
                                        controller: _horizontalController,
                                        pixelsPerSecond: pixelsPerSecond,
                                        viewportWidth: effectiveViewportWidth,
                                        durationSeconds: durationSeconds,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: traceContainerInset,
                              ),
                              child: Row(
                                children: <Widget>[
                                  if (!hideSignals) SizedBox(width: labelWidth),
                                  if (!hideSignals) const SizedBox(width: 4),
                                  if (!hideSignals) const SizedBox(width: 8),
                                  if (!hideSignals) const SizedBox(width: 4),
                                  Expanded(
                                    child: SizedBox(
                                      width: effectiveViewportWidth,
                                      child: _TimelineBar(
                                        controller: _horizontalController,
                                        totalWidth: totalWidth,
                                        viewportWidth: effectiveViewportWidth,
                                        durationSeconds: durationSeconds,
                                      ),
                                    ),
                                  ),
                                ],
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
                                  (_resolvedRightPanelWidth(
                                            defaultSidePanelWidth,
                                          ) -
                                          delta)
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
                                onTap: () => _updateParam(
                                  'right_panel_collapsed',
                                  false,
                                ),
                              )
                            : _buildInfoPanel(
                                interactiveArtifactDetection:
                                    interactiveArtifactDetection,
                                markers: markers,
                                pixelsPerSecond: pixelsPerSecond,
                                onCollapse: () =>
                                    _updateParam('right_panel_collapsed', true),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar({
    required double sampleRate,
    required int channelCount,
  }) {
    final bool interactiveArtifactDetection =
        _interactiveArtifactDetectionEnabled();
    final double windowSeconds =
        (widget.params['window_sec'] as num?)?.toDouble() ?? 10.0;
    final bool showSignals = _showSignals();
    final bool showMarkers = _showMarkers();
    final bool removeDc = _removeDc();
    final double spacingFactor = _channelSpacingFactor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TextButton.icon(
              onPressed: () => _showChannelMarkerEditPanel(
                initialTab: ChannelMarkerEditTab.channels,
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit channels'),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
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
                  onPressed: () =>
                      _updateParam('raw_show_markers', !showMarkers),
                ),
              ],
            ),
            const _ControlStripDivider(),
            _InlineToggleButton(
              label: 'Remove DC',
              selected: removeDc,
              onPressed: () => _updateParam('raw_remove_dc', !removeDc),
            ),
            const _ControlStripDivider(),
            _InlineChoiceGroup(
              label: 'Mode:',
              options: <_InlineChoiceOption>[
                _InlineChoiceOption(
                  label: 'view',
                  selected: _currentMode() == 'view',
                  onPressed: () => _setMode('view'),
                ),
                _InlineChoiceOption(
                  label: 'edit',
                  selected: _currentMode() == 'edit',
                  onPressed: () => _setMode('edit'),
                ),
              ],
            ),
            if (interactiveArtifactDetection)
              Text(
                _interactiveMatchingEnabled()
                    ? 'Drag to label blink • Alt+drag for other artifacts • Shift+drag for markers'
                    : 'Shift+drag adds marker ranges',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            const _ControlStripDivider(),
            _ScaleCluster(
              timeSeconds: windowSeconds,
              timeOptionsSeconds: _timeSpanOptionsSec,
              onTimeSelected: (double value) =>
                  _updateParam('window_sec', value),
              rangeUv: _yScaleUv(),
              rangeOptionsUv: _yScaleOptionsUv,
              onRangeSelected: (double value) =>
                  _updateParam('y_scale_uv', value),
              spacingFactor: spacingFactor,
              spacingOptions: _channelSpacingOptions,
              onSpacingSelected: (double value) =>
                  _updateParam('channel_spacing_factor', value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoPanel({
    required bool interactiveArtifactDetection,
    required List<TimeMarker> markers,
    required double pixelsPerSecond,
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
                icon: const Icon(Icons.chevron_right, color: Colors.white70),
              ),
            ),
            if (_hasAnyDraftChanges) ...<Widget>[
              _buildDraftSummary(interactiveArtifactDetection),
              const SizedBox(height: 10),
              _buildDraftActions(interactiveArtifactDetection),
              const SizedBox(height: 10),
            ] else if (widget.onQuit != null) ...<Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: widget.onQuit,
                  child: const Text('Quit'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_savedChangesSummary != null) ...<Widget>[
              Divider(color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 6),
              _buildSavedChangesSummary(_savedChangesSummary!),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (interactiveArtifactDetection) ...<Widget>[
                      _InteractiveArtifactReviewSection(
                        labelChoices: InteractiveArtifactDetectionNodeType
                            .supportedLabels,
                        channelLabels:
                            widget.dataset.timeSeries?.channelLabels ??
                            const <String>[],
                        channelCoordinates:
                            widget.dataset.timeSeries?.channelCoordinates ??
                            const <String, ChannelCoordinate>{},
                        pixelsPerSecond: pixelsPerSecond,
                        exemplarsExpanded:
                            (widget.params['artifact_exemplars_expanded']
                                as bool?) ??
                            true,
                        candidatesExpanded:
                            (widget.params['artifact_candidates_expanded']
                                as bool?) ??
                            true,
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
                        onUndoAccepted:
                            _undoAcceptedInteractiveArtifactCandidate,
                        onAcceptAll: _acceptAllInteractiveArtifactCandidates,
                        onFocusExemplar: (ArtifactExemplarData exemplar) {
                          _jumpToTimeRange(
                            onsetMicros: exemplar.onsetMicros,
                            durationMicros: exemplar.durationMicros,
                          );
                        },
                        onFocusPendingCandidate:
                            (ArtifactCandidateData candidate) {
                              _jumpToTimeRange(
                                onsetMicros: candidate.onsetMicros,
                                durationMicros: candidate.durationMicros,
                              );
                            },
                        onFocusAcceptedCandidate:
                            (ArtifactCandidateData candidate) {
                              _jumpToTimeRange(
                                onsetMicros: candidate.onsetMicros,
                                durationMicros: candidate.durationMicros,
                              );
                            },
                        onToggleExemplars: (bool expanded) => _updateParam(
                          'artifact_exemplars_expanded',
                          expanded,
                        ),
                        onToggleCandidates: (bool expanded) => _updateParam(
                          'artifact_candidates_expanded',
                          expanded,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _MarkerSection(
                      expanded:
                          (widget.params['marker_list_expanded'] as bool?) ??
                          false,
                      markers: markers,
                      onRecode: markers.isEmpty
                          ? null
                          : _showRecodeMarkersDialog,
                      onToggle: (bool expanded) =>
                          _updateParam('marker_list_expanded', expanded),
                      labelExpandedMap: Map<String, dynamic>.from(
                        widget.params['marker_label_expanded'] as Map? ??
                            <String, dynamic>{},
                      ),
                      onToggleLabelExpanded: (String label, bool expanded) {
                        final Map<String, dynamic> next =
                            Map<String, dynamic>.from(
                              widget.params['marker_label_expanded'] as Map? ??
                                  <String, dynamic>{},
                            );
                        next[label] = expanded;
                        _updateParam('marker_label_expanded', next);
                      },
                      onDelete: _deleteMarker,
                      onDeleteLabel: _deleteMarkersWithLabel,
                      onFocus: (TimeMarker marker) {
                        _jumpToTimeRange(
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
          onPressed: () => _persistDraftChanges(runAfterSave: false),
          child: const Text('Save'),
        ),
        FilledButton.tonal(
          onPressed: () => _persistDraftChanges(runAfterSave: true),
          child: const Text('Save and run'),
        ),
        OutlinedButton(onPressed: widget.onQuit, child: const Text('Quit')),
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final BuildContext? primaryContext =
        FocusManager.instance.primaryFocus?.context;
    if (primaryContext != null &&
        primaryContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool controlPressed = HardwareKeyboard.instance.isControlPressed;
    final bool altPressed = HardwareKeyboard.instance.isAltPressed;

    if (altPressed) {
      if (key == LogicalKeyboardKey.keyD) {
        _updateParam('raw_show_data', !_showSignals());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyM) {
        _updateParam('raw_show_markers', !_showMarkers());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _updateParam('raw_remove_dc', !_removeDc());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _setMode('view');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyE) {
        _setMode('edit');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI) {
        _setMode('edit');
        return KeyEventResult.handled;
      }
    }

    if (controlPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _stepTimeSpan(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }

    if (controlPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      _stepYScale(key == LogicalKeyboardKey.arrowUp ? 1 : -1);
      return KeyEventResult.handled;
    }

    if (!controlPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _nudgeHorizontalWindow(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _setMode(String mode) {
    setState(() {
      if (mode == 'edit') {
        widget.params['interactiveArtifactDetection'] = true;
        widget.params['interaction_mode'] = 'edit';
        widget.params['interactive_template_matching_enabled'] = true;
      } else {
        widget.params['interactiveArtifactDetection'] = false;
        widget.params['interaction_mode'] = 'view';
        widget.params['interactive_template_matching_enabled'] = false;
      }
      _ensureDefaults();
    });
  }

  void _stepTimeSpan(int direction) {
    final double current =
        (widget.params['window_sec'] as num?)?.toDouble() ??
        _timeSpanOptionsSec[0];
    final int currentIndex = _closestOptionIndex(_timeSpanOptionsSec, current);
    final int nextIndex = (currentIndex + direction).clamp(
      0,
      _timeSpanOptionsSec.length - 1,
    );
    _updateParam('window_sec', _timeSpanOptionsSec[nextIndex]);
  }

  void _stepYScale(int direction) {
    final double current = _yScaleUv();
    final int currentIndex = _closestOptionIndex(_yScaleOptionsUv, current);
    final int nextIndex = (currentIndex + direction).clamp(
      0,
      _yScaleOptionsUv.length - 1,
    );
    _updateParam('y_scale_uv', _yScaleOptionsUv[nextIndex]);
  }

  void _handleTracePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed ||
        event.scrollDelta.dy == 0) {
      return;
    }
    _stepYScale(event.scrollDelta.dy < 0 ? -1 : 1);
  }

  void _nudgeHorizontalWindow(int direction) {
    if (!_horizontalController.hasClients) {
      return;
    }
    final double viewportWidth =
        _horizontalController.position.viewportDimension;
    final double step = math.max(24.0, viewportWidth * 0.12);
    _horizontalController.jumpTo(
      (_horizontalController.offset + (direction * step)).clamp(
        0.0,
        _horizontalController.position.maxScrollExtent,
      ),
    );
  }

  void _handleMarkerTapOrRename(Offset localPosition, double pixelsPerSecond) {
    if (_renamingMarker) {
      return;
    }
    if (!_markerEditingEnabled()) {
      return;
    }

    if (_dragSelectionStart != null || _dragSelectionCurrent != null) {
      return;
    }

    final TimeMarker? tappedMarker = _markerAtLabelPosition(
      localPosition,
      pixelsPerSecond,
    );
    if (tappedMarker != null) {
      _renameMarker(tappedMarker);
      return;
    }

    if (_currentMode() != 'edit') {
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
    final int durationMicros =
        ((math.max(0.0, rightDx - leftDx) / pixelsPerSecond) * 1000000.0)
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

  TimeMarker? _markerAtLabelPosition(
    Offset localPosition,
    double pixelsPerSecond,
  ) {
    final double verticalOffset = _verticalController.hasClients
        ? _verticalController.offset
        : 0.0;
    final double labelTop = verticalOffset + 4;
    const double labelHeight = 18;
    if (localPosition.dy < labelTop ||
        localPosition.dy > (labelTop + labelHeight)) {
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
    return '${marker.label}:${marker.onsetMicros}:${marker.durationMicros}:${marker.markerType}';
  }

  Future<void> _renameMarker(TimeMarker marker) async {
    if (_renamingMarker) {
      return;
    }
    final String markerId = _markerReferenceId(marker);
    final TextEditingController controller = TextEditingController(
      text: marker.label,
    );
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
              decoration: const InputDecoration(labelText: 'Marker label'),
              onSubmitted: (String value) =>
                  Navigator.of(context).pop(value.trim()),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
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
    _setDraftMarkersForDataset(updated);
    setState(() {
      widget.params['marker_default_label'] = normalized;
      _hoveredMarkerReferenceId = null;
    });
  }

  Future<void> _showChannelEditPanel(
    int channelIndex, {
    bool allowInView = false,
  }) async {
    if (!allowInView && !_markerEditingEnabled()) {
      return;
    }
    final TimeSeriesData? baseTimeSeries = widget.dataset.timeSeries;
    if (baseTimeSeries == null || baseTimeSeries.channels.isEmpty) {
      return;
    }
    await _showChannelMarkerEditPanel(
      initialTab: ChannelMarkerEditTab.channels,
      channelIndex: channelIndex,
    );
  }

  Future<void> _showChannelMarkerEditPanel({
    required ChannelMarkerEditTab initialTab,
    int? channelIndex,
  }) async {
    final TimeSeriesData? baseTimeSeries = widget.dataset.timeSeries;
    if (baseTimeSeries == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Edit channels and markers',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ChannelMarkerEditConfigEditor(
                      dataset: widget.dataset,
                      channelConfig: _effectiveChannelEditConfig(),
                      markers: _currentMarkersForDataset(),
                      initialTab: initialTab,
                      initialVisibleChannelIndices: channelIndex == null
                          ? null
                          : <int>[channelIndex],
                      channelHeaderAction: OutlinedButton.icon(
                        onPressed: () => showChannelPositionsDialog(
                          context,
                          dataset: widget.dataset,
                        ),
                        icon: const Icon(Icons.public, size: 18),
                        label: const Text('Channel positions'),
                      ),
                      onChannelConfigChanged: (Map<String, dynamic> config) {
                        setState(() {
                          _draftChannelEditConfig = config;
                        });
                      },
                      onMarkersChanged: (List<TimeMarker> markers) {
                        _setDraftMarkersForDataset(markers);
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
      onsetMicros: ((math.min(start.dx, end.dx) / pixelsPerSecond) * 1000000.0)
          .round(),
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

  void _deleteMarkersWithLabel(String label) {
    _setDraftMarkersForDataset(
      _currentMarkersForDataset()
          .where((TimeMarker marker) => marker.label != label)
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
            (String label) =>
                PopupMenuItem<String>(value: label, child: Text(label)),
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
        .where(
          (Map<String, dynamic> marker) =>
              marker['datasetId'] == widget.dataset.id,
        )
        .map((Map<String, dynamic> marker) {
          final Map<String, dynamic> payload = Map<String, dynamic>.from(
            marker,
          );
          payload.remove('datasetId');
          return TimeMarker.fromJson(payload);
        })
        .toList(growable: false);
    if (_draftMarkers != null || editedMarkers.isNotEmpty) {
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
      _draftMarkers ??
      (widget.params['markers'] as List<dynamic>? ?? <dynamic>[]);

  bool get _hasMarkerDraft => _draftMarkers != null;

  bool get _hasChannelEditDraft => _draftChannelEditConfig != null;

  bool get _hasInteractiveArtifactDraft =>
      _draftArtifactExemplars != null ||
      _draftArtifactCandidates != null ||
      _draftArtifactTemplates != null;

  bool get _hasAnyDraftChanges =>
      _currentDraftSaveRequest(runAfterSave: false) != null;

  Map<String, dynamic> _effectiveChannelEditConfig() {
    return _draftChannelEditConfig ??
        EditChannelsNodeType.configForDataset(widget.params, widget.dataset.id);
  }

  bool _interactiveArtifactDetectionEnabled() =>
      widget.params['interactiveArtifactDetection'] == true;

  bool _interactiveMatchingEnabled() =>
      _interactiveArtifactDetectionEnabled() &&
      (widget.params['interactive_template_matching_enabled'] as bool?) !=
          false;

  bool _markerEditingEnabled() {
    final String mode = _interactionMode();
    return mode == 'edit' || mode == 'interactive';
  }

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

  List<ArtifactCandidateData> _artifactCandidates({Set<String>? statuses}) {
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
        (widget.params['artifactExemplars'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where(
              (Map<String, dynamic> item) =>
                  item['datasetId'] != widget.dataset.id,
            )
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: true);
    final List<Map<String, dynamic>> preservedCandidates =
        (widget.params['artifactCandidates'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where(
              (Map<String, dynamic> item) =>
                  item['datasetId'] != widget.dataset.id,
            )
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: true);
    final List<Map<String, dynamic>> preservedTemplates =
        (widget.params['artifactTemplates'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where(
              (Map<String, dynamic> item) =>
                  item['datasetId'] != widget.dataset.id,
            )
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: true);

    preservedExemplars.addAll(
      currentDatasetExemplars.map((ArtifactExemplarData item) => item.toJson()),
    );
    preservedCandidates.addAll(
      currentDatasetCandidates.map(
        (ArtifactCandidateData item) => item.toJson(),
      ),
    );
    preservedTemplates.addAll(
      currentDatasetTemplates.map(
        (ArtifactTemplateSummary item) => item.toJson(),
      ),
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
          enableTemplateMatching: _interactiveMatchingEnabled(),
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
          (ArtifactCandidateData item) =>
              item.id == candidate.id ? item.copyWith(status: status) : item,
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

  void _undoAcceptedInteractiveArtifactCandidate(
    ArtifactCandidateData candidate,
  ) {
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
        .where(
          (Map<String, dynamic> marker) =>
              marker['datasetId'] != widget.dataset.id,
        )
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

  Future<void> _persistDraftChanges({required bool runAfterSave}) async {
    final ViewerDraftSaveRequest? request = _currentDraftSaveRequest(
      runAfterSave: runAfterSave,
    );
    if (request == null) {
      return;
    }
    final Future<void> Function(ViewerDraftSaveRequest request)?
    onPersistDrafts = widget.onPersistDrafts;
    if (onPersistDrafts == null) {
      return;
    }
    final String fingerprint = _draftSaveFingerprint(request);
    final _SavedChangesSummary savedSummary = _SavedChangesSummary(
      title: _savedChangesTitle(request),
      items: _draftManifestItems(_interactiveArtifactDetectionEnabled()),
    );
    await onPersistDrafts(request);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastPersistedDraftFingerprint = fingerprint;
      _savedChangesSummary = savedSummary;
    });
    if (runAfterSave) {
      widget.onQuit?.call();
    }
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
      _lastPersistedDraftFingerprint = null;
    });
  }

  Future<void> _showRecodeMarkersDialog() async {
    if (widget.dataset.timeSeries != null) {
      await _showChannelMarkerEditPanel(
        initialTab: ChannelMarkerEditTab.markers,
      );
      return;
    }
    final List<TimeMarker> markers = _currentMarkersForDataset();
    if (markers.isEmpty || !mounted) {
      return;
    }
    final List<String> labels =
        markers
            .map((TimeMarker marker) => marker.label)
            .toSet()
            .toList(growable: false)
          ..sort();
    final Map<String, String> draftValues = <String, String>{
      for (final String label in labels) label: '',
    };
    final List<String> boundaryLabels = labels
        .where((String label) => label.trim().isNotEmpty)
        .toList(growable: false);
    final Set<String> deletedLabels = <String>{};
    int nextBoundaryDraftId = 1;
    final List<_BoundaryCombinationDraft> boundaryDrafts =
        <_BoundaryCombinationDraft>[
          _BoundaryCombinationDraft(id: nextBoundaryDraftId++),
        ];

    Map<String, String> effectiveRenames() => <String, String>{
      for (final MapEntry<String, String> entry in draftValues.entries)
        if (!deletedLabels.contains(entry.key) && entry.value.trim().isNotEmpty)
          entry.key: entry.value.trim(),
    };

    String? boundaryValidationMessage(_BoundaryCombinationDraft draft) {
      final String? start = draft.startLabel;
      final String? stop = draft.stopLabel;
      if (start == null && stop == null) {
        return null;
      }
      if (start == null || stop == null) {
        return 'Choose both a start marker and a stop marker.';
      }
      if (deletedLabels.contains(start) || deletedLabels.contains(stop)) {
        return 'A boundary label cannot be deleted and combined at the same time.';
      }
      if (draft.blockLabel.trim().isEmpty) {
        return 'Enter a label for the new blocks.';
      }
      final Map<String, String> renamed = effectiveRenames();
      if ((renamed[start] ?? start) == (renamed[stop] ?? stop)) {
        return 'Start and stop markers must use different labels.';
      }
      return null;
    }

    MarkerBoundaryCombinationResult? boundaryPreview(
      _BoundaryCombinationDraft draft,
    ) {
      final String? start = draft.startLabel;
      final String? stop = draft.stopLabel;
      if (start == null ||
          stop == null ||
          boundaryValidationMessage(draft) != null) {
        return null;
      }
      final Map<String, String> renamed = effectiveRenames();
      final List<TimeMarker> previewMarkers = markers
          .where((TimeMarker marker) => !deletedLabels.contains(marker.label))
          .map((TimeMarker marker) {
            final String? replacement = renamed[marker.label];
            return replacement == null
                ? marker
                : marker.copyWith(label: replacement);
          })
          .toList(growable: false);
      return AddRemoveMarkersNodeType.combineBoundaryMarkers(
        previewMarkers,
        startLabel: renamed[start] ?? start,
        stopLabel: renamed[stop] ?? stop,
        blockLabel: draft.blockLabel,
        replaceBoundaries: false,
      );
    }

    final Map<String, dynamic>? edits = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit markers'),
          content: SizedBox(
            width: 680,
            child: StatefulBuilder(
              builder:
                  (
                    BuildContext context,
                    void Function(void Function()) setDialogState,
                  ) {
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('Rename or delete marker labels.'),
                          const SizedBox(height: 12),
                          for (
                            int index = 0;
                            index < labels.length;
                            index++
                          ) ...<Widget>[
                            if (index > 0) const Divider(height: 18),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    labels[index],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: IgnorePointer(
                                    ignoring: deletedLabels.contains(
                                      labels[index],
                                    ),
                                    child: Opacity(
                                      opacity:
                                          deletedLabels.contains(labels[index])
                                          ? 0.4
                                          : 1,
                                      child: TextFormField(
                                        initialValue:
                                            draftValues[labels[index]] ?? '',
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          hintText: 'New label',
                                          hintStyle: TextStyle(
                                            color: Colors.white38,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (String value) {
                                          setDialogState(() {
                                            draftValues[labels[index]] = value;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message:
                                      'Delete all ${labels[index]} markers',
                                  child: Checkbox(
                                    value: deletedLabels.contains(
                                      labels[index],
                                    ),
                                    onChanged: (bool? value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          deletedLabels.add(labels[index]);
                                        } else {
                                          deletedLabels.remove(labels[index]);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                const Text('Delete'),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),
                          Text(
                            'Combine boundaries into blocks',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Each stop closes the earliest unmatched start.',
                          ),
                          const SizedBox(height: 12),
                          for (
                            int index = 0;
                            index < boundaryDrafts.length;
                            index++
                          )
                            _buildBoundaryCombinationEditor(
                              context: context,
                              draft: boundaryDrafts[index],
                              boundaryLabels: boundaryLabels,
                              validationMessage: boundaryValidationMessage(
                                boundaryDrafts[index],
                              ),
                              preview: boundaryPreview(boundaryDrafts[index]),
                              canRemove: boundaryDrafts.length > 1,
                              onChanged: () => setDialogState(() {}),
                              onRemove: () {
                                setDialogState(() {
                                  boundaryDrafts.removeAt(index);
                                });
                              },
                            ),
                          TextButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                boundaryDrafts.add(
                                  _BoundaryCombinationDraft(
                                    id: nextBoundaryDraftId++,
                                  ),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add pair-to-block transform'),
                          ),
                        ],
                      ),
                    );
                  },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String? validationMessage = boundaryDrafts
                    .map(boundaryValidationMessage)
                    .whereType<String>()
                    .firstOrNull;
                if (validationMessage != null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(validationMessage)));
                  return;
                }
                final Map<String, String> renamedLabels = effectiveRenames();
                Navigator.of(context).pop(<String, dynamic>{
                  'renamedLabels': renamedLabels,
                  'deletedLabels': deletedLabels.toList(growable: false),
                  'boundaryCombinations': boundaryDrafts
                      .where(
                        (_BoundaryCombinationDraft draft) =>
                            draft.startLabel != null && draft.stopLabel != null,
                      )
                      .map(
                        (_BoundaryCombinationDraft draft) => <String, dynamic>{
                          'startLabel': draft.startLabel,
                          'stopLabel': draft.stopLabel,
                          'blockLabel': draft.blockLabel.trim(),
                          'replaceBoundaries': draft.replaceBoundaries,
                        },
                      )
                      .toList(growable: false),
                });
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    if (!mounted || edits == null) {
      return;
    }
    final Map<String, String> renamedLabels = Map<String, String>.from(
      edits['renamedLabels'] as Map? ?? const <String, String>{},
    );
    final Set<String> removedLabels = Set<String>.from(
      edits['deletedLabels'] as List<dynamic>? ?? const <dynamic>[],
    );
    final List<Map<String, dynamic>> boundaryCombinations =
        (edits['boundaryCombinations'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map value) => Map<String, dynamic>.from(value))
            .toList(growable: false);
    if (renamedLabels.isEmpty &&
        removedLabels.isEmpty &&
        boundaryCombinations.isEmpty) {
      return;
    }
    List<TimeMarker> recoded = markers
        .where((TimeMarker marker) => !removedLabels.contains(marker.label))
        .map((TimeMarker marker) {
          final String? replacement = renamedLabels[marker.label];
          if (replacement == null || replacement.isEmpty) {
            return marker;
          }
          return marker.copyWith(label: replacement);
        })
        .toList(growable: false);
    int combinedCount = 0;
    int unmatchedCount = 0;
    for (final Map<String, dynamic> boundaryCombination
        in boundaryCombinations) {
      final String originalStart = boundaryCombination['startLabel'].toString();
      final String originalStop = boundaryCombination['stopLabel'].toString();
      final MarkerBoundaryCombinationResult combinationResult =
          AddRemoveMarkersNodeType.combineBoundaryMarkers(
            recoded,
            startLabel: renamedLabels[originalStart] ?? originalStart,
            stopLabel: renamedLabels[originalStop] ?? originalStop,
            blockLabel: boundaryCombination['blockLabel'].toString(),
            replaceBoundaries:
                boundaryCombination['replaceBoundaries'] as bool? ?? true,
          );
      recoded = combinationResult.markers;
      combinedCount += combinationResult.combinedCount;
      unmatchedCount +=
          combinationResult.unmatchedStartCount +
          combinationResult.unmatchedStopCount;
    }
    _setDraftMarkersForDataset(recoded);
    if (boundaryCombinations.isNotEmpty && mounted) {
      final String message = combinedCount == 0
          ? 'No complete start/stop pairs were found.'
          : 'Created $combinedCount block${combinedCount == 1 ? '' : 's'}${unmatchedCount == 0 ? '.' : '; left $unmatchedCount unmatched boundary marker${unmatchedCount == 1 ? '' : 's'}.'}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _buildBoundaryCombinationEditor({
    required BuildContext context,
    required _BoundaryCombinationDraft draft,
    required List<String> boundaryLabels,
    required String? validationMessage,
    required MarkerBoundaryCombinationResult? preview,
    required bool canRemove,
    required VoidCallback onChanged,
    required VoidCallback onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (canRemove)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: onRemove,
                tooltip: 'Remove transform',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double fieldWidth = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 20) / 3
                  : constraints.maxWidth;
              DropdownButtonFormField<String> boundaryDropdown({
                required String role,
                required String? value,
                required ValueChanged<String?> onSelected,
              }) {
                return DropdownButtonFormField<String>(
                  key: ValueKey<String>('${draft.id}-$role-${value ?? 'none'}'),
                  initialValue: value ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '$role marker',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: <String>['', ...boundaryLabels]
                      .map(
                        (String label) => DropdownMenuItem<String>(
                          value: label,
                          child: Text(
                            label.isEmpty ? 'None' : label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onSelected,
                );
              }

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  SizedBox(
                    width: fieldWidth,
                    child: boundaryDropdown(
                      role: 'Start',
                      value: draft.startLabel,
                      onSelected: (String? value) {
                        draft.startLabel = value == null || value.isEmpty
                            ? null
                            : value;
                        onChanged();
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: boundaryDropdown(
                      role: 'Stop',
                      value: draft.stopLabel,
                      onSelected: (String? value) {
                        draft.stopLabel = value == null || value.isEmpty
                            ? null
                            : value;
                        onChanged();
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: ValueKey<String>('${draft.id}-block'),
                      initialValue: draft.blockLabel,
                      decoration: const InputDecoration(
                        labelText: 'Block label',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (String value) {
                        draft.blockLabel = value;
                        onChanged();
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          if (validationMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              validationMessage,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ] else if (preview != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '${preview.combinedCount} complete pair${preview.combinedCount == 1 ? '' : 's'}; '
              '${preview.unmatchedStartCount} unmatched start${preview.unmatchedStartCount == 1 ? '' : 's'}; '
              '${preview.unmatchedStopCount} unmatched stop${preview.unmatchedStopCount == 1 ? '' : 's'}.',
              style: const TextStyle(color: Colors.white60),
            ),
          ],
          Row(
            children: <Widget>[
              Checkbox(
                value: draft.replaceBoundaries,
                onChanged: (bool? value) {
                  draft.replaceBoundaries = value ?? true;
                  onChanged();
                },
              ),
              const Expanded(
                child: Text('Replace paired start and stop markers'),
              ),
            ],
          ),
          Divider(color: Colors.white.withValues(alpha: 0.10)),
        ],
      ),
    );
  }

  ViewerDraftSaveRequest? _currentDraftSaveRequest({
    required bool runAfterSave,
  }) {
    final List<Map<String, dynamic>>? markerEdits = _draftMarkers
        ?.whereType<Map<String, dynamic>>()
        .where(
          (Map<String, dynamic> marker) =>
              marker['datasetId'] == widget.dataset.id,
        )
        .map((Map<String, dynamic> marker) => Map<String, dynamic>.from(marker))
        .toList(growable: false);
    final Map<String, dynamic>? channelEditConfig =
        _draftChannelEditConfig == null
        ? null
        : EditChannelsNodeType.configForDataset(<String, dynamic>{
            'channelEditsByDataset': <String, dynamic>{
              widget.dataset.id: _draftChannelEditConfig!,
            },
          }, widget.dataset.id);
    final Map<String, dynamic>? interactiveArtifactParams =
        _hasInteractiveArtifactDraft
        ? <String, dynamic>{
            'interactiveArtifactDetection': true,
            'artifactThreshold':
                (widget.params['artifactThreshold'] as num?)?.toDouble() ??
                0.78,
            'artifactExemplars': _artifactExemplars()
                .map((ArtifactExemplarData item) => item.toJson())
                .toList(growable: false),
            'artifactCandidates': _artifactCandidates()
                .map((ArtifactCandidateData item) => item.toJson())
                .toList(growable: false),
            'artifactTemplates': _artifactTemplateSummaries()
                .map((ArtifactTemplateSummary item) => item.toJson())
                .toList(growable: false),
          }
        : null;

    final bool hasMarkerEdits = markerEdits != null;
    final bool hasChannelEdits = channelEditConfig != null;
    final bool hasInteractiveEdits = interactiveArtifactParams != null;
    if (!hasMarkerEdits && !hasChannelEdits && !hasInteractiveEdits) {
      return null;
    }

    final ViewerDraftSaveRequest request = ViewerDraftSaveRequest(
      markerEdits: markerEdits,
      channelEditConfig: channelEditConfig,
      interactiveArtifactParams: interactiveArtifactParams,
      runAfterSave: runAfterSave,
    );
    if (_lastPersistedDraftFingerprint == _draftSaveFingerprint(request)) {
      return null;
    }
    return request;
  }

  String _draftSaveFingerprint(ViewerDraftSaveRequest request) {
    return jsonEncode(<String, dynamic>{
      'markerEdits': request.markerEdits,
      'channelEditConfig': request.channelEditConfig,
      'interactiveArtifactParams': request.interactiveArtifactParams,
    });
  }

  void _jumpToTimeRange({
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
    final double recordingSeconds =
        timeSeries.sampleCount / timeSeries.sampleRate;
    final double viewportWidth = math.max(1.0, _lastTraceViewportWidth);
    final double pixelsPerSecond = viewportWidth / secondsPerView;
    final double targetStartSeconds = (centerSeconds - (secondsPerView / 2))
        .clamp(0.0, math.max(0.0, recordingSeconds - secondsPerView));
    final double targetOffset = targetStartSeconds * pixelsPerSecond;
    _horizontalController.jumpTo(
      targetOffset.clamp(0.0, _horizontalController.position.maxScrollExtent),
    );
  }

  void _syncTraceViewportWidth({
    required double nextWidth,
    required double secondsPerView,
  }) {
    final double previousWidth = _lastTraceViewportWidth;
    if ((previousWidth - nextWidth).abs() < 0.5) {
      _lastTraceViewportWidth = nextWidth;
      return;
    }
    _lastTraceViewportWidth = nextWidth;
    if (!_horizontalController.hasClients || _traceViewportSyncScheduled) {
      return;
    }
    final double previousPixelsPerSecond = previousWidth / secondsPerView;
    if (previousPixelsPerSecond <= 0) {
      return;
    }
    final double previousRightEdgeSeconds =
        (_horizontalController.offset + previousWidth) /
        previousPixelsPerSecond;
    _traceViewportSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _traceViewportSyncScheduled = false;
      if (!mounted || !_horizontalController.hasClients) {
        return;
      }
      final double nextPixelsPerSecond = nextWidth / secondsPerView;
      final double nextOffset =
          (previousRightEdgeSeconds * nextPixelsPerSecond) - nextWidth;
      _horizontalController.jumpTo(
        nextOffset.clamp(0.0, _horizontalController.position.maxScrollExtent),
      );
    });
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
      () => _interactiveArtifactDetectionEnabled()
          ? 'interactive'
          : (legacyMarkerMode == 'edit' ? 'edit' : 'view'),
    );
    widget.params.putIfAbsent(
      'interactive_template_matching_enabled',
      () => _interactiveArtifactDetectionEnabled(),
    );
    if ((widget.params['interaction_mode'] ?? '').toString() == 'interactive') {
      widget.params['interaction_mode'] = 'edit';
    }
    widget.params.putIfAbsent('marker_default_label', () => 'new marker');
    widget.params.putIfAbsent('markers', () => <Map<String, dynamic>>[]);
    widget.params.putIfAbsent('channel_colors', () => <String, dynamic>{});
    widget.params.putIfAbsent('marker_list_expanded', () => false);
    widget.params.putIfAbsent(
      'marker_label_expanded',
      () => <String, dynamic>{},
    );
    widget.params.putIfAbsent('artifact_exemplars_expanded', () => true);
    widget.params.putIfAbsent('artifact_candidates_expanded', () => true);
    widget.params.putIfAbsent('y_scale_uv', () => 100.0);
    widget.params.putIfAbsent('channel_spacing_factor', () => 1.0);
    widget.params.putIfAbsent('raw_show_data', () => true);
    widget.params.putIfAbsent('raw_show_markers', () => true);
    widget.params.putIfAbsent('raw_remove_dc', () => true);
    widget.params.putIfAbsent('right_panel_collapsed', () => false);
    if (_interactiveArtifactDetectionEnabled()) {
      final String interactionMode =
          (widget.params['interaction_mode'] ?? 'edit').toString();
      if (interactionMode != 'edit') {
        widget.params['interaction_mode'] = 'edit';
      }
      widget.params['interactive_template_matching_enabled'] = true;
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
            steepness: 0.5,
          ),
        )
        .toList(growable: false);
    _filterCacheKey = cacheKey;
    return _filteredChannels!;
  }

  List<_ChannelDisplayRow> _channelDisplayRows(TimeSeriesData timeSeries) {
    final List<String> baseLabels = _channelLabels(
      timeSeries,
      timeSeries.channelCount,
    );
    final List<List<double>> baseChannels = _effectiveChannels(timeSeries);
    final Map<String, dynamic> config = _effectiveChannelEditConfig();
    final Map<int, Map<String, dynamic>> resolvedEdits =
        EditChannelsNodeType.resolvedEditsForSeries(timeSeries, config);
    return List<_ChannelDisplayRow>.generate(timeSeries.channelCount, (
      int index,
    ) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        resolvedEdits[index] ?? const <String, dynamic>{},
      );
      final String renamed = (edit['rename'] ?? '').toString().trim();
      final bool removed = edit['remove'] == true;
      final String removeMode = (edit['removeMode'] ?? 'delete')
          .toString()
          .trim()
          .toLowerCase();
      final bool hideTrace = removed && removeMode == 'delete';
      return _ChannelDisplayRow(
        sourceIndex: index,
        label: renamed.isEmpty ? baseLabels[index] : renamed,
        samples: hideTrace ? const <double>[] : baseChannels[index],
        removed: hideTrace,
      );
    }, growable: false);
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
    final double spacingFactor = _channelSpacingFactor();
    return math.max(
      40.0,
      (viewportHeight / math.max(1, channelCount)) * spacingFactor,
    );
  }

  double _yScaleUv() {
    final double requested =
        (widget.params['y_scale_uv'] as num?)?.toDouble() ?? 100.0;
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

  double _channelSpacingFactor() {
    final double requested =
        (widget.params['channel_spacing_factor'] as num?)?.toDouble() ?? 1.0;
    double closest = _channelSpacingOptions.first;
    double bestDistance = (requested - closest).abs();
    for (final double option in _channelSpacingOptions.skip(1)) {
      final double distance = (requested - option).abs();
      if (distance < bestDistance) {
        closest = option;
        bestDistance = distance;
      }
    }
    return closest;
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
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      maxWidth = math.max(maxWidth, painter.width + 38);
    }
    return maxWidth.clamp(88.0, 260.0);
  }

  double _defaultRightPanelWidth(List<TimeMarker> markers) {
    double measure(
      String text, {
      double fontSize = 12,
      FontWeight fontWeight = FontWeight.w600,
    }) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, fontWeight: fontWeight),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    // Includes panel padding, the section chevron, and the Edit markers action.
    double maxWidth =
        measure('Markers (${markers.length})') + measure('Edit markers') + 78;
    for (final String text in <String>[
      'Current template',
      'Candidate matches',
      'Accepted',
      'Save and Quit',
    ]) {
      maxWidth = math.max(maxWidth, measure(text) + 56);
    }
    for (final String label
        in markers.map((TimeMarker marker) => marker.label).toSet().take(32)) {
      // A marker-label row also contains a chevron, swatch, count, and delete.
      maxWidth = math.max(maxWidth, measure(label) + 132);
    }
    return maxWidth.clamp(248.0, 360.0);
  }

  double _resolvedLeftPanelWidth(double defaultWidth) {
    return ((widget.params['left_panel_width'] as num?)?.toDouble() ??
            defaultWidth)
        .clamp(88.0, 260.0);
  }

  double _resolvedRightPanelWidth(double defaultWidth) {
    return ((widget.params['right_panel_width'] as num?)?.toDouble() ??
            defaultWidth)
        .clamp(188.0, 420.0);
  }

  String _interactionMode() {
    final String mode = (widget.params['interaction_mode'] ?? 'view')
        .toString();
    if (mode == 'interactive' ||
        mode == 'edit' ||
        mode == 'markers' ||
        mode == 'channels') {
      return 'edit';
    }
    return 'view';
  }

  String _currentViewIdentity() {
    final String sourceKey =
        widget.dataset.ram['viewer.sourceKey']?.toString() ?? widget.dataset.id;
    final Object? sampleRate = widget.dataset.ram['signal.fs'];
    final Object? sampleCount = widget.dataset.ram['signal.samples'] is List
        ? (widget.dataset.ram['signal.samples'] as List).length
        : widget.dataset.timeSeries?.sampleCount;
    return '$sourceKey|$sampleRate|$sampleCount';
  }

  void _scheduleViewportReset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_horizontalController.hasClients) {
        _horizontalController.jumpTo(0);
      }
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(0);
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget _buildDraftSummary(bool interactiveArtifactDetection) {
    final List<_DraftManifestItem> items = _draftManifestItems(
      interactiveArtifactDetection,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => setState(() {
                _draftSummaryExpanded = !_draftSummaryExpanded;
              }),
              child: Row(
                children: <Widget>[
                  Icon(
                    _draftSummaryExpanded
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Unsaved changes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Tooltip(
                    message:
                        'Saving creates or updates processing nodes. The source file is not changed.',
                    child: Icon(
                      Icons.info_outline,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
            if (_draftSummaryExpanded) ...<Widget>[
              const SizedBox(height: 10),
              ..._buildDraftManifestRows(items),
            ],
          ],
        ),
      ),
    );
  }

  List<_DraftManifestItem> _draftManifestItems(
    bool interactiveArtifactDetection,
  ) {
    return <_DraftManifestItem>[
      if (_hasMarkerDraft)
        _DraftManifestItem(
          label: 'Markers',
          detail: _markerDraftSummary(),
          color: const Color(0xFFFFD54F),
        ),
      if (_hasChannelEditDraft)
        _DraftManifestItem(label: 'Channels', detail: _channelDraftSummary()),
      if (_hasInteractiveArtifactDraft)
        _DraftManifestItem(
          label: interactiveArtifactDetection ? 'Interactive' : 'Artifacts',
          detail: _interactiveDraftSummary(),
          color: const Color(0xFFFF8A65),
        ),
    ];
  }

  Widget _buildSavedChangesSummary(_SavedChangesSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          summary.title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ..._buildDraftManifestRows(summary.items),
      ],
    );
  }

  Iterable<Widget> _buildDraftManifestRows(List<_DraftManifestItem> items) {
    return items.map(
      (_DraftManifestItem item) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (item.color != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.25,
                  ),
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${item.label}: ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: item.detail),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _savedChangesTitle(ViewerDraftSaveRequest request) {
    final List<String> nodes = <String>[
      if (request.hasChannelEdits) '"Edit Channels"',
      if (request.hasMarkerEdits || request.hasInteractiveArtifactEdits)
        '"Edit Markers"',
    ];
    final String nodeText = nodes.length == 1
        ? '${nodes.single} node'
        : '${nodes.join(' and ')} nodes';
    return 'Saved changes (new $nodeText created)';
  }

  String _channelDraftSummary() {
    final Map<String, dynamic> config = _effectiveChannelEditConfig();
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      config['edits'] as Map? ?? const <String, dynamic>{},
    );
    final List<dynamic> newChannels =
        config['newChannels'] as List<dynamic>? ?? const <dynamic>[];
    final TimeSeriesData? timeSeries = widget.dataset.timeSeries;
    final List<String> labels = timeSeries == null
        ? const <String>[]
        : _channelLabels(timeSeries, timeSeries.channelCount);
    final List<String> deleted = <String>[];
    final List<String> interpolated = <String>[];
    final List<String> renamedChannels = <String>[];
    final List<String> added = <String>[];

    for (final MapEntry<String, dynamic> entry in edits.entries) {
      final int? index = int.tryParse(entry.key);
      if (index == null || index < 0 || index >= labels.length) {
        continue;
      }
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        entry.value as Map? ?? const <String, dynamic>{},
      );
      final String label = labels[index];
      final String newName = (edit['rename'] ?? '').toString().trim();
      if (edit['remove'] == true) {
        final String mode = (edit['removeMode'] ?? 'delete')
            .toString()
            .toLowerCase();
        (mode == 'interpolate' ? interpolated : deleted).add(label);
      } else if (newName.isNotEmpty && newName != label) {
        renamedChannels.add('$label to $newName');
      }
    }

    for (final dynamic value in newChannels) {
      final Map<String, dynamic> channel = Map<String, dynamic>.from(
        value as Map? ?? const <String, dynamic>{},
      );
      final String name = (channel['name'] ?? '').toString().trim();
      added.add(name.isEmpty ? 'unnamed channel' : name);
    }

    final List<String> changes = <String>[
      if (deleted.isNotEmpty) 'Deleted: ${deleted.join(', ')}',
      if (interpolated.isNotEmpty) 'Interpolated: ${interpolated.join(', ')}',
      if (renamedChannels.isNotEmpty) 'Renamed: ${renamedChannels.join(', ')}',
      if (added.isNotEmpty) 'Added: ${added.join(', ')}',
    ];
    if ((config['coordinateImportMode'] ?? '').toString() ==
        EditChannelsNodeType.coordinateImportStandard) {
      changes.add('Coordinates: All channels');
    }
    if ((config['rereferenceMode'] ?? '').toString() ==
        EditChannelsNodeType.rereferenceAverage) {
      changes.add('Applied average reference');
    }
    return changes.isEmpty ? 'No channel edits' : changes.join('; ');
  }

  String _markerDraftSummary() {
    final List<TimeMarker> savedMarkers = _savedMarkersForDataset();
    final List<TimeMarker> currentMarkers = _currentMarkersForDataset();
    final Map<String, int> savedCounts = _markerCountsByLabel(savedMarkers);
    final Map<String, int> currentCounts = _markerCountsByLabel(currentMarkers);
    final List<String> deleted = <String>[];
    final List<String> added = <String>[];

    for (final String label in {...savedCounts.keys, ...currentCounts.keys}) {
      final int difference =
          (currentCounts[label] ?? 0) - (savedCounts[label] ?? 0);
      if (difference < 0) {
        deleted.add(_markerCountLabel(label, -difference));
      } else if (difference > 0) {
        added.add(_markerCountLabel(label, difference));
      }
    }

    final List<String> changes = <String>[
      if (deleted.isNotEmpty) 'Deleted: ${deleted.join(', ')}',
      if (added.isNotEmpty) 'Added: ${added.join(', ')}',
    ];
    return changes.isEmpty ? 'Markers edited' : changes.join('; ');
  }

  List<TimeMarker> _savedMarkersForDataset() {
    final List<TimeMarker> saved =
        (widget.params['markers'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where(
              (Map<String, dynamic> marker) =>
                  marker['datasetId'] == widget.dataset.id,
            )
            .map((Map<String, dynamic> marker) {
              final Map<String, dynamic> payload = Map<String, dynamic>.from(
                marker,
              );
              payload.remove('datasetId');
              return TimeMarker.fromJson(payload);
            })
            .toList(growable: false);
    return saved.isNotEmpty
        ? saved
        : widget.dataset.timeSeries?.markers ?? const <TimeMarker>[];
  }

  Map<String, int> _markerCountsByLabel(List<TimeMarker> markers) {
    final Map<String, int> counts = <String, int>{};
    for (final TimeMarker marker in markers) {
      counts.update(marker.label, (int count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  String _markerCountLabel(String label, int count) {
    return count == 1 ? label : '$label ($count)';
  }

  String _interactiveDraftSummary() {
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
    return '$exemplarCount exemplar(s), $pendingCount pending candidate(s), $acceptedCount accepted match(es), and $templateCount template(s) will be converted into marker parameters in an Edit Markers node for this dataset.';
  }

  String _currentMode() {
    return _interactionMode();
  }

  int _closestOptionIndex(List<double> options, double value) {
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
    final Map<String, dynamic> colorMap = Map<String, dynamic>.from(
      widget.params['channel_colors'] as Map? ?? <String, dynamic>{},
    );
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
    final Map<String, dynamic> colorMap = Map<String, dynamic>.from(
      widget.params['channel_colors'] as Map? ?? <String, dynamic>{},
    );
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
  const _HoverHighlightFrame({required this.child, required this.glowColor});

  final Widget child;
  final Color glowColor;

  @override
  State<_HoverHighlightFrame> createState() => _HoverHighlightFrameState();
}

class _HoverHighlightFrameState extends State<_HoverHighlightFrame> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.yellow.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: _hovered
              ? Border.all(color: Colors.yellow.withValues(alpha: 0.85))
              : null,
          boxShadow: _hovered
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
            child: Center(child: Icon(icon, color: Colors.white70, size: 18)),
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
    required this.spacingFactor,
    required this.spacingOptions,
    required this.onSpacingSelected,
  });

  final double timeSeconds;
  final List<double> timeOptionsSeconds;
  final ValueChanged<double> onTimeSelected;
  final double rangeUv;
  final List<double> rangeOptionsUv;
  final ValueChanged<double> onRangeSelected;
  final double spacingFactor;
  final List<double> spacingOptions;
  final ValueChanged<double> onSpacingSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const Text('Scale:', style: TextStyle(color: Colors.white70)),
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
          valueText: '${rangeUv.toStringAsFixed(0)} μV',
          tooltip: 'Signal range',
          options: rangeOptionsUv,
          itemLabelBuilder: (double option) =>
              '${option.toStringAsFixed(0)} μV',
          onSelected: onRangeSelected,
        ),
        _ScalePillMenu<double>(
          label: 'Spacing',
          currentValue: spacingFactor,
          valueText:
              '${spacingFactor.toStringAsFixed(spacingFactor == spacingFactor.roundToDouble() ? 0 : 2)}x',
          tooltip: 'Channel spacing',
          options: spacingOptions,
          itemLabelBuilder: (double option) =>
              '${option.toStringAsFixed(option == option.roundToDouble() ? 0 : 2)}x',
          onSelected: onSpacingSelected,
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
              return options
                  .map((T option) {
                    return PopupMenuItem<T>(
                      value: option,
                      child: Text(itemLabelBuilder(option)),
                    );
                  })
                  .toList(growable: false);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
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

class _InlineToggleButton extends StatelessWidget {
  const _InlineToggleButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final double buttonWidth = painter.width + 40;
    return SizedBox(
      width: buttonWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size(buttonWidth, 34),
            backgroundColor: selected
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.04),
            foregroundColor: selected ? Colors.white : Colors.white70,
            side: BorderSide(
              color: selected
                  ? Colors.white.withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            shape: const StadiumBorder(),
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
            animationDuration: Duration.zero,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineToggleGroup extends StatelessWidget {
  const _InlineToggleGroup({required this.label, required this.options});

  final String label;
  final List<_InlineToggleOption> options;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(label, style: const TextStyle(color: Colors.white70)),
        ...options.map((_InlineToggleOption option) {
          return _InlineToggleButton(
            label: option.label,
            selected: option.selected,
            onPressed: option.onPressed,
          );
        }),
      ],
    );
  }
}

class _InlineChoiceGroup extends StatelessWidget {
  const _InlineChoiceGroup({required this.label, required this.options});

  final String label;
  final List<_InlineChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    final String selectedLabel = options
        .firstWhere(
          (_InlineChoiceOption option) => option.selected,
          orElse: () => options.first,
        )
        .label;

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
          Text(label, style: const TextStyle(color: Colors.white70)),
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
                        fontWeight: option.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
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
    required this.removed,
    required this.channelHeight,
    required this.onCycleColor,
    required this.channelEditEnabled,
    required this.onEditChannel,
  });

  final List<String> labels;
  final List<Color> colors;
  final List<bool> removed;
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
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.channelEditEnabled && _hoveredIndex == index
                          ? Colors.yellow.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border:
                          widget.channelEditEnabled && _hoveredIndex == index
                          ? Border.all(
                              color: Colors.yellow.withValues(alpha: 0.85),
                            )
                          : null,
                      boxShadow:
                          widget.channelEditEnabled && _hoveredIndex == index
                          ? <BoxShadow>[
                              BoxShadow(
                                color: widget.colors[index].withValues(
                                  alpha: 0.45,
                                ),
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
                          color: widget.removed[index]
                              ? Colors.white38
                              : widget.channelEditEnabled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.95),
                          fontSize: 12,
                          fontWeight: widget.channelEditEnabled
                              ? FontWeight.w700
                              : FontWeight.w500,
                          decoration: widget.removed[index]
                              ? TextDecoration.none
                              : widget.channelEditEnabled
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
  });

  final List<TimeMarker> markers;
  final ValueChanged<TimeMarker> onDelete;
  final ValueChanged<TimeMarker> onFocus;

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) {
      return const Text(
        'No markers placed yet.',
        style: TextStyle(color: Colors.white70),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: markers
          .map((TimeMarker marker) {
            final bool isArtifact = marker.markerType == MarkerType.artifact;
            final Color markerColor = _markerDisplayColor(marker);
            return _HoverHighlightFrame(
              glowColor: markerColor,
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
                selected: isArtifact,
                selectedColor: markerColor.withValues(alpha: 0.22),
                onPressed: () => onFocus(marker),
                onDeleted: () => onDelete(marker),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _MarkerLabelGroup {
  const _MarkerLabelGroup({required this.label, required this.markers});

  final String label;
  final List<TimeMarker> markers;
}

class _MarkerSection extends StatelessWidget {
  const _MarkerSection({
    required this.expanded,
    required this.markers,
    required this.onRecode,
    required this.labelExpandedMap,
    required this.onToggleLabelExpanded,
    required this.onToggle,
    required this.onDelete,
    required this.onDeleteLabel,
    required this.onFocus,
  });

  final bool expanded;
  final List<TimeMarker> markers;
  final Future<void> Function()? onRecode;
  final Map<String, dynamic> labelExpandedMap;
  final void Function(String label, bool expanded) onToggleLabelExpanded;
  final ValueChanged<bool> onToggle;
  final ValueChanged<TimeMarker> onDelete;
  final ValueChanged<String> onDeleteLabel;
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
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Markers (${markers.length})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onRecode != null)
                    TextButton(
                      onPressed: onRecode,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Edit markers'),
                    ),
                ],
              ),
            ),
            if (expanded) ...<Widget>[
              const SizedBox(height: 8),
              ..._groupedMarkers().map((_MarkerLabelGroup group) {
                final bool isExpanded =
                    (labelExpandedMap[group.label] as bool?) ?? false;
                final Color groupColor = _markerDisplayColor(
                  group.markers.first,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _HoverHighlightFrame(
                            glowColor: groupColor,
                            child: InkWell(
                              onTap: () => onToggleLabelExpanded(
                                group.label,
                                !isExpanded,
                              ),
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
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
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
                                    Tooltip(
                                      message:
                                          'Delete all ${group.label} markers',
                                      child: IconButton(
                                        onPressed: () =>
                                            onDeleteLabel(group.label),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                        ),
                                        color: Colors.white70,
                                        visualDensity: VisualDensity.compact,
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
          (MapEntry<String, List<TimeMarker>> entry) =>
              _MarkerLabelGroup(label: entry.key, markers: entry.value),
        )
        .toList(growable: false);
  }
}

Color _markerDisplayColor(TimeMarker marker) {
  final String? interactiveStatus = marker
      .attributes['brainstory.artifactStatus']
      ?.toString();
  final String? interactiveSource = marker
      .attributes['brainstory.artifactSource']
      ?.toString();
  return _interactiveMarkerColor(
    interactiveStatus: interactiveStatus,
    interactiveSource: interactiveSource,
    fallbackMarkerType: marker.markerType,
  );
}

Color _interactiveMarkerColor({
  String? interactiveStatus,
  String? interactiveSource,
  String? fallbackMarkerType,
}) {
  if (interactiveStatus == InteractiveArtifactDetectionNodeType.pendingStatus) {
    return const Color(0xFFFFA630);
  }
  if (interactiveSource == 'exemplar') {
    return const Color(0xFFFF4D8D);
  }
  if (interactiveStatus ==
      InteractiveArtifactDetectionNodeType.acceptedStatus) {
    return const Color(0xFFFF5A36);
  }
  return fallbackMarkerType == MarkerType.artifact
      ? const Color(0xFFFF6B35)
      : const Color(0xFFFFC145);
}

Color _complementColor(Color color) {
  final int argb = color.toARGB32();
  final int alpha = (argb >> 24) & 0xFF;
  final int red = (argb >> 16) & 0xFF;
  final int green = (argb >> 8) & 0xFF;
  final int blue = argb & 0xFF;
  return Color.fromARGB(alpha, 255 - red, 255 - green, 255 - blue);
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
      interactiveStatus ==
          InteractiveArtifactDetectionNodeType.acceptedStatus) {
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
  canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
}

class _InteractiveArtifactReviewSection extends StatelessWidget {
  const _InteractiveArtifactReviewSection({
    required this.labelChoices,
    required this.channelLabels,
    required this.channelCoordinates,
    required this.pixelsPerSecond,
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
  final List<String> channelLabels;
  final Map<String, ChannelCoordinate> channelCoordinates;
  final double pixelsPerSecond;
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap any exemplar or candidate to jump there. Alt+drag adds ${labelChoices.where((String label) => label != 'blink').join(', ')}.',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        if (templates.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          ArtifactTemplatePreview(
            templates: templates,
            channelLabels: channelLabels,
            channelCoordinates: channelCoordinates,
            pixelsPerSecond: pixelsPerSecond,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: templates
                .map((ArtifactTemplateSummary template) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: artifactTemplateColor(
                        template.label,
                      ).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: artifactTemplateColor(
                          template.label,
                        ).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${template.label}: ${template.exemplarCount} exemplar${template.exemplarCount == 1 ? '' : 's'} • ${template.sampleCount} samples',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                })
                .toList(growable: false),
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
              children: exemplars
                  .map((ArtifactExemplarData exemplar) {
                    final Color labelColor = _interactiveMarkerColor(
                      interactiveSource: 'exemplar',
                    );
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
                  })
                  .toList(growable: false),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _SectionHeader(
              title: 'Candidate matches',
              count: pendingCandidates.length + acceptedCandidates.length,
              expanded: candidatesExpanded,
              onToggle: () => onToggleCandidates(!candidatesExpanded),
            ),
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
              children: pendingCandidates
                  .map((ArtifactCandidateData candidate) {
                    final Color markerColor = _interactiveMarkerColor(
                      interactiveStatus:
                          InteractiveArtifactDetectionNodeType.pendingStatus,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: markerColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onFocusPendingCandidate(candidate),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: markerColor,
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
                  })
                  .toList(growable: false),
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
              children: acceptedCandidates
                  .map((ArtifactCandidateData candidate) {
                    final Color labelColor = _interactiveMarkerColor(
                      interactiveStatus:
                          InteractiveArtifactDetectionNodeType.acceptedStatus,
                    );
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
                  })
                  .toList(growable: false),
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
            expanded ? Icons.expand_more : Icons.chevron_right,
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

class _DraftManifestItem {
  const _DraftManifestItem({
    required this.label,
    required this.detail,
    this.color,
  });

  final String label;
  final String detail;
  final Color? color;
}

class _SavedChangesSummary {
  const _SavedChangesSummary({required this.title, required this.items});

  final String title;
  final List<_DraftManifestItem> items;
}

class _BoundaryCombinationDraft {
  _BoundaryCombinationDraft({required this.id});

  final int id;
  String? startLabel;
  String? stopLabel;
  String blockLabel = 'Block';
  bool replaceBoundaries = true;
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
          final int lastTick = math.min(
            durationSeconds.ceil(),
            endSeconds.ceil(),
          );

          return Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (int second = firstTick; second <= lastTick; second++)
                  ...() {
                    final double tickX = (second * pixelsPerSecond) - offset;
                    const double labelWidth = 44;
                    final double labelLeft = tickX - (labelWidth / 2);
                    return <Widget>[
                      Positioned(
                        left: tickX - 0.5,
                        top: 0,
                        child: Container(
                          width: 1,
                          height: 8,
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      Positioned(
                        left: labelLeft,
                        top: 10,
                        child: SizedBox(
                          width: labelWidth,
                          child: Text(
                            '${second}s',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ];
                  }(),
              ],
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
              final double currentOffset = controller.hasClients
                  ? controller.offset
                  : 0.0;
              final double normalizedOffset = maxOffset == 0
                  ? 0.0
                  : (currentOffset / maxOffset).clamp(0.0, 1.0);
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
                  final double nextLeft = (thumbLeft + details.delta.dx).clamp(
                    0.0,
                    travel,
                  );
                  controller.jumpTo((nextLeft / travel) * maxOffset);
                },
                onTapDown: (TapDownDetails details) {
                  if (!controller.hasClients || maxOffset == 0) {
                    return;
                  }
                  final double centeredLeft =
                      (details.localPosition.dx - (thumbWidth / 2)).clamp(
                        0.0,
                        travel,
                      );
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
  const _BrowserMessage({required this.title, required this.body});

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
    required this.sampleCount,
    required this.sampleRate,
    required this.channelHeight,
    required this.pixelsPerSecond,
    required this.yScaleUv,
    required this.showSignals,
    required this.removeDc,
    required this.colors,
    required this.removedRows,
    required this.markers,
    this.selectionStartX,
    this.selectionEndX,
    this.hoveredMarkerReferenceId,
    required this.horizontalOffset,
    required this.verticalOffset,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final List<List<double>> channels;
  final List<String> channelLabels;
  final int sampleCount;
  final double sampleRate;
  final double channelHeight;
  final double pixelsPerSecond;
  final double yScaleUv;
  final bool showSignals;
  final bool removeDc;
  final List<Color> colors;
  final List<bool> removedRows;
  final List<TimeMarker> markers;
  final double? selectionStartX;
  final double? selectionEndX;
  final String? hoveredMarkerReferenceId;
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
        : math.min(sampleCount, (endTime * sampleRate).ceil() + 1);
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
      final double markerEndX =
          ((marker.onsetMicros + marker.durationMicros) / 1000000.0) *
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
      final double scaleBarX = horizontalOffset + viewportWidth - 14;
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
          text: '${yScaleUv.toStringAsFixed(0)} μV',
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
        Offset(
          scaleBarX - scaleLabelPainter.width - 8,
          scaleBarTop + (scaleBarHeight / 2) - (scaleLabelPainter.height / 2),
        ),
      );
    }

    if (showSignals) {
      final double verticalScale = channelHeight * 0.35;
      final double pixelsPerUv = verticalScale / math.max(1.0, yScaleUv);
      for (
        int channelIndex = firstChannel;
        channelIndex <= lastChannel;
        channelIndex++
      ) {
        final double centerY =
            (channelIndex * channelHeight) + (channelHeight / 2);
        canvas.drawLine(
          Offset(horizontalOffset, centerY),
          Offset(horizontalOffset + viewportWidth, centerY),
          baselinePaint,
        );

        if (removedRows[channelIndex]) {
          continue;
        }
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
        for (
          int sampleIndex = startSample;
          sampleIndex < endSample;
          sampleIndex += stride
        ) {
          final double x = (sampleIndex / sampleRate) * pixelsPerSecond;
          final double y =
              centerY - ((samples[sampleIndex] - dcOffset) * pixelsPerUv);
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
            centerY - ((samples[lastSampleIndex] - dcOffset) * pixelsPerUv),
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
    }

    for (final TimeMarker marker in visibleMarkers) {
      final double x = marker.timeSeconds * pixelsPerSecond;
      final double markerEndX =
          ((marker.onsetMicros + marker.durationMicros) / 1000000.0) *
          pixelsPerSecond;
      final Color markerColor = _markerDisplayColor(marker);
      final String markerReferenceId =
          '${marker.label}:${marker.onsetMicros}:${marker.durationMicros}:${marker.markerType}';
      final bool hovered = hoveredMarkerReferenceId == markerReferenceId;
      final String? interactiveStatus = marker
          .attributes['brainstory.artifactStatus']
          ?.toString();
      final String? interactiveSource = marker
          .attributes['brainstory.artifactSource']
          ?.toString();
      _drawMarkerGuideLine(
        canvas: canvas,
        x: x,
        top: verticalOffset,
        bottom: verticalOffset + viewportHeight,
        color: markerColor,
        extraStrokeWidth: hovered ? 1.2 : 0.0,
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
          extraStrokeWidth: hovered ? 1.2 : 0.0,
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
            shadows: const <Shadow>[Shadow(blurRadius: 8, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (hovered) {
        final Rect highlightRect = Rect.fromLTWH(
          x,
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
      textPainter.paint(canvas, Offset(x + 4, verticalOffset + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _RawSignalPainter oldDelegate) {
    return oldDelegate.channels != channels ||
        oldDelegate.sampleCount != sampleCount ||
        oldDelegate.sampleRate != sampleRate ||
        oldDelegate.channelHeight != channelHeight ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.yScaleUv != yScaleUv ||
        oldDelegate.showSignals != showSignals ||
        oldDelegate.removeDc != removeDc ||
        oldDelegate.markers != markers ||
        oldDelegate.colors != colors ||
        oldDelegate.removedRows != removedRows ||
        oldDelegate.selectionStartX != selectionStartX ||
        oldDelegate.selectionEndX != selectionEndX ||
        oldDelegate.hoveredMarkerReferenceId != hoveredMarkerReferenceId ||
        oldDelegate.horizontalOffset != horizontalOffset ||
        oldDelegate.verticalOffset != verticalOffset ||
        oldDelegate.viewportWidth != viewportWidth ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}
