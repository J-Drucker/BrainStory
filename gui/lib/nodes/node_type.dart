import 'dart:async';

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';

part 'node_type_dialog.dart';

const String combinedExecutionStagesKey = 'combinedExecutionStages';

List<Map<String, dynamic>>? combinedExecutionStages(
  Map<String, dynamic> params,
) {
  final List<dynamic>? rawStages =
      params[combinedExecutionStagesKey] as List<dynamic>?;
  if (rawStages == null || rawStages.isEmpty) return null;
  return rawStages
      .whereType<Map>()
      .map((Map<dynamic, dynamic> stage) => Map<String, dynamic>.from(stage))
      .toList(growable: false);
}

enum PortType { signal, metadata, markers, matrixTransformation }

enum NodeCategory {
  import,
  transform,
  multimodal,
  machineLearning,
  markerFunctions,
  endpoints,
  other,
}

enum NodeStoragePolicy {
  automatic,
  preferRam,
  preferDisk,
  ramAndDisk,
  onDemand,
}

enum NodeParameterChangeImpact { none, metadataOnly, computation }

extension NodeCategoryPresentation on NodeCategory {
  String get label {
    switch (this) {
      case NodeCategory.import:
        return 'Data Wrangling';
      case NodeCategory.transform:
        return 'Signal Processing';
      case NodeCategory.multimodal:
        return 'Multimodal';
      case NodeCategory.machineLearning:
        return 'Machine Learning';
      case NodeCategory.markerFunctions:
        return 'Markers and Metadata';
      case NodeCategory.endpoints:
        return 'Endpoints';
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
      case NodeCategory.multimodal:
        return Colors.blueGrey;
      case NodeCategory.machineLearning:
        return Colors.redAccent;
      case NodeCategory.markerFunctions:
        return Colors.yellow.shade700;
      case NodeCategory.endpoints:
        return Colors.teal;
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

  const PortSpec({required this.name, required this.type});
}

class NodePlacement {
  const NodePlacement({required this.category, required this.subcategory});

  final NodeCategory category;
  final String subcategory;
}

class NodeDropdownOption<T> {
  const NodeDropdownOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
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

class NodePortStatusSummary {
  const NodePortStatusSummary({required this.inputs, required this.outputs});

  final List<NodePortDatasetSummary> inputs;
  final List<NodePortDatasetSummary> outputs;
}

class NodePortDatasetSummary {
  const NodePortDatasetSummary({
    required this.label,
    required this.type,
    required this.readyCount,
    required this.totalCount,
  });

  final String label;
  final PortType type;
  final int readyCount;
  final int totalCount;
}

class NodeDatasetActions {
  const NodeDatasetActions({
    required this.supportsDisk,
    required this.refresh,
    required this.hasLoadableDiskCache,
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
  final Future<bool> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  hasLoadableDiskCache;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  runAllPrevious;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  runThisNode;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  clearResults;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  loadFromDisk;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  purgeActiveMemory;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  saveToDisk;
  final Future<String> Function(
    Map<String, dynamic> params,
    Set<String> datasetIds,
  )
  purgeFromDisk;
}

class NodeExecutionContext {
  const NodeExecutionContext({
    required this.setProgress,
    required this.yieldIfNeeded,
  });

  final Future<void> Function(String detail) setProgress;
  final Future<void> Function() yieldIfNeeded;
}

abstract class NodeType {
  String get title;
  String? get helpText => null;
  NodeCategory get category => NodeCategory.other;
  String get subcategory => 'Subcategory 1';
  List<NodePlacement> get additionalPlacements => const <NodePlacement>[];
  Map<String, dynamic> get defaultParams;

  NodePlacement get primaryPlacement =>
      NodePlacement(category: category, subcategory: subcategory);

  List<NodePlacement> get allPlacements {
    final List<NodePlacement> placements = <NodePlacement>[primaryPlacement];
    for (final NodePlacement placement in additionalPlacements) {
      final bool alreadyPresent = placements.any(
        (NodePlacement existing) =>
            existing.category == placement.category &&
            existing.subcategory == placement.subcategory,
      );
      if (!alreadyPresent) {
        placements.add(placement);
      }
    }
    return placements;
  }

  NodeStoragePolicy get defaultStoragePolicy {
    switch (category) {
      case NodeCategory.import:
      case NodeCategory.endpoints:
        return NodeStoragePolicy.preferRam;
      case NodeCategory.transform:
      case NodeCategory.multimodal:
      case NodeCategory.machineLearning:
      case NodeCategory.markerFunctions:
        return NodeStoragePolicy.automatic;
      case NodeCategory.other:
        return NodeStoragePolicy.automatic;
    }
  }

  List<PortSpec> get inputs;
  List<PortSpec> get outputs;

  NodeParameterChangeImpact parameterChangeImpact(
    Map<String, dynamic> previousParams,
    Map<String, dynamic> nextParams,
    Dataset dataset,
  ) {
    final Map<String, dynamic> previous = _executionParams(previousParams);
    final Map<String, dynamic> next = _executionParams(nextParams);
    return _nodeParamValuesEqual(previous, next)
        ? NodeParameterChangeImpact.none
        : NodeParameterChangeImpact.computation;
  }

  void applyMetadataOnlyParams(
    Map<String, dynamic> previousParams,
    Map<String, dynamic> nextParams,
    Dataset dataset,
  ) {}

  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  });

  String get executionChunkingStrategy => 'monolithic';

  Widget buildConfigWidget(
    Map<String, dynamic> params,
    void Function(Map<String, dynamic>) onSave, {
    FutureOr<void> Function(Map<String, dynamic>)? onSaveAndRun,
    NodeDatasetActions? datasetActions,
    required Map<String, Dataset> datasets,
    required Set<String> availableDatasetIds,
    required Map<String, List<String>> datasetSourceLabels,
    required Map<String, DatasetState> processedDatasetStates,
    required NodePortStatusSummary portStatusSummary,
    required List<String> processingSteps,
  }) {
    return _NodeConfigDialog(
      title: title,
      helpText: helpText,
      params: params,
      datasets: datasets,
      availableDatasetIds: availableDatasetIds,
      datasetSourceLabels: datasetSourceLabels,
      processedDatasetStates: processedDatasetStates,
      portStatusSummary: portStatusSummary,
      processingSteps: processingSteps,
      buildBody: buildBody,
      onSave: onSave,
      onSaveAndRun: onSaveAndRun,
      datasetActions: datasetActions,
      defaultStoragePolicy: defaultStoragePolicy,
      showSourceFiles: title == 'Import',
    );
  }

  Future<void> run(Dataset dataset, Map<String, dynamic> params);

  Future<void> runChunked(
    Dataset dataset,
    Map<String, dynamic> params,
    NodeExecutionContext context,
  ) {
    return run(dataset, params);
  }
}

Map<String, dynamic> _executionParams(Map<String, dynamic> params) {
  return <String, dynamic>{
    for (final MapEntry<String, dynamic> entry in params.entries)
      if (!entry.key.startsWith('_') &&
          entry.key != 'selectedDatasetIds' &&
          entry.key != 'storagePolicy')
        entry.key: entry.value,
  };
}

bool _nodeParamValuesEqual(dynamic left, dynamic right) {
  if (identical(left, right) || left == right) {
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final dynamic key in left.keys) {
      if (!right.containsKey(key) ||
          !_nodeParamValuesEqual(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index++) {
      if (!_nodeParamValuesEqual(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

class NodeParamTextField extends StatefulWidget {
  const NodeParamTextField({
    super.key,
    required this.params,
    required this.paramKey,
    required this.labelText,
    this.helperText,
    this.keyboardType,
    this.parser,
    this.valueFormatter,
    this.decoration,
  });

  final Map<String, dynamic> params;
  final String paramKey;
  final String labelText;
  final String? helperText;
  final TextInputType? keyboardType;
  final dynamic Function(String text, dynamic previousValue)? parser;
  final String Function(dynamic value)? valueFormatter;
  final InputDecoration? decoration;

  @override
  State<NodeParamTextField> createState() => _NodeParamTextFieldState();
}

class _NodeParamTextFieldState extends State<NodeParamTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _currentText);
  }

  String get _currentText {
    final dynamic value = widget.params[widget.paramKey];
    return widget.valueFormatter?.call(value) ?? value?.toString() ?? '';
  }

  @override
  void didUpdateWidget(covariant NodeParamTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String nextText = _currentText;
    if (_controller.text != nextText) {
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration decoration =
        widget.decoration ??
        InputDecoration(
          labelText: widget.labelText,
          helperText: widget.helperText,
        );
    return TextField(
      controller: _controller,
      keyboardType: widget.keyboardType,
      decoration: decoration,
      onChanged: (String text) {
        final dynamic previousValue = widget.params[widget.paramKey];
        final dynamic nextValue =
            widget.parser?.call(text, previousValue) ?? text;
        widget.params[widget.paramKey] = nextValue;
      },
    );
  }
}

class NodeParamDropdownField<T> extends StatefulWidget {
  const NodeParamDropdownField({
    super.key,
    required this.params,
    required this.paramKey,
    required this.labelText,
    required this.options,
    this.helperText,
    this.onChanged,
  });

  final Map<String, dynamic> params;
  final String paramKey;
  final String labelText;
  final String? helperText;
  final List<NodeDropdownOption<T>> options;
  final ValueChanged<T>? onChanged;

  @override
  State<NodeParamDropdownField<T>> createState() =>
      _NodeParamDropdownFieldState<T>();
}

class _NodeParamDropdownFieldState<T> extends State<NodeParamDropdownField<T>> {
  T? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = _resolveSelection();
  }

  @override
  void didUpdateWidget(covariant NodeParamDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedValue = _resolveSelection();
  }

  T? _resolveSelection() {
    final dynamic rawValue = widget.params[widget.paramKey];
    for (final NodeDropdownOption<T> option in widget.options) {
      if (option.value == rawValue) {
        return option.value;
      }
    }
    return widget.options.isEmpty ? null : widget.options.first.value;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: _selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
      ),
      items: widget.options
          .map((NodeDropdownOption<T> option) {
            return DropdownMenuItem<T>(
              value: option.value,
              enabled: option.enabled,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            );
          })
          .toList(growable: false),
      onChanged: (T? value) {
        if (value == null) {
          return;
        }
        setState(() {
          _selectedValue = value;
        });
        widget.params[widget.paramKey] = value;
        widget.onChanged?.call(value);
      },
    );
  }
}
