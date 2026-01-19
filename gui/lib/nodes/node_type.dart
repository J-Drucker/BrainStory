// lib/nodes/node_type.dart
import 'package:flutter/material.dart';

abstract class NodeType {
  String get title;
  Map<String, dynamic> get defaultParams;
  Widget buildConfigWidget(Map<String, dynamic> params, void Function(Map<String, dynamic>) onSave);
}
