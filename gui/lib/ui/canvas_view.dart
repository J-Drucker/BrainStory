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

        return KeyboardListener(
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
    final selectedNode = logic.selectedVisualizationNode;
    if (selectedNode == null) {
      return;
    }
    _openVisualizationWindow(selectedNode);
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
