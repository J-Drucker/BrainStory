import 'package:flutter/material.dart';

class NodeModel {
  final String id;
  final String title;
  Offset position;
  Map<String, dynamic> params;

  NodeModel({
    required this.id,
    required this.title,
    required this.position,
    this.params = const {},
  });
}
