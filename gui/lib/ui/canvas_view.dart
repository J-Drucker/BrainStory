import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final GlobalKey _canvasKey = GlobalKey();

  CanvasLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compactRail = constraints.maxWidth < 1200;
        final double sideRailWidth = compactRail ? 300 : 360;

        return KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (KeyEvent event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.delete) {
              setState(() => logic.deleteSelected());
            }
          },
          child: Row(
            children: <Widget>[
              logic.sidebar(
                export: () => logic.export(context),
                clear: () => setState(() => logic.clearAll()),
                update: () => setState(() {}),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => logic.clearConnectionDraft()),
                  child: Container(
                    key: _canvasKey,
                    color: Colors.transparent,
                    child: Stack(
                      children: <Widget>[
                        ...logic.connectionWidgets(),
                        ...logic.nodeWidgets(
                          context: context,
                          update: () => setState(() {}),
                          translateDropOffset: _globalToCanvasOffset,
                        ),
                      ],
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
    return renderBox.globalToLocal(globalOffset);
  }
}
