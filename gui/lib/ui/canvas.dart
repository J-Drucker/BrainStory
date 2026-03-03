// canvas.dart
import 'package:flutter/material.dart';
import 'canvas_view.dart';
import 'canvas_logic.dart';

class BrainStoryCanvas extends StatefulWidget {
  const BrainStoryCanvas({super.key});

  @override
  State<BrainStoryCanvas> createState() => _BrainStoryCanvasState();
}

class _BrainStoryCanvasState extends State<BrainStoryCanvas> {
  late final CanvasLogic logic;

  @override
  void initState() {
    super.initState();
    logic = CanvasLogic(onUpdate: _handleUpdate);
  }

  void _handleUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CanvasView(logic: logic);
  }
}
