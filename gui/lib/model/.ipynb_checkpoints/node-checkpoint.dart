import 'package:flutter/material.dart';
import '../nodes/node_type.dart';

class NodeModel {
  final String id;
  final NodeType type;
  Offset position;
  Map<String, dynamic> params;

  String get title => type.title;

  NodeModel({
    required this.id,
    required this.type,
    required this.position,
    required this.params,
  });
}
