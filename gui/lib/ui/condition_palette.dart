import 'package:flutter/material.dart';

const List<Color> conditionPalette = <Color>[
  Color(0xFFFFD23F),
  Color(0xFF2F80ED),
  Color(0xFF34D399),
  Color(0xFFFF5C8A),
  Color(0xFFFF8A3D),
  Color(0xFF8B5CF6),
  Color(0xFF00C2A8),
  Color(0xFFE84855),
  Color(0xFF7DD3FC),
  Color(0xFFA3E635),
];

Color conditionColor(String label, Iterable<String> availableLabels) {
  final List<String> labels = availableLabels.toSet().toList(growable: false)
    ..sort((String a, String b) => a.compareTo(b));
  final int index = labels.indexOf(label);
  return conditionPalette[(index < 0 ? 0 : index) % conditionPalette.length];
}
