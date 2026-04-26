import 'dart:isolate';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/dataset_artifact_snapshot.dart';
import '../nodes/amplitude_features_node.dart';
import '../nodes/average_node.dart';
import '../nodes/bandpass_node.dart';
import '../nodes/bridge_detector_node.dart';
import '../nodes/fooof_node.dart';
import '../nodes/node_type.dart';
import '../nodes/psd_node.dart';
import '../nodes/resample_node.dart';
import '../nodes/spectral_features_node.dart';

Future<Map<String, dynamic>> runNodeSnapshotInBackground({
  required String nodeTitle,
  required String datasetId,
  required String datasetLabel,
  required String datasetPath,
  required bool datasetLoaded,
  required Map<String, dynamic> params,
  required Map<String, dynamic> inputSnapshotJson,
}) {
  return Isolate.run(
    () => _runNodeSnapshotWorker(
      <String, dynamic>{
        'nodeTitle': nodeTitle,
        'datasetId': datasetId,
        'datasetLabel': datasetLabel,
        'datasetPath': datasetPath,
        'datasetLoaded': datasetLoaded,
        'params': params,
        'inputSnapshot': inputSnapshotJson,
      },
    ),
  );
}

Future<Map<String, dynamic>> _runNodeSnapshotWorker(
  Map<String, dynamic> payload,
) async {
  final NodeType nodeType = _workerNodeTypeForTitle(
    payload['nodeTitle']?.toString() ?? '',
  );
  final Dataset dataset = Dataset(
    payload['datasetId']?.toString() ?? '',
    label: payload['datasetLabel']?.toString() ?? '',
    path: payload['datasetPath']?.toString() ?? '',
  )..loaded = payload['datasetLoaded'] as bool? ?? false;

  final DatasetArtifactSnapshot inputSnapshot = DatasetArtifactSnapshot.fromJson(
    Map<String, dynamic>.from(
      payload['inputSnapshot'] as Map? ?? const <String, dynamic>{},
    ),
  );
  inputSnapshot.applyToDataset(dataset);

  final Map<String, dynamic> params = Map<String, dynamic>.from(
    payload['params'] as Map? ?? const <String, dynamic>{},
  );
  await nodeType.run(dataset, params);

  final DatasetArtifactSnapshot outputSnapshot =
      DatasetArtifactSnapshot.fromDataset(
    dataset,
    includedKinds: _artifactKindsForNodeOutputs(nodeType, dataset),
  );
  return outputSnapshot.toJson();
}

Set<BrainStoryArtifactKind> _artifactKindsForNodeOutputs(
  NodeType nodeType,
  Dataset dataset,
) {
  final Set<BrainStoryArtifactKind> kinds = <BrainStoryArtifactKind>{};
  for (final PortSpec output in nodeType.outputs) {
    final String outputName = output.name.toLowerCase();
    switch (output.type) {
      case PortType.signal:
        if ((outputName.contains('psd') || outputName.contains('spectrum')) &&
            dataset.spectrum != null) {
          kinds.add(BrainStoryArtifactKind.spectrum);
        } else if (dataset.timeSeries != null) {
          kinds.add(BrainStoryArtifactKind.timeSeries);
        }
        break;
      case PortType.markers:
        if (dataset.timeSeries != null) {
          kinds.add(BrainStoryArtifactKind.markers);
        }
        break;
      case PortType.metadata:
        if (outputName.contains('segment') &&
            dataset.segmentedTimeSeries != null) {
          kinds.add(BrainStoryArtifactKind.segmentedTimeSeries);
        } else if (dataset.fooofResult != null) {
          kinds.add(BrainStoryArtifactKind.fooofResult);
        } else if (dataset.featureTable != null) {
          kinds.add(BrainStoryArtifactKind.featureTable);
        } else if (dataset.bridgeDetection != null) {
          kinds.add(BrainStoryArtifactKind.bridgeDetection);
        } else if (dataset.timeFrequency != null) {
          kinds.add(BrainStoryArtifactKind.timeFrequency);
        }
        break;
      case PortType.matrixTransformation:
        if (dataset.matrixTransformation != null) {
          kinds.add(BrainStoryArtifactKind.matrixTransformation);
        }
        break;
    }
  }
  return kinds;
}

NodeType _workerNodeTypeForTitle(String title) {
  final List<NodeType> supportedNodes = <NodeType>[
    AmplitudeFeaturesNodeType(),
    AverageNodeType(),
    BandpassNodeType(),
    BridgeDetectorNodeType(),
    FooofNodeType(),
    PSDNodeType(),
    ResampleNodeType(),
    SpectralFeaturesNodeType(),
  ];
  for (final NodeType nodeType in supportedNodes) {
    if (nodeType.title == title) {
      return nodeType;
    }
  }
  throw UnsupportedError('Node "$title" is not background-runnable yet.');
}
