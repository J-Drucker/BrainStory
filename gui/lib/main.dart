import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'ui/canvas.dart';

void main() {
  runApp(const BrainStoryApp());
}

class BrainStoryApp extends StatelessWidget {
  const BrainStoryApp({super.key});

  bool get _disableDesktopSemantics {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrainStory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: _disableDesktopSemantics
            ? const ExcludeSemantics(child: BrainStoryCanvas())
            : const BrainStoryCanvas(),
      ),
    );
  }
}
