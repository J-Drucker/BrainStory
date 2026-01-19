// canvas.dart (now minimal entry point)
import 'package:flutter/material.dart';
import 'canvas_view.dart';

class BrainStoryCanvas extends StatefulWidget {
  const BrainStoryCanvas({super.key});

  @override
  State<BrainStoryCanvas> createState() => _BrainStoryCanvasState();
}

class _BrainStoryCanvasState extends State<BrainStoryCanvas> {
  @override
  Widget build(BuildContext context) {
    return const CanvasView();
  }
}
