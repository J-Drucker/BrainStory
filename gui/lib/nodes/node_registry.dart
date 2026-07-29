import 'node_type.dart';

import 'import_node.dart';
import 'bridge_detector_node.dart';
import 'edit_channels_node.dart';
import 'edit_channels_and_markers_node.dart';
import 'bandpass_node.dart';
import 'fooof_node.dart';
import 'impedances_node.dart';
import 'machine_learning_nodes.dart';
import 'multimodal_nodes.dart';
import 'psd_node.dart';
import 'publish_node.dart';
import 'recode_markers_node.dart';
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
import 'visualization_node.dart';

enum NodeGroup {
  import,
  transform,
  multimodal,
  machineLearning,
  markerFunctions,
  endpoints,
}

extension NodeGroupLabel on NodeGroup {
  String get label {
    switch (this) {
      case NodeGroup.import:
        return 'Data Wrangling';
      case NodeGroup.transform:
        return 'Signal Processing';
      case NodeGroup.multimodal:
        return 'Multimodal';
      case NodeGroup.machineLearning:
        return 'Machine Learning';
      case NodeGroup.markerFunctions:
        return 'Markers and Metadata';
      case NodeGroup.endpoints:
        return 'Endpoints';
    }
  }
}

class NodeRegistryEntry {
  final NodeGroup group;
  final NodeType Function() create;
  final bool visible;

  NodeRegistryEntry({
    required this.group,
    required this.create,
    this.visible = true,
  });
}

/// Central 3-level hierarchy:
/// Node (overall) -> Group (Input/Output/...) -> Type (Import/PSD/etc)
class NodeRegistry {
  static final List<NodeGroup> groupOrder = [
    NodeGroup.import,
    NodeGroup.transform,
    NodeGroup.multimodal,
    NodeGroup.machineLearning,
    NodeGroup.markerFunctions,
    NodeGroup.endpoints,
  ];

  static final List<NodeRegistryEntry> entries = [
    // Input
    NodeRegistryEntry(group: NodeGroup.import, create: () => ImportNodeType()),
    NodeRegistryEntry(
      group: NodeGroup.import,
      create: () => EditChannelsNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.import,
      create: () => BridgeDetectorNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.import,
      create: () => ResampleNodeType(),
    ),

    // Signal processing
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => BandpassNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => AmplitudeFeaturesNodeType(),
    ),
    NodeRegistryEntry(group: NodeGroup.transform, create: () => PSDNodeType()),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => FooofNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => SpectralFeaturesNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => MicrostatesNodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => PCANodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => ICANodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => EigenvalueDecompositionNodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.transform,
      create: () => SourceReconstructionNodeType(),
      visible: false,
    ),

    // Multimodal
    NodeRegistryEntry(
      group: NodeGroup.multimodal,
      create: () => DetectPeaksNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.multimodal,
      create: () => InterbeatIntervalNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.multimodal,
      create: () => HeartRateVariabilityNodeType(),
    ),

    // Machine learning
    NodeRegistryEntry(
      group: NodeGroup.machineLearning,
      create: () => KMeansNodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.machineLearning,
      create: () => CNNNodeType(),
      visible: false,
    ),

    // Markers and metadata
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => AddRemoveMarkersNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => EditChannelsAndMarkersNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.markerFunctions,
      create: () => RecodeMarkersNodeType(),
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

    // Endpoints
    NodeRegistryEntry(
      group: NodeGroup.endpoints,
      create: () => ImpedancesNodeType(),
    ),
    NodeRegistryEntry(
      group: NodeGroup.endpoints,
      create: () => VisualizationNodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.endpoints,
      create: () => DebugOutputNodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.endpoints,
      create: () => ExportNodeType(),
      visible: false,
    ),
    NodeRegistryEntry(
      group: NodeGroup.endpoints,
      create: () => PublishNodeType(),
      visible: false,
    ),
  ];
}
