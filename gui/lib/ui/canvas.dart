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
  late final CanvasLogic logic = CanvasLogic();

  @override
  void initState() {
    super.initState();
    _restoreLastBrainStory();
  }

  Future<void> _restoreLastBrainStory() async {
    final bool restored = await logic.restoreLastBrainStory();
    if (restored && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return CanvasView(logic: logic);
  }
}
