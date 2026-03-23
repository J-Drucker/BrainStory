import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/node.dart';
import 'canvas_logic.dart';
import 'dataset_panel.dart';
import 'visualization_panel.dart';

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
  bool _altSnapOverride = false;

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
                KeyboardListener(
                  focusNode: _keyboardFocusNode,
                  autofocus: true,
                  onKeyEvent: (KeyEvent event) {
                    final bool isAltKey =
                        event.logicalKey == LogicalKeyboardKey.altLeft ||
                        event.logicalKey == LogicalKeyboardKey.altRight;
                    if (isAltKey) {
                      final bool nextValue = event is KeyDownEvent || event is KeyRepeatEvent;
                      if (_altSnapOverride != nextValue) {
                        setState(() {
                          _altSnapOverride = nextValue;
                        });
                      }
                    }
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.delete) {
                      setState(() {
                        if (logic.selectedConnectionIndex != null) {
                          logic.deleteSelectedConnection();
                        } else {
                          logic.deleteSelected();
                        }
                      });
                    }
                  },
                  child: Row(
                    children: <Widget>[
                      logic.sidebar(
                        width: leftRailWidth,
                        export: () => logic.export(context),
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
                                      setState(() {
                                        if (!logic.selectConnectionAt(
                                          _globalToRawCanvasOffset(details.globalPosition),
                                        )) {
                                          logic.selectedConnectionIndex = null;
                                          logic.clearConnectionDraft();
                                        }
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
    if (_altSnapOverride) {
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
