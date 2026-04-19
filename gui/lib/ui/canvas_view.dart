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
                        publish: () async {
                          await logic.showPublishDialog(context);
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
                                          ...logic.nodeWidgets(
                                            context: context,
                                            update: () => setState(() {}),
                                            translateDropOffset: _globalToCanvasOffset,
                                            openVisualizationWindow: _openVisualizationWindow,
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
                            Expanded(
                              flex: 2,
                              child: VisualizationPanel(
                                logic: logic,
                                onChanged: () => setState(() {}),
                                onOpenWindow: _openSelectedVisualizationWindow,
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
                if (runActivity != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.14),
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 20),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Card(
                            elevation: 10,
                            color: Colors.grey.shade900,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    runActivity.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (runActivity.detail.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 8),
                                    Text(
                                      runActivity.detail,
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  const LinearProgressIndicator(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
}
