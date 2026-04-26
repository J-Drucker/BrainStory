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
  const CanvasView({
    super.key,
    required this.logic,
  });

  final CanvasLogic logic;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  static const bool _quickVisualizerEnabled = false;

  late final FocusNode _keyboardFocusNode;
  late final ScrollController _verticalScrollController;
  late final ScrollController _horizontalScrollController;
  final GlobalKey _canvasKey = GlobalKey();
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  _KeyboardPane _keyboardPane = _KeyboardPane.canvas;

  CanvasLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode();
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
  }

  @override
  void dispose() {
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
            (constraints.maxWidth - sideRailWidth - leftRailWidth)
                .clamp(200.0, double.infinity);
        final Size canvasSize = logic.canvasSizeForViewport(
          Size(canvasViewportWidth, constraints.maxHeight),
        );

        return ValueListenableBuilder<RunActivity?>(
          valueListenable: logic.runActivity,
          builder: (BuildContext context, RunActivity? runActivity, Widget? child) {
            return Stack(
              children: <Widget>[
                Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.delete): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                        _UndoIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (ActivateIntent intent) {
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
                                notificationPredicate: (ScrollNotification notification) {
                                  return notification.metrics.axis == Axis.horizontal;
                                },
                                child: SingleChildScrollView(
                                  controller: _horizontalScrollController,
                                  primary: false,
                                  scrollDirection: Axis.horizontal,
                                  child: GestureDetector(
                                    onTapDown: (TapDownDetails details) {
                                      _keyboardFocusNode.requestFocus();
                                      final Offset canvasOffset =
                                          _globalToRawCanvasOffset(details.globalPosition);
                                      setState(() {
                                        if (HardwareKeyboard.instance.isControlPressed &&
                                            logic.deleteConnectionAt(canvasOffset)) {
                                          return;
                                        }
                                        if (!logic.selectConnectionAt(canvasOffset)) {
                                          logic.selectedConnectionIndex = null;
                                          logic.selectedNodeIds.clear();
                                          logic.selectedNodeId = null;
                                          logic.clearConnectionDraft();
                                        }
                                      });
                                    },
                                    onPanStart: (DragStartDetails details) {
                                      _keyboardFocusNode.requestFocus();
                                      final Offset canvasOffset =
                                          _globalToRawCanvasOffset(details.globalPosition);
                                      setState(() {
                                        _selectionStart = canvasOffset;
                                        _selectionCurrent = canvasOffset;
                                        logic.selectedConnectionIndex = null;
                                        logic.clearConnectionDraft();
                                      });
                                    },
                                    onPanUpdate: (DragUpdateDetails details) {
                                      final Offset canvasOffset =
                                          _globalToRawCanvasOffset(details.globalPosition);
                                      setState(() {
                                        _selectionCurrent = canvasOffset;
                                      });
                                    },
                                    onPanEnd: (DragEndDetails details) {
                                      final Offset? start = _selectionStart;
                                      final Offset? current = _selectionCurrent;
                                      setState(() {
                                        _selectionStart = null;
                                        _selectionCurrent = null;
                                        if (start != null && current != null) {
                                          logic.selectNodesInRect(
                                            Rect.fromPoints(start, current)
                                                .inflate(2),
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
                                    onSecondaryTapDown: (TapDownDetails details) {
                                      setState(() {
                                        if (!logic.deleteConnectionAt(
                                          _globalToRawCanvasOffset(details.globalPosition),
                                        )) {
                                          logic.selectedConnectionIndex = null;
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
                                          ValueListenableBuilder<
                                              Map<String, NodeProcessIndicator>>(
                                            valueListenable:
                                                logic.nodeProcessIndicators,
                                            builder: (
                                              BuildContext context,
                                              Map<String, NodeProcessIndicator>
                                                  indicators,
                                              Widget? child,
                                            ) {
                                              return Stack(
                                                children: logic.nodeWidgets(
                                                  context: context,
                                                  update: () => setState(() {}),
                                                  translateDropOffset:
                                                      _globalToCanvasOffset,
                                                  openVisualizationWindow:
                                                      _openVisualizationWindow,
                                                ),
                                              );
                                            },
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
                                                    color: const Color(0xFF6DD3FF)
                                                        .withValues(alpha: 0.10),
                                                    border: Border.all(
                                                      color: const Color(0xFF6DD3FF)
                                                          .withValues(alpha: 0.88),
                                                      width: 1.5,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(4),
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
                            if (_quickVisualizerEnabled)
                              Expanded(
                                flex: 2,
                                child: VisualizationPanel(
                                  logic: logic,
                                  onChanged: () => setState(() {}),
                                  onOpenWindow: _openSelectedVisualizationWindow,
                                ),
                              ),
                            _ProjectActionsPanel(
                              saveLabel: logic.saveBrainStoryLabel,
                              onOpen: () async {
                                await logic.openBrainStory(context);
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                              onSave: () async {
                                await logic.saveBrainStory(context);
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                              onSaveAs: () async {
                                await logic.saveBrainStoryAs(context);
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                              onMemory: () async {
                                await _openMemoryManager();
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                              onPublish: () async {
                                await logic.showPublishDialog(context);
                              },
                              onClear: () {
                                setState(() => logic.clearAll());
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: ValueListenableBuilder<List<BrainStoryJob>>(
                    valueListenable: logic.jobs,
                    builder: (
                      BuildContext context,
                      List<BrainStoryJob> jobs,
                      Widget? child,
                    ) {
                      return _JobTray(
                        jobs: jobs,
                        onCancel: logic.cancelActiveRun,
                      );
                    },
                  ),
                ),
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

  Offset _globalToRawCanvasOffset(Offset globalOffset) {
    final RenderBox? renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return globalOffset;
    }
    return renderBox.globalToLocal(globalOffset);
  }

  KeyEventResult _handleKeyboardEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (_isEditingText()) {
      return KeyEventResult.ignored;
    }

    final LogicalKeyboardKey key = event.logicalKey;
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

  bool _isEditingText() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    return focusContext.widget is EditableText;
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
    final NodeModel current = logic.keyboardFocusedNode ??
        _nodeById(logic.selectedNodeId) ??
        logic.nodes.first;
    final NodeModel next = _nearestNodeInDirection(current, key) ??
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
    final NodeModel node = logic.keyboardFocusedNode ??
        _nodeById(logic.selectedNodeId) ??
        logic.nodes.first;
    final bool selectedSingleNode = logic.selectedNodeId == node.id &&
        logic.selectedNodeIds.length <= 1;
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
    final NodeModel node = logic.keyboardFocusedNode ??
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

  NodeModel? _nearestNodeInDirection(NodeModel current, LogicalKeyboardKey key) {
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
        return xCompare == 0 ? a.position.dy.compareTo(b.position.dy) : xCompare;
      });
    } else {
      ordered.sort((NodeModel a, NodeModel b) {
        final int yCompare = a.position.dy.compareTo(b.position.dy);
        return yCompare == 0 ? a.position.dx.compareTo(b.position.dx) : yCompare;
      });
    }
    final int currentIndex = ordered.indexWhere(
      (NodeModel node) => node.id == current.id,
    );
    if (currentIndex < 0) {
      return ordered.first;
    }
    final int offset = key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowUp
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
      final double viewport = _horizontalScrollController.position.viewportDimension;
      double target = current;
      if (node.position.dx < current + margin) {
        target = (node.position.dx - margin).clamp(
          0,
          _horizontalScrollController.position.maxScrollExtent,
        ).toDouble();
      } else if (node.position.dx + nodeWidth > current + viewport - margin) {
        target = (node.position.dx + nodeWidth + margin - viewport).clamp(
          0,
          _horizontalScrollController.position.maxScrollExtent,
        ).toDouble();
      }
      if (target != current) {
        _horizontalScrollController.jumpTo(target);
      }
    }
    if (_verticalScrollController.hasClients) {
      final double current = _verticalScrollController.offset;
      final double viewport = _verticalScrollController.position.viewportDimension;
      double target = current;
      if (node.position.dy < current + margin) {
        target = (node.position.dy - margin).clamp(
          0,
          _verticalScrollController.position.maxScrollExtent,
        ).toDouble();
      } else if (node.position.dy + nodeHeight > current + viewport - margin) {
        target = (node.position.dy + nodeHeight + margin - viewport).clamp(
          0,
          _verticalScrollController.position.maxScrollExtent,
        ).toDouble();
      }
      if (target != current) {
        _verticalScrollController.jumpTo(target);
      }
    }
  }

  void _openSelectedVisualizationWindow() {
    final NodeModel? selectedTarget = logic.selectedVisualizationTarget;
    if (selectedTarget == null || !logic.canVisualizeNode(selectedTarget)) {
      return;
    }
    _openVisualizationWindow(selectedTarget);
  }

  void _openVisualizationWindow(NodeModel node) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) => VisualizationFullscreenPage(
          logic: logic,
          nodeId: node.id,
        ),
      ),
    );
  }

  Future<void> _openMemoryManager() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _MemoryManagerDialog(logic: logic);
      },
    );
  }
}

class _MemoryManagerDialog extends StatefulWidget {
  const _MemoryManagerDialog({
    required this.logic,
  });

  final CanvasLogic logic;

  @override
  State<_MemoryManagerDialog> createState() => _MemoryManagerDialogState();
}

class _MemoryManagerDialogState extends State<_MemoryManagerDialog> {
  List<MemoryArtifactSummary> _rows = const <MemoryArtifactSummary>[];
  bool _loading = true;
  bool _runningAction = false;
  String _actionLabel = 'Working...';

  CanvasLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });
    final List<MemoryArtifactSummary> rows = await logic.memoryArtifactSummaries();
    if (!mounted) {
      return;
    }
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _runAction({
    required String label,
    required Future<String> Function(List<MemoryArtifactSummary> rows) action,
  }) async {
    if (_rows.isEmpty) {
      return;
    }
    setState(() {
      _runningAction = true;
      _actionLabel = label;
    });
    try {
      final String message = await action(_rows);
      if (!mounted) {
        return;
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int ramRows = _rows.where((MemoryArtifactSummary row) => row.inRam).length;
    final int diskRows = _rows.where((MemoryArtifactSummary row) => row.onDisk).length;
    final int ramBytes = _rows.fold<int>(
      0,
      (int total, MemoryArtifactSummary row) => total + row.approxRamBytes,
    );
    final int diskBytes = _rows.fold<int>(
      0,
      (int total, MemoryArtifactSummary row) => total + (row.approxDiskBytes ?? 0),
    );

    return AlertDialog(
      title: const Text('Memory Manager'),
      content: SizedBox(
        width: 1120,
        height: 640,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: <Widget>[
                      _MemoryStatChip(
                        label: 'Rows in RAM',
                        value: '$ramRows',
                      ),
                      _MemoryStatChip(
                        label: 'Rows on disk',
                        value: '$diskRows',
                      ),
                      _MemoryStatChip(
                        label: 'Approx RAM',
                        value: _formatBytes(ramBytes),
                      ),
                      _MemoryStatChip(
                        label: 'Approx disk',
                        value: _formatBytes(diskBytes),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Numeric artifacts are compacted to Float32 (4 bytes/value) when BrainStory stores them. This dialog shows what is currently cached in RAM, what is persisted to disk, and the precision regime for each row.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Spacer(),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _runningAction ? null : _refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 18,
                          columns: const <DataColumn>[
                            DataColumn(label: Text('Node')),
                            DataColumn(label: Text('Dataset')),
                            DataColumn(label: Text('Artifacts')),
                            DataColumn(label: Text('Processing')),
                            DataColumn(label: Text('RAM')),
                            DataColumn(label: Text('Disk')),
                            DataColumn(label: Text('Precision')),
                          ],
                          rows: _rows
                              .map(
                                (MemoryArtifactSummary row) => DataRow(
                                  cells: <DataCell>[
                                    DataCell(Text(row.nodeDescriptor)),
                                    DataCell(Text(row.datasetLabel)),
                                    DataCell(Text(row.artifactLabel)),
                                    DataCell(Text(row.processingState.name)),
                                    DataCell(
                                      Text(
                                        row.inRam
                                            ? 'Loaded (${_formatBytes(row.approxRamBytes)})'
                                            : 'Not loaded',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        row.onDisk
                                            ? 'Saved (${_formatBytes(row.approxDiskBytes ?? 0)})'
                                            : 'Not saved',
                                      ),
                                    ),
                                    DataCell(Text(row.precisionLabel)),
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonal(
                        onPressed: _runningAction
                            ? null
                            : () => _runAction(
                                  label: 'Loading into RAM...',
                                  action: logic.loadMemorySummariesToRam,
                                ),
                        child: const Text('Load from disk'),
                      ),
                      FilledButton.tonal(
                        onPressed: _runningAction
                            ? null
                            : () => _runAction(
                                  label: 'Saving to disk...',
                                  action: logic.saveMemorySummariesToDisk,
                                ),
                        child: const Text('Save to disk'),
                      ),
                      FilledButton.tonal(
                        onPressed: _runningAction
                            ? null
                            : () => _runAction(
                                  label: 'Purging RAM...',
                                  action: logic.purgeMemorySummariesFromRam,
                                ),
                        child: const Text('Purge RAM'),
                      ),
                      FilledButton.tonal(
                        onPressed: _runningAction
                            ? null
                            : () => _runAction(
                                  label: 'Purging disk cache...',
                                  action: logic.purgeMemorySummariesFromDisk,
                                ),
                        child: const Text('Purge disk'),
                      ),
                      if (_runningAction)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, top: 10),
                          child: Text(_actionLabel),
                        ),
                    ],
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _runningAction ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final int decimals = value >= 100 ? 0 : value >= 10 ? 1 : 2;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }
}

class _MemoryStatChip extends StatelessWidget {
  const _MemoryStatChip({
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
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectActionsPanel extends StatelessWidget {
  const _ProjectActionsPanel({
    required this.saveLabel,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onMemory,
    required this.onPublish,
    required this.onClear,
  });

  final String saveLabel;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onMemory;
  final VoidCallback onPublish;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: onOpen,
                  child: const Text('Open BrainStory'),
                ),
                FilledButton(
                  onPressed: onSave,
                  child: Text(saveLabel),
                ),
                FilledButton.tonal(
                  onPressed: onSaveAs,
                  child: const Text('Save As'),
                ),
                FilledButton.tonal(
                  onPressed: onMemory,
                  child: const Text('Memory'),
                ),
                FilledButton.tonal(
                  onPressed: onPublish,
                  child: const Text('Publish'),
                ),
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JobTray extends StatefulWidget {
  const _JobTray({
    required this.jobs,
    required this.onCancel,
  });

  final List<BrainStoryJob> jobs;
  final VoidCallback onCancel;

  @override
  State<_JobTray> createState() => _JobTrayState();
}

class _JobTrayState extends State<_JobTray> {
  Timer? _autoCollapseTimer;
  bool _collapsed = false;

  bool get _hasActiveJob =>
      widget.jobs.any((BrainStoryJob job) => job.isActive);

  @override
  void initState() {
    super.initState();
    _syncAutoCollapseTimer();
  }

  @override
  void didUpdateWidget(covariant _JobTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool hadActiveJob =
        oldWidget.jobs.any((BrainStoryJob job) => job.isActive);
    if (_hasActiveJob && !hadActiveJob && _collapsed) {
      _collapsed = false;
    }
    _syncAutoCollapseTimer();
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    super.dispose();
  }

  void _syncAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
    if (widget.jobs.isEmpty || _hasActiveJob || _collapsed) {
      return;
    }
    _autoCollapseTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || _hasActiveJob) {
        return;
      }
      setState(() {
        _collapsed = true;
      });
    });
  }

  void _collapse() {
    setState(() {
      _collapsed = true;
    });
    _syncAutoCollapseTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jobs.isEmpty) {
      return const SizedBox.shrink();
    }
    if (_collapsed) {
      return const SizedBox.shrink();
    }
    final List<BrainStoryJob> visibleJobs =
        widget.jobs.take(3).toList(growable: false);
    final bool hasActiveJob = _hasActiveJob;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.workspaces_outline,
                    size: 16,
                    color: hasActiveJob
                        ? Colors.cyanAccent
                        : Colors.white.withValues(alpha: 0.72),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasActiveJob ? 'Jobs running' : 'Recent jobs',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.jobs.length}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Hide recent jobs',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 26,
                      ),
                      onPressed: _collapse,
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final BrainStoryJob job in visibleJobs)
                _JobTrayRow(
                  job: job,
                  onCancel: widget.onCancel,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobTrayRow extends StatelessWidget {
  const _JobTrayRow({
    required this.job,
    required this.onCancel,
  });

  final BrainStoryJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _jobStatusColor(job.status);
    final bool showProgress =
        job.status == BrainStoryJobStatus.running && job.progress != null;
    final String detailText = job.error?.isNotEmpty == true
        ? job.error!
        : job.detail;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  job.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _jobStatusLabel(job.status),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (job.isActive && job.cancellable) ...<Widget>[
                const SizedBox(width: 6),
                SizedBox(
                  height: 24,
                  child: TextButton(
                    onPressed: job.cancelRequested ? null : onCancel,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      job.cancelRequested ? 'Canceling' : 'Cancel',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (detailText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              detailText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.66),
                fontSize: 11,
              ),
            ),
          ],
          if (showProgress) ...<Widget>[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: job.progress,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _jobStatusColor(BrainStoryJobStatus status) {
  switch (status) {
    case BrainStoryJobStatus.queued:
      return Colors.blueGrey.shade200;
    case BrainStoryJobStatus.running:
      return Colors.cyanAccent;
    case BrainStoryJobStatus.completed:
      return Colors.lightGreenAccent;
    case BrainStoryJobStatus.failed:
      return Colors.redAccent;
    case BrainStoryJobStatus.canceled:
      return Colors.orangeAccent;
  }
}

String _jobStatusLabel(BrainStoryJobStatus status) {
  switch (status) {
    case BrainStoryJobStatus.queued:
      return 'Queued';
    case BrainStoryJobStatus.running:
      return 'Running';
    case BrainStoryJobStatus.completed:
      return 'Done';
    case BrainStoryJobStatus.failed:
      return 'Failed';
    case BrainStoryJobStatus.canceled:
      return 'Canceled';
  }
}
