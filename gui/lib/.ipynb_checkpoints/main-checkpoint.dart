import 'package:flutter/material.dart';
import 'ui/canvas.dart';

void main() {
  runApp(const BrainStoryApp());
}

class BrainStoryApp extends StatelessWidget {
  const BrainStoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrainStory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const Scaffold(
        body: BrainStoryCanvas(),
      ),
    );
  }
} 
