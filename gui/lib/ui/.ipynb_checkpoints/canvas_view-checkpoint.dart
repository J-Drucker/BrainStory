// canvas_view.dart
import 'package:flutter/material.dart';
import '../model/node.dart';
import 'node_card.dart';
import 'connection_painter.dart';
import 'node_config.dart';
import 'canvas_logic.dart';

class CanvasView extends StatefulWidget {
  const CanvasView({super.key});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  final logic = CanvasLogic();

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (event) {
        if (event.logicalKey.keyLabel == 'Delete') {
          setState(() => logic.deleteSelected());
        }
      },
      child: Row(
        children: [
          logic.sidebar(
              export: () => logic.export(context),
              clear: () => setState(() => logic.clearAll()),
              update: () => setState(() {}),
            ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => logic.clearConnection()),
              child: Stack(
                children: [
                  ...logic.connectionWidgets(),
                  ...logic.nodeWidgets(
                    context: context,
                    update: () => setState(() {}),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
