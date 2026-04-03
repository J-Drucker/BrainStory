import 'node_type.dart';

import 'import_node.dart';
import 'bridge_detector_node.dart';
import 'channel_exclusion_node.dart';
import 'bandpass_node.dart';
import 'fooof_node.dart';
import 'machine_learning_nodes.dart';
import 'psd_node.dart';
import 'realign_node.dart';
import 'resample_node.dart';
import 'matrix_transform_nodes.dart';
import 'add_remove_markers_node.dart';
import 'amplitude_features_node.dart';
import 'segmentation_node.dart';
import 'sleep_staging_node.dart';
import 'spectral_features_node.dart';
import 'debug_output_node.dart';
import 'eye_blinks_node.dart';
import 'export_edf_node.dart';

enum NodeGroup {
  import,
  transform,
  machineLearning,
  markerFunctions,
  visualize,
  export,
}

extension NodeGroupLabel on NodeGroup {
  String get label {
    switch (this) {
      case NodeGroup.import:
        return 'Data Wrangling';
      case NodeGroup.transform:
        return 'Signal Processing';
      case NodeGroup.machineLearning:
        return 'Machine Learning';
      case NodeGroup.markerFunctions:
        return 'Markers and Metadata';
      case NodeGroup.visualize:
        return 'Visualize';
      case NodeGroup.export:
        return 'Export';
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
    NodeGroup.import,
    NodeGroup.transform,
    NodeGroup.machineLearning,
    NodeGroup.markerFunctions,
    NodeGroup.visualize,
    NodeGroup.export,
  ];

  static final List<NodeRegistryEntry> entries = [
    // Input
    NodeRegistryEntry(group: NodeGroup.import, create: () => ImportNodeType()),
    NodeRegistryEntry(group: NodeGroup.import, create: () => ChannelExclusionNodeType()),
    NodeRegistryEntry(group: NodeGroup.import, create: () => BridgeDetectorNodeType()),
    NodeRegistryEntry(group: NodeGroup.import, create: () => ResampleNodeType()),

    // Signal processing
    NodeRegistryEntry(group: NodeGroup.transform, create: () => BandpassNodeType()),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => AmplitudeFeaturesNodeType()),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => PSDNodeType()),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => FooofNodeType()),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => SpectralFeaturesNodeType()),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => MicrostatesNodeType()),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => PCANodeType()),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => ICANodeType()),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => EigenvalueDecompositionNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => SourceReconstructionNodeType(),
    ),

    // Machine learning
    NodeRegistryEntry(
      group: NodeGroup.machineLearning,
      create: () => KMeansNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.machineLearning,
      create: () => CNNNodeType(),
    ),

    // Markers and metadata
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => AddRemoveMarkersNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => SegmentationNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => EyeBlinksNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => SleepStagingNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => RealignNodeType(),
    ),

    // Visualize
    NodeRegistryEntry(group: NodeGroup.visualize, create: () => DebugOutputNodeType()),

    // Export
    NodeRegistryEntry(group: NodeGroup.export, create: () => ExportNodeType()),
  ];
}
