import 'node_type.dart';

import 'import_node.dart';
import 'bandpass_node.dart';
import 'psd_node.dart';
import 'debug_output_node.dart';

enum NodeGroup {
  input,
  output,
  signalProcessing,
  metadataEdit,
  markerEdit,
  view,
  export,
  ml,
}

extension NodeGroupLabel on NodeGroup {
  String get label {
    switch (this) {
      case NodeGroup.input:
        return 'Input';
      case NodeGroup.output:
        return 'Output';
      case NodeGroup.signalProcessing:
        return 'Signal Processing';
      case NodeGroup.metadataEdit:
        return 'Metadata Edit';
      case NodeGroup.markerEdit:
        return 'Marker Edit';
      case NodeGroup.view:
        return 'View';
      case NodeGroup.export:
        return 'Export';
      case NodeGroup.ml:
        return 'ML';
    }
  }
}

class NodeRegistryEntry {
  final NodeGroup group;
  final NodeType Function() create;

  NodeRegistryEntry({
    required this.group,
    required this.create,
  });
}

/// Central 3-level hierarchy:
/// Node (overall) -> Group (Input/Output/...) -> Type (Import/PSD/etc)
class NodeRegistry {
  static final List<NodeGroup> groupOrder = [
    NodeGroup.input,
    NodeGroup.output,
    NodeGroup.signalProcessing,
    NodeGroup.metadataEdit,
    NodeGroup.markerEdit,
    NodeGroup.view,
    NodeGroup.export,
    NodeGroup.ml,
  ];

  static final List<NodeRegistryEntry> entries = [
    // Input
    NodeRegistryEntry(group: NodeGroup.input, create: () => ImportNodeType()),

    // Signal Processing
    NodeRegistryEntry(group: NodeGroup.signalProcessing, create: () => BandpassNodeType()),
    NodeRegistryEntry(group: NodeGroup.signalProcessing, create: () => PSDNodeType()),

    // Output
    NodeRegistryEntry(group: NodeGroup.output, create: () => DebugOutputNodeType()),
  ];
}