import 'dart:async';

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';

part 'node_type_dialog.dart';

enum PortType { signal, metadata, markers, matrixTransformation }

enum NodeCategory { import, transform, markerFunctions, visualize, export, other }

enum NodeStoragePolicy { automatic, preferRam, preferDisk, ramAndDisk, onDemand }

extension NodeCategoryPresentation on NodeCategory {
  String get label {
    switch (this) {
      case NodeCategory.import:
        return 'Import';
      case NodeCategory.transform:
        return 'Transform';
      case NodeCategory.markerFunctions:
        return 'Markers and Metadata';
      case NodeCategory.visualize:
        return 'Visualize';
      case NodeCategory.export:
        return 'Export';
      case NodeCategory.other:
        return 'Other';
    }
  }

  Color get color {
    switch (this) {
      case NodeCategory.import:
        return Colors.green;
      case NodeCategory.transform:
        return Colors.indigo;
      case NodeCategory.markerFunctions:
        return Colors.yellow.shade700;
      case NodeCategory.visualize:
        return Colors.teal;
      case NodeCategory.export:
        return Colors.pinkAccent;
      case NodeCategory.other:
        return Colors.grey;
    }
  }
}

extension NodeStoragePolicyPresentation on NodeStoragePolicy {
  String get wireValue {
    switch (this) {
      case NodeStoragePolicy.automatic:
        return 'automatic';
      case NodeStoragePolicy.preferRam:
        return 'prefer_ram';
      case NodeStoragePolicy.preferDisk:
        return 'prefer_disk';
      case NodeStoragePolicy.ramAndDisk:
        return 'ram_and_disk';
      case NodeStoragePolicy.onDemand:
        return 'on_demand';
    }
  }

  String get label {
    switch (this) {
      case NodeStoragePolicy.automatic:
        return 'Automatic';
      case NodeStoragePolicy.preferRam:
        return 'Prefer RAM';
      case NodeStoragePolicy.preferDisk:
        return 'Prefer Disk';
      case NodeStoragePolicy.ramAndDisk:
        return 'RAM + Disk';
      case NodeStoragePolicy.onDemand:
        return 'On Demand';
    }
  }

  String get description {
    switch (this) {
      case NodeStoragePolicy.automatic:
        return 'Use BrainStory defaults for this node type.';
      case NodeStoragePolicy.preferRam:
        return 'Keep this node readily materialized in memory when possible.';
      case NodeStoragePolicy.preferDisk:
        return 'Persist this node to disk and release extra node cache from RAM when possible.';
      case NodeStoragePolicy.ramAndDisk:
        return 'Keep a hot in-memory copy and a disk cache for reloads.';
      case NodeStoragePolicy.onDemand:
        return 'Avoid keeping extra node cache unless explicitly loaded.';
    }
  }

  static NodeStoragePolicy fromWireValue(String? value) {
    for (final NodeStoragePolicy policy in NodeStoragePolicy.values) {
      if (policy.wireValue == value) {
        return policy;
      }
    }
    return NodeStoragePolicy.automatic;
  }
}

class PortSpec {
  final String name;
  final PortType type;

  const PortSpec({
    required this.name,
    required this.type,
  });
}

class NodeDatasetStatusSnapshot {
  const NodeDatasetStatusSnapshot({
    required this.availableDatasetIds,
    required this.processedDatasetStates,
    required this.ramLoadedDatasetIds,
    required this.diskSavedDatasetIds,
  });

  final Set<String> availableDatasetIds;
  final Map<String, DatasetState> processedDatasetStates;
  final Set<String> ramLoadedDatasetIds;
  final Set<String> diskSavedDatasetIds;
}

class NodeDatasetActions {
  const NodeDatasetActions({
    required this.supportsDisk,
    required this.refresh,
    required this.runAllPrevious,
    required this.runThisNode,
    required this.clearResults,
    required this.loadFromDisk,
    required this.purgeActiveMemory,
    required this.saveToDisk,
    required this.purgeFromDisk,
  });

  final bool supportsDisk;
  final Future<NodeDatasetStatusSnapshot> Function(Map<String, dynamic> params)
      refresh;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  ) runAllPrevious;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  ) runThisNode;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  ) clearResults;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  ) loadFromDisk;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  ) purgeActiveMemory;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  ) saveToDisk;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  ) purgeFromDisk;
}

abstract class NodeType {
  String get title;
  NodeCategory get category => NodeCategory.other;
  Map<String, dynamic> get defaultParams;

  NodeStoragePolicy get defaultStoragePolicy {
    switch (category) {
      case NodeCategory.import:
      case NodeCategory.visualize:
        return NodeStoragePolicy.preferRam;
      case NodeCategory.transform:
      case NodeCategory.markerFunctions:
        return NodeStoragePolicy.automatic;
      case NodeCategory.export:
        return NodeStoragePolicy.onDemand;
      case NodeCategory.other:
        return NodeStoragePolicy.automatic;
    }
  }

  List<PortSpec> get inputs;
  List<PortSpec> get outputs;

  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  });

  Widget buildConfigWidget(
    Map<String, dynamic> params,
    void Function(Map<String, dynamic>) onSave, {
    FutureOr<void> Function(Map<String, dynamic>)? onSaveAndRun,
    NodeDatasetActions? datasetActions,
    required Map<String, Dataset> datasets,
    required Set<String> availableDatasetIds,
    required Map<String, List<String>> datasetSourceLabels,
    required Map<String, DatasetState> processedDatasetStates,
    required List<String> processingSteps,
  }) {
    return _NodeConfigDialog(
      title: title,
      params: params,
      datasets: datasets,
      availableDatasetIds: availableDatasetIds,
      datasetSourceLabels: datasetSourceLabels,
      processedDatasetStates: processedDatasetStates,
      processingSteps: processingSteps,
      buildBody: buildBody,
      onSave: onSave,
      onSaveAndRun: onSaveAndRun,
      datasetActions: datasetActions,
      defaultStoragePolicy: defaultStoragePolicy,
    );
  }

  Future<void> run(Dataset dataset, Map<String, dynamic> params);
}
