import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/node.dart';
import 'canvas_logic.dart';
import 'dataset_panel.dart';
import 'visualization_panel.dart';

class _UndoIntent extends Intent {
  const _UndoIntent();
}

enum _KeyboardPane {
  nodeSelector,
  canvas,
  projectActions,
  datasetStatus,
  visualization,
}

class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.logic});

  final CanvasLogic logic;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  static const bool _showEmbeddedVisualizationPreview = false;

  late final FocusNode _keyboardFocusNode;
  late final ScrollController _verticalScrollController;
  late final ScrollController _horizontalScrollController;
  final GlobalKey _canvasKey = GlobalKey();
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  _KeyboardPane _keyboardPane = _KeyboardPane.canvas;
  Timer? _recentJobsCollapseTimer;
  bool _recentJobsCollapsed = true;

  CanvasLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode();
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    logic.runActivity.addListener(_handleRunActivityChange);
  }

  @override
  void dispose() {
    logic.runActivity.removeListener(_handleRunActivityChange);
    _recentJobsCollapseTimer?.cancel();
    _keyboardFocusNode.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compactRail = constraints.maxWidth < 1200;
        final double sideRailWidth = compactRail ? 300 : 360;
        final double leftRailWidth =
            ((constraints.maxWidth - sideRailWidth) * 0.28).clamp(260.0, 340.0);
        final double canvasViewportWidth =
            (constraints.maxWidth - sideRailWidth - leftRailWidth).clamp(
              200.0,
              double.infinity,
            );
        final Size canvasSize = logic.canvasSizeForViewport(
          Size(canvasViewportWidth, constraints.maxHeight),
        );

        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            logic.runActivity,
            logic.recentRunJobs,
            logic.queuedRunJobs,
            logic.processingResponsiveness,
            logic.visualizerPriorityActive,
          ]),
          builder: (BuildContext context, Widget? child) {
            final RunActivity? runActivity = logic.runActivity.value;
            final bool interfaceLocked = runActivity?.locksInterface ?? false;
            return Stack(
              children: <Widget>[
                Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.delete):
                        ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                        _UndoIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (ActivateIntent intent) {
                          if (logic.selectedMutationBlocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'That edit is locked while the current job is preparing, running, or committing.',
                                ),
                              ),
                            );
                            return null;
                          }
                          setState(() {
                            if (logic.selectedConnectionIndex != null) {
                              logic.deleteSelectedConnection();
                            } else {
                              logic.deleteSelected();
                            }
                          });
                          return null;
                        },
                      ),
                      _UndoIntent: CallbackAction<_UndoIntent>(
                        onInvoke: (_UndoIntent intent) {
                          if (logic.runActivity.value != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Undo is paused until the active job finishes.',
                                ),
                              ),
                            );
                            return null;
                          }
                          String? label;
                          setState(() {
                            label = logic.undoLast();
                          });
                          if (label != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Undid $label.')),
                            );
                          }
                          return null;
                        },
                      ),
                    },
                    child: Focus(
                      focusNode: _keyboardFocusNode,
                      autofocus: true,
                      onKeyEvent: _handleKeyboardEvent,
                      child: Row(
                        children: <Widget>[
                          logic.sidebar(
                            width: leftRailWidth,
                            publish: () async {
                              await logic.showPublishDialog(context);
                            },
                            memory: () async {
                              await logic.showMemoryManagerDialog(
                                context,
                                update: () => setState(() {}),
                              );
                            },
                            load: () async {
                              await logic.loadBrainStory(context);
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            export: () async {
                              await logic.exportBrainStory(context);
                            },
                            clear: () => setState(() => logic.clearAll()),
                            update: () => setState(() {}),
                          ),
                          Expanded(
                            child: ClipRect(
                              child: Scrollbar(
                                controller: _verticalScrollController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _verticalScrollController,
                                  primary: false,
                                  scrollDirection: Axis.vertical,
                                  child: Scrollbar(
                                    controller: _horizontalScrollController,
                                    thumbVisibility: true,
                                    notificationPredicate:
                                        (ScrollNotification notification) {
                                          return notification.metrics.axis ==
                                              Axis.horizontal;
                                        },
                                    child: SingleChildScrollView(
                                      controller: _horizontalScrollController,
                                      primary: false,
                                      scrollDirection: Axis.horizontal,
                                      child: GestureDetector(
                                        onTapDown: (TapDownDetails details) {
                                          _keyboardFocusNode.requestFocus();
                                          final Offset canvasOffset =
                                              _globalToRawCanvasOffset(
                                                details.globalPosition,
                                              );
                                          setState(() {
                                            if (HardwareKeyboard
                                                    .instance
                                                    .isControlPressed &&
                                                logic.deleteConnectionAt(
                                                  canvasOffset,
                                                )) {
                                              return;
                                            }
                                            if (!logic.selectConnectionAt(
                                              canvasOffset,
                                            )) {
                                              logic.selectedConnectionIndex =
                                                  null;
                                              logic.selectedNodeIds.clear();
                                              logic.selectedNodeId = null;
                                              logic.clearConnectionDraft();
                                            }
                                          });
                                        },
                                        onPanStart: (DragStartDetails details) {
                                          _keyboardFocusNode.requestFocus();
                                          final Offset canvasOffset =
                                              _globalToRawCanvasOffset(
                                                details.globalPosition,
                                              );
                                          setState(() {
                                            _selectionStart = canvasOffset;
                                            _selectionCurrent = canvasOffset;
                                            logic.selectedConnectionIndex =
                                                null;
                                            logic.clearConnectionDraft();
                                          });
                                        },
                                        onPanUpdate:
                                            (DragUpdateDetails details) {
                                              final Offset canvasOffset =
                                                  _globalToRawCanvasOffset(
                                                    details.globalPosition,
                                                  );
                                              setState(() {
                                                _selectionCurrent =
                                                    canvasOffset;
                                              });
                                            },
                                        onPanEnd: (DragEndDetails details) {
                                          final Offset? start = _selectionStart;
                                          final Offset? current =
                                              _selectionCurrent;
                                          setState(() {
                                            _selectionStart = null;
                                            _selectionCurrent = null;
                                            if (start != null &&
                                                current != null) {
                                              logic.selectNodesInRect(
                                                Rect.fromPoints(
                                                  start,
                                                  current,
                                                ).inflate(2),
                                              );
                                            }
                                          });
                                        },
                                        onPanCancel: () {
                                          setState(() {
                                            _selectionStart = null;
                                            _selectionCurrent = null;
                                          });
                                        },
                                        onSecondaryTapDown:
                                            (TapDownDetails details) {
                                              setState(() {
                                                if (!logic.deleteConnectionAt(
                                                  _globalToRawCanvasOffset(
                                                    details.globalPosition,
                                                  ),
                                                )) {
                                                  logic.selectedConnectionIndex =
                                                      null;
                                                }
                                              });
                                            },
                                        child: SizedBox(
                                          key: _canvasKey,
                                          width: canvasSize.width,
                                          height: canvasSize.height,
                                          child: Stack(
                                            children: <Widget>[
                                              ...logic.connectionWidgets(),
                                              ...logic.nodeWidgets(
                                                context: context,
                                                update: () => setState(() {}),
                                                translateDropOffset:
                                                    _globalToCanvasOffset,
                                                openVisualizationWindow:
                                                    _openVisualizationWindow,
                                              ),
                                              if (_selectionStart != null &&
                                                  _selectionCurrent != null)
                                                Positioned.fromRect(
                                                  rect: Rect.fromPoints(
                                                    _selectionStart!,
                                                    _selectionCurrent!,
                                                  ),
                                                  child: IgnorePointer(
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        color:
                                                            const Color(
                                                              0xFF6DD3FF,
                                                            ).withValues(
                                                              alpha: 0.10,
                                                            ),
                                                        border: Border.all(
                                                          color:
                                                              const Color(
                                                                0xFF6DD3FF,
                                                              ).withValues(
                                                                alpha: 0.88,
                                                              ),
                                                          width: 1.5,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
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
                          ),
                          SizedBox(
                            width: sideRailWidth,
                            child: Column(
                              children: <Widget>[
                                Expanded(
                                  child: DatasetPanel(
                                    logic: logic,
                                    onChanged: () => setState(() {}),
                                  ),
                                ),
                                if (_showEmbeddedVisualizationPreview)
                                  Expanded(
                                    flex: 2,
                                    child: VisualizationPanel(
                                      logic: logic,
                                      onChanged: () => setState(() {}),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!interfaceLocked)
                  _RecentJobsOverlay(
                    runActivity: runActivity,
                    jobs: logic.recentRunJobs.value,
                    queuedJobs: logic.queuedRunJobs.value,
                    processingResponsiveness:
                        logic.processingResponsiveness.value,
                    visualizerPriorityActive:
                        logic.visualizerPriorityActive.value,
                    collapsed: _recentJobsCollapsed,
                    onToggleCollapsed: () {
                      setState(() {
                        _recentJobsCollapsed = !_recentJobsCollapsed;
                      });
                      if (_recentJobsCollapsed) {
                        _scheduleRecentJobsCollapse();
                      } else {
                        _recentJobsCollapseTimer?.cancel();
                      }
                    },
                  ),
                if (interfaceLocked && runActivity != null)
                  _ResourceLockOverlay(runActivity: runActivity),
              ],
            );
          },
        );
      },
    );
  }

  Offset _globalToCanvasOffset(Offset globalOffset) {
    final RenderBox? renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return globalOffset;
    }
    final Offset localOffset = renderBox.globalToLocal(globalOffset);
    final bool altSnapOverride = HardwareKeyboard.instance.isAltPressed;
    if (altSnapOverride) {
      return localOffset;
    }
    return logic.snapToGrid(localOffset);
  }

  void _handleRunActivityChange() {
    final bool running = logic.runActivity.value != null;
    if (running) {
      _recentJobsCollapseTimer?.cancel();
      if (_recentJobsCollapsed && mounted) {
        setState(() {
          _recentJobsCollapsed = false;
        });
      }
      return;
    }
    _scheduleRecentJobsCollapse();
  }

  void _scheduleRecentJobsCollapse() {
    _recentJobsCollapseTimer?.cancel();
    if (logic.recentRunJobs.value.isEmpty) {
      return;
    }
    _recentJobsCollapseTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || logic.runActivity.value != null) {
        return;
      }
      setState(() {
        _recentJobsCollapsed = true;
      });
    });
  }

  Offset _globalToRawCanvasOffset(Offset globalOffset) {
    final RenderBox? renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return globalOffset;
    }
    return renderBox.globalToLocal(globalOffset);
  }

  KeyEventResult _handleKeyboardEvent(FocusNode node, KeyEvent event) {
    if (logic.interfaceLocked) {
      return event is KeyDownEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final LogicalKeyboardKey key = event.logicalKey;
    if ((key == LogicalKeyboardKey.altLeft ||
            key == LogicalKeyboardKey.altRight) &&
        _keyboardPane == _KeyboardPane.canvas) {
      _showFocusedNodeContextMenu();
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      final _KeyboardPane? pane = _keyboardPaneForAltShortcut(key);
      if (pane != null) {
        setState(() {
          _keyboardPane = pane;
        });
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.tab) {
      setState(() {
        _cycleKeyboardPane(reverse: HardwareKeyboard.instance.isShiftPressed);
      });
      return KeyEventResult.handled;
    }

    if (_keyboardPane != _KeyboardPane.canvas) {
      return KeyEventResult.ignored;
    }

    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.enter) {
      _openFocusedNodeParameters();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter) {
      _activateFocusedNode();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _moveKeyboardNodeFocus(key);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  _KeyboardPane? _keyboardPaneForAltShortcut(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.digit1:
      case LogicalKeyboardKey.numpad1:
        return _KeyboardPane.nodeSelector;
      case LogicalKeyboardKey.digit2:
      case LogicalKeyboardKey.numpad2:
        return _KeyboardPane.canvas;
      case LogicalKeyboardKey.digit3:
      case LogicalKeyboardKey.numpad3:
        return _KeyboardPane.projectActions;
      case LogicalKeyboardKey.digit4:
      case LogicalKeyboardKey.numpad4:
        return _KeyboardPane.datasetStatus;
      case LogicalKeyboardKey.digit5:
      case LogicalKeyboardKey.numpad5:
        return _KeyboardPane.visualization;
      default:
        return null;
    }
  }

  void _cycleKeyboardPane({required bool reverse}) {
    final List<_KeyboardPane> panes = _KeyboardPane.values;
    final int currentIndex = panes.indexOf(_keyboardPane);
    final int offset = reverse ? -1 : 1;
    int nextIndex = currentIndex + offset;
    if (nextIndex < 0) {
      nextIndex = panes.length - 1;
    } else if (nextIndex >= panes.length) {
      nextIndex = 0;
    }
    _keyboardPane = panes[nextIndex];
  }

  void _moveKeyboardNodeFocus(LogicalKeyboardKey key) {
    if (logic.nodes.isEmpty) {
      return;
    }
    final NodeModel current =
        logic.keyboardFocusedNode ??
        _nodeById(logic.selectedNodeId) ??
        logic.nodes.first;
    final NodeModel next =
        _nearestNodeInDirection(current, key) ??
        _wrappedNodeInDirection(current, key);
    setState(() {
      logic.setKeyboardFocusedNode(next);
    });
    _scrollNodeIntoView(next);
  }

  void _activateFocusedNode() {
    if (logic.nodes.isEmpty) {
      return;
    }
    final NodeModel node =
        logic.keyboardFocusedNode ??
        _nodeById(logic.selectedNodeId) ??
        logic.nodes.first;
    final bool selectedSingleNode =
        logic.selectedNodeId == node.id && logic.selectedNodeIds.length <= 1;
    if (selectedSingleNode && logic.canVisualizeNode(node)) {
      _openVisualizationWindow(node);
      return;
    }
    setState(() {
      logic.activateNodeFromKeyboard(node);
    });
  }

  void _openFocusedNodeParameters() {
    if (logic.nodes.isEmpty) {
      return;
    }
    final NodeModel node =
        logic.keyboardFocusedNode ??
        _nodeById(logic.selectedNodeId) ??
        logic.nodes.first;
    setState(() {
      logic.setKeyboardFocusedNode(node);
    });
    logic.openNodeEditorFromKeyboard(
      context: context,
      node: node,
      update: () => setState(() {}),
    );
  }

  void _showFocusedNodeContextMenu() {
    final NodeModel? node =
        logic.keyboardFocusedNode ??
        _nodeById(logic.selectedNodeId) ??
        (logic.nodes.isEmpty ? null : logic.nodes.first);
    if (node == null) {
      return;
    }
    final RenderBox? renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final Offset globalPosition = renderBox.localToGlobal(
      node.position + const Offset(80, 36),
    );
    setState(() {
      logic.setKeyboardFocusedNode(node);
      logic.selectedNodeId = node.id;
      logic.selectedNodeIds
        ..clear()
        ..add(node.id);
    });
    unawaited(
      logic.showNodeContextMenu(
        context: context,
        node: node,
        globalPosition: globalPosition,
        update: () => setState(() {}),
        openVisualizationWindow: _openVisualizationWindow,
      ),
    );
  }

  NodeModel? _nearestNodeInDirection(
    NodeModel current,
    LogicalKeyboardKey key,
  ) {
    final Offset currentCenter = _nodeCenter(current);
    NodeModel? best;
    double? bestScore;
    for (final NodeModel candidate in logic.nodes) {
      if (candidate.id == current.id) {
        continue;
      }
      final Offset delta = _nodeCenter(candidate) - currentCenter;
      final double primaryDistance;
      final double perpendicularDistance;
      if (key == LogicalKeyboardKey.arrowRight) {
        if (delta.dx <= 0) continue;
        primaryDistance = delta.dx;
        perpendicularDistance = delta.dy.abs();
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        if (delta.dx >= 0) continue;
        primaryDistance = -delta.dx;
        perpendicularDistance = delta.dy.abs();
      } else if (key == LogicalKeyboardKey.arrowDown) {
        if (delta.dy <= 0) continue;
        primaryDistance = delta.dy;
        perpendicularDistance = delta.dx.abs();
      } else {
        if (delta.dy >= 0) continue;
        primaryDistance = -delta.dy;
        perpendicularDistance = delta.dx.abs();
      }
      final double score = primaryDistance + (perpendicularDistance * 0.65);
      if (bestScore == null || score < bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  NodeModel _wrappedNodeInDirection(NodeModel current, LogicalKeyboardKey key) {
    final List<NodeModel> ordered = List<NodeModel>.from(logic.nodes);
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft) {
      ordered.sort((NodeModel a, NodeModel b) {
        final int xCompare = a.position.dx.compareTo(b.position.dx);
        return xCompare == 0
            ? a.position.dy.compareTo(b.position.dy)
            : xCompare;
      });
    } else {
      ordered.sort((NodeModel a, NodeModel b) {
        final int yCompare = a.position.dy.compareTo(b.position.dy);
        return yCompare == 0
            ? a.position.dx.compareTo(b.position.dx)
            : yCompare;
      });
    }
    final int currentIndex = ordered.indexWhere(
      (NodeModel node) => node.id == current.id,
    );
    if (currentIndex < 0) {
      return ordered.first;
    }
    final int offset =
        key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp
        ? -1
        : 1;
    return ordered[(currentIndex + offset) % ordered.length];
  }

  Offset _nodeCenter(NodeModel node) {
    return node.position + const Offset(80, 36);
  }

  NodeModel? _nodeById(String? id) {
    if (id == null) {
      return null;
    }
    for (final NodeModel node in logic.nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  void _scrollNodeIntoView(NodeModel node) {
    const double nodeWidth = 160;
    const double nodeHeight = 72;
    const double margin = 48;
    if (_horizontalScrollController.hasClients) {
      final double current = _horizontalScrollController.offset;
      final double viewport =
          _horizontalScrollController.position.viewportDimension;
      double target = current;
      if (node.position.dx < current + margin) {
        target = (node.position.dx - margin)
            .clamp(0, _horizontalScrollController.position.maxScrollExtent)
            .toDouble();
      } else if (node.position.dx + nodeWidth > current + viewport - margin) {
        target = (node.position.dx + nodeWidth + margin - viewport)
            .clamp(0, _horizontalScrollController.position.maxScrollExtent)
            .toDouble();
      }
      if (target != current) {
        _horizontalScrollController.jumpTo(target);
      }
    }
    if (_verticalScrollController.hasClients) {
      final double current = _verticalScrollController.offset;
      final double viewport =
          _verticalScrollController.position.viewportDimension;
      double target = current;
      if (node.position.dy < current + margin) {
        target = (node.position.dy - margin)
            .clamp(0, _verticalScrollController.position.maxScrollExtent)
            .toDouble();
      } else if (node.position.dy + nodeHeight > current + viewport - margin) {
        target = (node.position.dy + nodeHeight + margin - viewport)
            .clamp(0, _verticalScrollController.position.maxScrollExtent)
            .toDouble();
      }
      if (target != current) {
        _verticalScrollController.jumpTo(target);
      }
    }
  }

  void _openVisualizationWindow(NodeModel node) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) =>
            VisualizationFullscreenPage(logic: logic, nodeId: node.id),
      ),
    );
  }
}

class _RecentJobsOverlay extends StatelessWidget {
  const _RecentJobsOverlay({
    required this.runActivity,
    required this.jobs,
    required this.queuedJobs,
    required this.processingResponsiveness,
    required this.visualizerPriorityActive,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final RunActivity? runActivity;
  final List<RunJobEntry> jobs;
  final List<RunJobEntry> queuedJobs;
  final ProcessingResponsiveness processingResponsiveness;
  final bool visualizerPriorityActive;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    if (runActivity == null &&
        !visualizerPriorityActive &&
        queuedJobs.isEmpty &&
        jobs.isEmpty) {
      return const SizedBox.shrink();
    }

    if (collapsed && runActivity == null && !visualizerPriorityActive) {
      return Positioned(
        right: 16,
        bottom: 16,
        child: FilledButton.tonalIcon(
          onPressed: onToggleCollapsed,
          icon: const Icon(Icons.history, size: 18),
          label: Text('Recent jobs (${jobs.length})'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.72),
            foregroundColor: Colors.white,
          ),
        ),
      );
    }

    return Positioned(
      right: 16,
      bottom: 16,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Recent jobs',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleCollapsed,
                      icon: const Icon(Icons.expand_more),
                      color: Colors.white70,
                      tooltip: 'Collapse',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (runActivity != null) ...<Widget>[
                  _RecentJobCard(
                    title: runActivity!.label,
                    detail: runActivity!.detail,
                    statusLabel: _activityStatusLabel(runActivity!),
                    color: _activityStatusColor(runActivity!),
                  ),
                  const SizedBox(height: 8),
                ],
                if (visualizerPriorityActive) ...<Widget>[
                  const _RecentJobCard(
                    title: 'Visualizer priority',
                    detail:
                        'Visualizer work is running monolithically; queued processing is paused.',
                    statusLabel: 'Priority',
                    color: Color(0xFFFFD166),
                  ),
                  const SizedBox(height: 8),
                ],
                if (runActivity != null) ...<Widget>[
                  _RecentJobCard(
                    title: 'Execution chunking',
                    detail:
                        '${processingResponsiveness.label}: ${processingResponsiveness.description}',
                    statusLabel: processingResponsiveness.label,
                    color: const Color(0xFF6DD3FF),
                  ),
                  const SizedBox(height: 8),
                ],
                if (queuedJobs.isNotEmpty) ...<Widget>[
                  ...queuedJobs.map(
                    (RunJobEntry job) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecentJobCard(
                        title: job.label,
                        detail: job.detail,
                        statusLabel: 'Queued',
                        color: const Color(0xFFC0CAD4),
                      ),
                    ),
                  ),
                ],
                if (jobs.isEmpty && queuedJobs.isEmpty)
                  const Text(
                    'No completed jobs yet.',
                    style: TextStyle(color: Colors.white60),
                  )
                else
                  ...jobs.map(
                    (RunJobEntry job) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecentJobCard(
                        title: job.label,
                        detail: _jobDetail(job),
                        statusLabel: job.state == RunJobState.done
                            ? 'Done'
                            : 'Failed',
                        color: job.state == RunJobState.done
                            ? const Color(0xFF43C26B)
                            : const Color(0xFFFF8A65),
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

  String _jobDetail(RunJobEntry job) {
    final String base = job.detail.trim();
    final int seconds = job.elapsed.inSeconds;
    final String durationLabel = seconds <= 0 ? '<1s' : '${seconds}s';
    return base.isEmpty
        ? 'Finished in $durationLabel.'
        : '$base • $durationLabel';
  }

  String _activityStatusLabel(RunActivity activity) {
    return switch (activity.phase) {
      RunActivityPhase.initializing => 'Preparing',
      RunActivityPhase.running => 'Running',
      RunActivityPhase.finalizing => 'Committing',
    };
  }

  Color _activityStatusColor(RunActivity activity) {
    return switch (activity.phase) {
      RunActivityPhase.initializing => const Color(0xFFFFD166),
      RunActivityPhase.running => const Color(0xFF7FE36A),
      RunActivityPhase.finalizing => const Color(0xFF6DD3FF),
    };
  }
}

class _ResourceLockOverlay extends StatelessWidget {
  const _ResourceLockOverlay({required this.runActivity});

  final RunActivity runActivity;

  @override
  Widget build(BuildContext context) {
    final String detail = runActivity.detail.trim();
    final bool initializing =
        runActivity.phase == RunActivityPhase.initializing;
    final String title = initializing
        ? 'Initializing resources'
        : 'Committing results';
    final Color accent = initializing
        ? const Color(0xFFFFD166)
        : const Color(0xFF6DD3FF);

    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.56),
            semanticsLabel: 'BrainStory is busy',
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF11151B),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: accent.withValues(alpha: 0.58)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 32,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: accent,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  runActivity.label,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (detail.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 18),
                        Text(
                          detail,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          color: accent,
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'The interface only locks during short setup and commit phases. Long processing continues in the jobs panel so more work can be queued.',
                        style: TextStyle(
                          color: Colors.white60,
                          height: 1.35,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentJobCard extends StatelessWidget {
  const _RecentJobCard({
    required this.title,
    required this.detail,
    required this.statusLabel,
    required this.color,
  });

  final String title;
  final String detail;
  final String statusLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withValues(alpha: 0.65)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (detail.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                detail,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
