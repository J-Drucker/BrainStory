import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset_artifact_snapshot.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';
import '../model/node.dart';
import '../nodes/add_remove_markers_node.dart';
import '../nodes/bridge_detector_node.dart';
import '../nodes/channel_coordinates_node.dart';
import '../nodes/edit_channels_and_markers_node.dart';
import '../nodes/edit_channels_node.dart';
import '../nodes/import_node.dart';
import '../nodes/impedances_node.dart';
import '../nodes/interactive_artifact_detection_node.dart';
import '../nodes/node_registry.dart';
import '../nodes/node_type.dart';
import '../nodes/psd_average_node.dart';
import '../nodes/psd_node.dart';
import '../nodes/realign_node.dart';
import '../nodes/segmentation_node.dart';
import '../nodes/sleep_staging_node.dart';
import '../nodes/visualization_node.dart';
import '../platform/node_snapshot_store.dart';
import '../platform/project_file_save.dart';
import '../platform/recent_project_path.dart';
import 'connection_painter.dart';
import 'node_card.dart';

enum _OutputHandleKind {
  timeSeries,
  spectrum,
  timeFrequency,
  markers,
  segments,
  table,
  matrix,
  other,
}

enum RunActivityPhase { initializing, running, finalizing }

enum ProcessingResponsiveness { fast, balanced, responsive }

class CanvasNodeGroup {
  CanvasNodeGroup({
    required this.id,
    required this.label,
    required Set<String> nodeIds,
    this.automaticRootNodeId,
  }) : nodeIds = Set<String>.from(nodeIds);

  final String id;
  final String label;
  final Set<String> nodeIds;
  final String? automaticRootNodeId;

  CanvasNodeGroup copy() => CanvasNodeGroup(
    id: id,
    label: label,
    nodeIds: nodeIds,
    automaticRootNodeId: automaticRootNodeId,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'nodeIds': nodeIds.toList(growable: false),
    if (automaticRootNodeId != null) 'automaticRootNodeId': automaticRootNodeId,
  };

  static CanvasNodeGroup fromJson(Map<String, dynamic> json) {
    return CanvasNodeGroup(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Group',
      nodeIds: (json['nodeIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toSet(),
      automaticRootNodeId: json['automaticRootNodeId']?.toString(),
    );
  }
}

extension ProcessingResponsivenessPresentation on ProcessingResponsiveness {
  String get label {
    switch (this) {
      case ProcessingResponsiveness.fast:
        return 'Fast';
      case ProcessingResponsiveness.balanced:
        return 'Balanced';
      case ProcessingResponsiveness.responsive:
        return 'Responsive';
    }
  }

  String get description {
    switch (this) {
      case ProcessingResponsiveness.fast:
        return 'Prioritize throughput; chunk-aware nodes yield minimally.';
      case ProcessingResponsiveness.balanced:
        return 'Split time between processing and UI responsiveness.';
      case ProcessingResponsiveness.responsive:
        return 'Yield frequently so the interface stays easy to use.';
    }
  }

  Duration get workBudget {
    switch (this) {
      case ProcessingResponsiveness.fast:
        return const Duration(milliseconds: 250);
      case ProcessingResponsiveness.balanced:
        return const Duration(milliseconds: 50);
      case ProcessingResponsiveness.responsive:
        return const Duration(milliseconds: 25);
    }
  }

  Duration get yieldBudget {
    switch (this) {
      case ProcessingResponsiveness.fast:
        return Duration.zero;
      case ProcessingResponsiveness.balanced:
        return const Duration(milliseconds: 50);
      case ProcessingResponsiveness.responsive:
        return const Duration(milliseconds: 75);
    }
  }

  bool get chunkingEnabled => this != ProcessingResponsiveness.fast;
}

class RunActivity {
  const RunActivity({
    required this.label,
    this.detail = '',
    this.phase = RunActivityPhase.initializing,
  });

  final String label;
  final String detail;
  final RunActivityPhase phase;

  RunActivity copyWith({
    String? label,
    String? detail,
    RunActivityPhase? phase,
  }) {
    return RunActivity(
      label: label ?? this.label,
      detail: detail ?? this.detail,
      phase: phase ?? this.phase,
    );
  }
}

enum RunJobState { queued, running, done, failed }

class RunJobEntry {
  const RunJobEntry({
    required this.label,
    required this.detail,
    required this.state,
    this.finishedAt,
    this.elapsed = Duration.zero,
  });

  final String label;
  final String detail;
  final RunJobState state;
  final DateTime? finishedAt;
  final Duration elapsed;
}

class _QueuedRunTask {
  _QueuedRunTask({
    required this.id,
    required this.label,
    required this.lockedNodeIds,
    required this.action,
    required this.successDetail,
  });

  final int id;
  final String label;
  final Set<String> lockedNodeIds;
  final Future<void> Function() action;
  final String Function() successDetail;
  final Completer<String> completer = Completer<String>();
}

class VisualizationSourceRef {
  const VisualizationSourceRef({
    required this.key,
    required this.datasetId,
    required this.datasetLabel,
    required this.materializeFromNodeId,
    required this.sourceDescriptor,
  });

  final String key;
  final String datasetId;
  final String datasetLabel;
  final String materializeFromNodeId;
  final String sourceDescriptor;

  String get displayLabel => '$datasetLabel [$sourceDescriptor]';
}

class _MemoryRowSummary {
  const _MemoryRowSummary({
    required this.nodeId,
    required this.nodeDescriptor,
    required this.nodeTitle,
    required this.datasetId,
    required this.datasetLabel,
    required this.processingLabel,
    required this.inRam,
    required this.onDisk,
    required this.precisionLabel,
  });

  final String nodeId;
  final String nodeDescriptor;
  final String nodeTitle;
  final String datasetId;
  final String datasetLabel;
  final String processingLabel;
  final bool inRam;
  final bool onDisk;
  final String precisionLabel;
}

class _DatasetUndoSnapshot {
  const _DatasetUndoSnapshot({
    required this.mapKey,
    required this.id,
    required this.label,
    required this.path,
    required this.sourceBytes,
    required this.loaded,
    required this.sourceFilename,
    required this.artifactSnapshot,
  });

  final String mapKey;
  final String id;
  final String label;
  final String path;
  final Uint8List? sourceBytes;
  final bool loaded;
  final String? sourceFilename;
  final DatasetArtifactSnapshot? artifactSnapshot;

  factory _DatasetUndoSnapshot.capture(
    MapEntry<String, Dataset> entry, {
    required bool captureArtifacts,
  }) {
    final Dataset dataset = entry.value;
    final String? sourceFilename = dataset.ram['source.filename']?.toString();
    return _DatasetUndoSnapshot(
      mapKey: entry.key,
      id: dataset.id,
      label: dataset.label,
      path: dataset.path,
      sourceBytes: dataset.sourceBytes,
      loaded: dataset.loaded,
      sourceFilename: sourceFilename?.isEmpty == true ? null : sourceFilename,
      artifactSnapshot: captureArtifacts
          ? DatasetArtifactSnapshot.fromDataset(dataset)
          : null,
    );
  }

  Dataset restore(Map<String, Dataset> currentDatasetsById) {
    final Dataset dataset =
        currentDatasetsById[id] ??
        Dataset(id, label: label, path: path, sourceBytes: sourceBytes);
    dataset.label = label;
    dataset.path = path;
    dataset.sourceBytes = sourceBytes;
    dataset.loaded = loaded;
    if (sourceFilename == null) {
      dataset.ram.remove('source.filename');
    } else {
      dataset.ram['source.filename'] = sourceFilename;
    }
    artifactSnapshot?.applyToDataset(dataset);
    return dataset;
  }
}

class _NodeUndoSnapshot {
  const _NodeUndoSnapshot({
    required this.id,
    required this.type,
    required this.position,
    required this.params,
    required this.markerChange,
    required this.datasetStates,
  });

  final String id;
  final NodeType type;
  final Offset position;
  final Map<String, dynamic> params;
  final MarkerChange markerChange;
  final Map<dynamic, DatasetState> datasetStates;

  factory _NodeUndoSnapshot.capture(NodeModel node) {
    return _NodeUndoSnapshot(
      id: node.id,
      type: node.type,
      position: node.position,
      params: _deepCloneJsonMap(node.params),
      markerChange: MarkerChange.fromJson(node.markerChange.toJson()),
      datasetStates: Map<dynamic, DatasetState>.from(node.datasetStates),
    );
  }

  NodeModel restore() {
    final NodeModel node = NodeModel(
      id: id,
      type: type,
      position: position,
      params: _deepCloneJsonMap(params),
      markerChange: MarkerChange.fromJson(markerChange.toJson()),
    );
    node.datasetStates.addAll(datasetStates);
    return node;
  }
}

class _CanvasUndoSnapshot {
  const _CanvasUndoSnapshot({
    required this.label,
    required this.nodes,
    required this.datasets,
    required this.connections,
    required this.nodeGroups,
    required this.ungroupedAutomaticRootNodeIds,
    required this.nodeRamSnapshots,
    required this.nodeDiskSnapshotIds,
    required this.selectedNodeId,
    required this.selectedNodeIds,
    required this.selectedConnectionIndex,
    required this.pendingFromNodeId,
    required this.pendingFromPortIndex,
  });

  final String label;
  final List<_NodeUndoSnapshot> nodes;
  final List<_DatasetUndoSnapshot> datasets;
  final List<Map<String, dynamic>> connections;
  final List<CanvasNodeGroup> nodeGroups;
  final Set<String> ungroupedAutomaticRootNodeIds;
  final Map<String, Map<String, DatasetArtifactSnapshot>> nodeRamSnapshots;
  final Map<String, Set<String>> nodeDiskSnapshotIds;
  final String? selectedNodeId;
  final Set<String> selectedNodeIds;
  final int? selectedConnectionIndex;
  final String? pendingFromNodeId;
  final int? pendingFromPortIndex;

  factory _CanvasUndoSnapshot.capture(
    CanvasLogic logic,
    String label, {
    Set<String> datasetArtifactIds = const <String>{},
  }) {
    return _CanvasUndoSnapshot(
      label: label,
      nodes: logic.nodes.map(_NodeUndoSnapshot.capture).toList(growable: false),
      datasets: logic.datasets.entries
          .map(
            (MapEntry<String, Dataset> entry) => _DatasetUndoSnapshot.capture(
              entry,
              captureArtifacts: datasetArtifactIds.contains(entry.value.id),
            ),
          )
          .toList(growable: false),
      connections: logic.connections
          .map(
            (Map<String, dynamic> connection) => _deepCloneJsonMap(connection),
          )
          .toList(growable: false),
      nodeGroups: logic.nodeGroups
          .map((CanvasNodeGroup group) => group.copy())
          .toList(growable: false),
      ungroupedAutomaticRootNodeIds: Set<String>.from(
        logic._ungroupedAutomaticRootNodeIds,
      ),
      nodeRamSnapshots: <String, Map<String, DatasetArtifactSnapshot>>{
        for (final MapEntry<String, Map<String, DatasetArtifactSnapshot>> entry
            in logic._nodeRamSnapshots.entries)
          entry.key: Map<String, DatasetArtifactSnapshot>.from(entry.value),
      },
      nodeDiskSnapshotIds: <String, Set<String>>{
        for (final MapEntry<String, Set<String>> entry
            in logic._nodeDiskSnapshotIds.entries)
          entry.key: Set<String>.from(entry.value),
      },
      selectedNodeId: logic.selectedNodeId,
      selectedNodeIds: Set<String>.from(logic.selectedNodeIds),
      selectedConnectionIndex: logic.selectedConnectionIndex,
      pendingFromNodeId: logic._pendingFromNodeId,
      pendingFromPortIndex: logic._pendingFromPortIndex,
    );
  }

  void restore(CanvasLogic logic) {
    final Map<String, Dataset> currentDatasetsById = <String, Dataset>{
      for (final Dataset dataset in logic.datasets.values) dataset.id: dataset,
    };

    logic.nodes
      ..clear()
      ..addAll(nodes.map((_NodeUndoSnapshot node) => node.restore()));

    logic.datasets.clear();
    for (final _DatasetUndoSnapshot datasetSnapshot in datasets) {
      logic.datasets[datasetSnapshot.mapKey] = datasetSnapshot.restore(
        currentDatasetsById,
      );
    }

    logic.connections
      ..clear()
      ..addAll(
        connections.map(
          (Map<String, dynamic> connection) => _deepCloneJsonMap(connection),
        ),
      );

    logic.nodeGroups
      ..clear()
      ..addAll(nodeGroups.map((CanvasNodeGroup group) => group.copy()));
    logic._ungroupedAutomaticRootNodeIds
      ..clear()
      ..addAll(ungroupedAutomaticRootNodeIds);

    logic._nodeRamSnapshots
      ..clear()
      ..addAll(<String, Map<String, DatasetArtifactSnapshot>>{
        for (final MapEntry<String, Map<String, DatasetArtifactSnapshot>> entry
            in nodeRamSnapshots.entries)
          entry.key: Map<String, DatasetArtifactSnapshot>.from(entry.value),
      });
    logic._nodeDiskSnapshotIds
      ..clear()
      ..addAll(<String, Set<String>>{
        for (final MapEntry<String, Set<String>> entry
            in nodeDiskSnapshotIds.entries)
          entry.key: Set<String>.from(entry.value),
      });

    logic.selectedNodeId = selectedNodeId;
    logic.selectedNodeIds
      ..clear()
      ..addAll(selectedNodeIds);
    logic.selectedConnectionIndex = selectedConnectionIndex;
    logic._pendingFromNodeId = pendingFromNodeId;
    logic._pendingFromPortIndex = pendingFromPortIndex;
  }
}

class _MemoryRowWidget extends StatelessWidget {
  const _MemoryRowWidget({
    required this.row,
    required this.supportsDisk,
    this.onLoadFromDisk,
    this.onReleaseRam,
    this.onSaveToDisk,
    this.onPurgeDisk,
  });

  final _MemoryRowSummary row;
  final bool supportsDisk;
  final Future<void> Function()? onLoadFromDisk;
  final Future<void> Function()? onReleaseRam;
  final Future<void> Function()? onSaveToDisk;
  final Future<void> Function()? onPurgeDisk;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${row.nodeDescriptor} • ${row.datasetLabel}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: _MemoryStatusColumn(
                label: 'Processing',
                value: row.processingLabel,
                color: switch (row.processingLabel) {
                  'Done' => const Color(0xFF43C26B),
                  'Ready' => const Color(0xFF5CC8FF),
                  'Stale' => const Color(0xFFFFB347),
                  'Partial' => const Color(0xFFC7D85A),
                  'Running' => const Color(0xFF7FE36A),
                  'Waiting' => const Color(0xFFC0CAD4),
                  'Input locked' => const Color(0xFFFFD166),
                  _ => const Color(0xFF8C98A4),
                },
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: _MemoryStatusColumn(
                label: 'RAM',
                value: row.inRam ? 'Loaded' : 'Not loaded',
                color: row.inRam
                    ? const Color(0xFF5CC8FF)
                    : const Color(0xFF8C98A4),
                actions: <Widget>[
                  OutlinedButton(
                    onPressed: onLoadFromDisk == null
                        ? null
                        : () => onLoadFromDisk!(),
                    child: const Text('Load from disk'),
                  ),
                  OutlinedButton(
                    onPressed: onReleaseRam == null
                        ? null
                        : () => onReleaseRam!(),
                    child: const Text('Purge RAM'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: _MemoryStatusColumn(
                label: 'Disk',
                value: row.onDisk ? 'Saved' : 'Not saved',
                color: row.onDisk
                    ? const Color(0xFF43C26B)
                    : const Color(0xFF8C98A4),
                actions: supportsDisk
                    ? <Widget>[
                        OutlinedButton(
                          onPressed: onSaveToDisk == null
                              ? null
                              : () => onSaveToDisk!(),
                          child: const Text('Save to disk'),
                        ),
                        OutlinedButton(
                          onPressed: onPurgeDisk == null
                              ? null
                              : () => onPurgeDisk!(),
                          child: const Text('Purge disk'),
                        ),
                      ]
                    : const <Widget>[],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: _MemoryStatusColumn(
                label: 'Precision',
                value: row.precisionLabel,
                color: const Color(0xFFD0B56E),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MemoryStatusColumn extends StatelessWidget {
  const _MemoryStatusColumn({
    required this.label,
    required this.value,
    required this.color,
    this.actions = const <Widget>[],
  });

  final String label;
  final String value;
  final Color color;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

class _ProcessingPolicyControl extends StatelessWidget {
  const _ProcessingPolicyControl({
    required this.value,
    required this.onChanged,
    this.showHeader = true,
    this.showDescription = true,
  });

  final ProcessingResponsiveness value;
  final ValueChanged<ProcessingResponsiveness> onChanged;
  final bool showHeader;
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (showHeader) ...<Widget>[
              const Text(
                'Processing',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
            ],
            DropdownButtonFormField<ProcessingResponsiveness>(
              initialValue: value,
              dropdownColor: const Color(0xFF20262E),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Responsiveness',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white70),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              items: ProcessingResponsiveness.values
                  .map(
                    (ProcessingResponsiveness option) =>
                        DropdownMenuItem<ProcessingResponsiveness>(
                          value: option,
                          child: Text(option.label),
                        ),
                  )
                  .toList(growable: false),
              onChanged: (ProcessingResponsiveness? nextValue) {
                if (nextValue != null) {
                  onChanged(nextValue);
                }
              },
            ),
            if (showDescription) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                value.description,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessingActionControl extends StatefulWidget {
  const _ProcessingActionControl({
    required this.value,
    required this.onChanged,
  });

  final ProcessingResponsiveness value;
  final ValueChanged<ProcessingResponsiveness> onChanged;

  @override
  State<_ProcessingActionControl> createState() =>
      _ProcessingActionControlState();
}

class _ProcessingActionControlState extends State<_ProcessingActionControl> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ProjectActionButton(
          label: 'Processing',
          icon: Icons.speed,
          onPressed: () {
            setState(() {
              _expanded = !_expanded;
            });
          },
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 120),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeOut,
          sizeCurve: Curves.easeOut,
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ProcessingPolicyControl(
              value: widget.value,
              onChanged: widget.onChanged,
              showHeader: false,
              showDescription: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectActionsMenu extends StatelessWidget {
  const _ProjectActionsMenu({
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.publish,
    required this.memory,
    required this.export,
    required this.load,
    required this.clear,
    required this.processingResponsiveness,
    required this.onProcessingResponsivenessChanged,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback publish;
  final VoidCallback memory;
  final VoidCallback export;
  final VoidCallback load;
  final VoidCallback clear;
  final ProcessingResponsiveness processingResponsiveness;
  final ValueChanged<ProcessingResponsiveness>
  onProcessingResponsivenessChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Divider(
            height: 20,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggleCollapsed,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Project',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.more_horiz, color: Colors.white54, size: 18),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 140),
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeOut,
            sizeCurve: Curves.easeOut,
            crossFadeState: collapsed
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ProjectActionButton(
                    label: 'Publish',
                    icon: Icons.upload,
                    onPressed: publish,
                  ),
                  const SizedBox(height: 10),
                  _ProjectActionButton(
                    label: 'Memory',
                    icon: Icons.memory,
                    onPressed: memory,
                  ),
                  const SizedBox(height: 10),
                  _ProcessingActionControl(
                    value: processingResponsiveness,
                    onChanged: onProcessingResponsivenessChanged,
                  ),
                  const SizedBox(height: 10),
                  _ProjectActionButton(
                    label: 'Load BrainStory',
                    icon: Icons.folder_open,
                    onPressed: load,
                  ),
                  const SizedBox(height: 10),
                  _ProjectActionButton(
                    label: 'Export BrainStory',
                    icon: Icons.save_alt,
                    onPressed: export,
                  ),
                  const SizedBox(height: 10),
                  _ProjectActionButton(
                    label: 'Clear All',
                    icon: Icons.delete_outline,
                    onPressed: clear,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectActionButton extends StatelessWidget {
  const _ProjectActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

Map<String, dynamic> _deepCloneJsonMap(Map<dynamic, dynamic> source) {
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in source.entries)
      entry.key.toString(): _deepCloneJsonValue(entry.value),
  };
}

dynamic _deepCloneJsonValue(dynamic value) {
  if (value is Map) {
    return _deepCloneJsonMap(value);
  }
  if (value is List) {
    return value.map(_deepCloneJsonValue).toList(growable: false);
  }
  return value;
}

class CanvasLogic {
  static const String _lastRunParamsByDatasetKey = '_lastRunParamsByDataset';

  CanvasLogic({this.runUiYieldsEnabled = true});

  @visibleForTesting
  final bool runUiYieldsEnabled;

  /// Registry of available node types in the sidebar.
  late final List<NodeType> availableNodes = NodeRegistry.entries
      .where((NodeRegistryEntry entry) => entry.visible)
      .map((NodeRegistryEntry entry) => entry.create())
      .toList(growable: false);

  final List<NodeModel> nodes = <NodeModel>[];
  final List<CanvasNodeGroup> nodeGroups = <CanvasNodeGroup>[];
  final Set<String> _ungroupedAutomaticRootNodeIds = <String>{};
  final Map<String, Dataset> datasets = <String, Dataset>{};

  /// Connection schema:
  /// {
  ///   fromNode: String,
  ///   toNode: String,
  ///   fromPort: int,
  ///   toPort: int,
  /// }
  final List<Map<String, dynamic>> connections = <Map<String, dynamic>>[];
  final ValueNotifier<RunActivity?> runActivity = ValueNotifier<RunActivity?>(
    null,
  );
  final ValueNotifier<ProcessingResponsiveness> processingResponsiveness =
      ValueNotifier<ProcessingResponsiveness>(
        ProcessingResponsiveness.responsive,
      );
  final ValueNotifier<bool> visualizerPriorityActive = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<List<RunJobEntry>> recentRunJobs =
      ValueNotifier<List<RunJobEntry>>(const <RunJobEntry>[]);
  final ValueNotifier<List<RunJobEntry>> queuedRunJobs =
      ValueNotifier<List<RunJobEntry>>(const <RunJobEntry>[]);
  final List<_QueuedRunTask> _queuedRunTasks = <_QueuedRunTask>[];
  Future<void> _runQueueTail = Future<void>.value();
  int _runQueueTaskCounter = 0;
  int _visualizerPriorityCount = 0;
  final Stopwatch _executionChunkStopwatch = Stopwatch();
  final Set<String> _runWaitingNodeIds = <String>{};
  final Set<String> _runLockedNodeIds = <String>{};
  String? _runActiveNodeId;
  DateTime? _runStartedAt;
  final Map<String, Map<String, DatasetArtifactSnapshot>> _nodeRamSnapshots =
      <String, Map<String, DatasetArtifactSnapshot>>{};
  final Map<String, Set<String>> _nodeDiskSnapshotIds = <String, Set<String>>{};
  String? _currentBrainStoryPath;

  String? selectedNodeId;
  final Set<String> selectedNodeIds = <String>{};
  int? selectedConnectionIndex;
  String? keyboardFocusedNodeId;

  String? _pendingFromNodeId;
  int? _pendingFromPortIndex;
  int _lastGeneratedNodeIdMicros = 0;
  final Map<NodeCategory, bool> _collapsedCategories = <NodeCategory, bool>{};
  final Map<String, bool> _collapsedSubcategories = <String, bool>{};

  static const double _cardWidth = 160;
  static const double _cardHeight = 72;
  static const double _spawnGap = 48;
  static const double _canvasPadding = 120;
  static const double _gridWidth = _cardWidth * 0.625;
  static const double _gridHeight = _cardHeight * 0.625;
  static const int _maxUndoDepth = 60;

  final List<_CanvasUndoSnapshot> _undoStack = <_CanvasUndoSnapshot>[];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get hasActiveRun => runActivity.value != null;

  bool get selectedMutationBlocked {
    final int? connectionIndex = selectedConnectionIndex;
    if (connectionIndex != null) {
      return _connectionMutationLockedAtIndex(connectionIndex);
    }
    final Set<String> targetIds = selectedNodeIds.isNotEmpty
        ? selectedNodeIds
        : <String>{if (selectedNodeId != null) selectedNodeId!};
    return targetIds.any(isNodeMutationLocked);
  }

  bool isNodeMutationLocked(String nodeId) {
    return hasActiveRun && _runLockedNodeIds.contains(nodeId);
  }

  bool isDatasetMutationLocked(String datasetId) {
    if (!hasActiveRun) {
      return false;
    }
    return nodes.any(
      (NodeModel node) =>
          _runLockedNodeIds.contains(node.id) &&
          _datasetsForNode(node).contains(datasetId),
    );
  }

  String? undoLast() {
    if (_undoStack.isEmpty) {
      return null;
    }
    final _CanvasUndoSnapshot snapshot = _undoStack.removeLast();
    snapshot.restore(this);
    return snapshot.label;
  }

  void _recordUndo(
    String label, {
    Set<String> datasetArtifactIds = const <String>{},
  }) {
    _undoStack.add(
      _CanvasUndoSnapshot.capture(
        this,
        label,
        datasetArtifactIds: datasetArtifactIds,
      ),
    );
    if (_undoStack.length > _maxUndoDepth) {
      _undoStack.removeAt(0);
    }
  }

  void addNode(NodeType type) {
    _recordUndo('add ${type.title}');
    final Offset spawnPosition = _nearestAvailablePosition(
      _nextSpawnPosition(),
    );
    nodes.add(_buildNode(type: type, position: spawnPosition));
  }

  NodeModel _buildNode({
    required NodeType type,
    required Offset position,
    Map<String, dynamic>? params,
  }) {
    final Map<String, dynamic> initialParams = params == null
        ? Map<String, dynamic>.from(type.defaultParams)
        : Map<String, dynamic>.from(params);
    initialParams.putIfAbsent(
      'selectedDatasetIds',
      () => datasets.values
          .map((Dataset dataset) => dataset.id)
          .toList(growable: false),
    );

    return NodeModel(
      id: _nextNodeId(),
      type: type,
      position: position,
      params: initialParams,
    );
  }

  String _nextNodeId() {
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int nextMicros = nowMicros <= _lastGeneratedNodeIdMicros
        ? _lastGeneratedNodeIdMicros + 1
        : nowMicros;
    _lastGeneratedNodeIdMicros = nextMicros;
    return nextMicros.toString();
  }

  Offset snapToGrid(Offset offset) {
    return Offset(
      _snapCoordinate(offset.dx, _gridWidth),
      _snapCoordinate(offset.dy, _gridHeight),
    );
  }

  Size canvasSizeForViewport(Size viewport) {
    double width = viewport.width;
    double height = viewport.height;

    for (final NodeModel node in nodes) {
      width = width < node.position.dx + _cardWidth + _canvasPadding
          ? node.position.dx + _cardWidth + _canvasPadding
          : width;
      height = height < node.position.dy + _cardHeight + _canvasPadding
          ? node.position.dy + _cardHeight + _canvasPadding
          : height;
    }

    return Size(width, height);
  }

  void clearAll({bool recordUndo = true}) {
    if (hasActiveRun) {
      return;
    }
    if (recordUndo &&
        (nodes.isNotEmpty ||
            nodeGroups.isNotEmpty ||
            connections.isNotEmpty ||
            _nodeRamSnapshots.isNotEmpty ||
            _nodeDiskSnapshotIds.isNotEmpty)) {
      _recordUndo('clear all');
    }
    _clearAll();
  }

  void _clearAll() {
    nodes.clear();
    nodeGroups.clear();
    _ungroupedAutomaticRootNodeIds.clear();
    connections.clear();
    _nodeRamSnapshots.clear();
    _nodeDiskSnapshotIds.clear();
    selectedNodeId = null;
    selectedNodeIds.clear();
    selectedConnectionIndex = null;
    keyboardFocusedNodeId = null;
    recentRunJobs.value = const <RunJobEntry>[];
    queuedRunJobs.value = const <RunJobEntry>[];
    _queuedRunTasks.clear();
    runActivity.value = null;
    visualizerPriorityActive.value = false;
    _visualizerPriorityCount = 0;
    _executionChunkStopwatch.reset();
    _runWaitingNodeIds.clear();
    _runLockedNodeIds.clear();
    _runActiveNodeId = null;
    _runStartedAt = null;
    _clearPendingConnection();
  }

  Future<void> pickFiles() async {
    final List<XFile> files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'BrainStory Signals',
          extensions: <String>[
            'csv',
            'tsv',
            'txt',
            'edf',
            'cnt',
            'set',
            'fdt',
            'vhdr',
          ],
        ),
      ],
    );

    if (files.isNotEmpty) {
      _recordUndo('import files');
    }

    for (final XFile file in files) {
      final String normalizedPath = brainVisionHeaderPathForSelection(
        eeglabMetadataPathForSelection(file.path),
      );
      final bool selectedFdt = file.name.toLowerCase().endsWith('.fdt');
      final bool selectedBrainVisionSidecar =
          file.name.toLowerCase().endsWith('.eeg') ||
          file.name.toLowerCase().endsWith('.vmrk');
      final bool selectedAntCnt = file.name.toLowerCase().endsWith('.cnt');
      final bool hasDesktopPath = !kIsWeb && normalizedPath.trim().isNotEmpty;
      final Uint8List? bytes =
          (hasDesktopPath ||
              selectedFdt ||
              selectedBrainVisionSidecar ||
              selectedAntCnt)
          ? null
          : await file.readAsBytes();
      final String sourceName = selectedFdt
          ? '${file.name.substring(0, file.name.length - 4)}.set'
          : selectedBrainVisionSidecar
          ? '${file.name.substring(0, file.name.length - 4)}.vhdr'
          : file.name;
      final Dataset dataset = datasets.putIfAbsent(
        normalizedPath.isEmpty ? sourceName : normalizedPath,
        () => Dataset(
          DateTime.now().microsecondsSinceEpoch.toString(),
          label: sourceName,
          path: normalizedPath,
          sourceBytes: bytes,
        ),
      );
      dataset.label = sourceName;
      dataset.path = normalizedPath;
      dataset.sourceBytes = bytes;
      dataset.ram['source.filename'] = sourceName;
      _markAllNodes(dataset.id, DatasetState.notReady);
      _refreshDatasetAvailability(dataset.id);
    }
  }

  Future<void> removeDataset(String datasetId) async {
    if (isDatasetMutationLocked(datasetId)) {
      return;
    }
    final MapEntry<String, Dataset>? entry = datasets.entries
        .cast<MapEntry<String, Dataset>?>()
        .firstWhere(
          (MapEntry<String, Dataset>? item) => item?.value.id == datasetId,
          orElse: () => null,
        );
    if (entry == null) {
      return;
    }

    _recordUndo('remove dataset');
    datasets.remove(entry.key);

    for (final NodeModel node in nodes) {
      node.datasetStates.remove(datasetId);

      final List<dynamic>? selected =
          node.params['selectedDatasetIds'] as List<dynamic>?;
      if (selected != null) {
        node.params['selectedDatasetIds'] = selected
            .where((dynamic value) => value?.toString() != datasetId)
            .toList(growable: false);
      }

      if (node.type is ImportNodeType) {
        final Map<String, dynamic> aliases = Map<String, dynamic>.from(
          node.params['datasetAliases'] as Map? ?? const <String, dynamic>{},
        );
        if (aliases.remove(datasetId) != null) {
          node.params['datasetAliases'] = aliases;
        }
      }

      final Map<String, dynamic> channelEditsByDataset =
          Map<String, dynamic>.from(
            node.params['channelEditsByDataset'] as Map? ??
                const <String, dynamic>{},
          );
      if (channelEditsByDataset.remove(datasetId) != null) {
        node.params['channelEditsByDataset'] = channelEditsByDataset;
      }

      final List<dynamic> markers =
          (node.params['markers'] as List<dynamic>? ?? const <dynamic>[]);
      if (markers.isNotEmpty) {
        node.params['markers'] = markers
            .where(
              (dynamic marker) =>
                  marker is! Map || marker['datasetId'] != datasetId,
            )
            .toList(growable: false);
      }

      for (final String key in <String>[
        'artifactExemplars',
        'artifactCandidates',
        'artifactTemplates',
      ]) {
        final List<dynamic> values =
            (node.params[key] as List<dynamic>? ?? const <dynamic>[]);
        if (values.isNotEmpty) {
          node.params[key] = values
              .where(
                (dynamic item) =>
                    item is! Map || item['datasetId'] != datasetId,
              )
              .toList(growable: false);
        }
      }
    }

    for (final String nodeId in _nodeRamSnapshots.keys.toList(
      growable: false,
    )) {
      final Map<String, DatasetArtifactSnapshot>? snapshots =
          _nodeRamSnapshots[nodeId];
      if (snapshots?.remove(datasetId) != null &&
          (snapshots?.isEmpty ?? false)) {
        _nodeRamSnapshots.remove(nodeId);
      }
    }

    for (final String nodeId in _nodeDiskSnapshotIds.keys.toList(
      growable: false,
    )) {
      final Set<String>? diskIds = _nodeDiskSnapshotIds[nodeId];
      if (diskIds?.remove(datasetId) ?? false) {
        await deleteNodeSnapshotFromDisk(nodeId: nodeId, datasetId: datasetId);
        if (diskIds!.isEmpty) {
          _nodeDiskSnapshotIds.remove(nodeId);
        }
      }
    }

    for (final NodeModel node in nodes) {
      if (node.type is ImportNodeType) {
        ImportNodeType.applyDatasetAliases(node.params, datasets.values);
      }
    }
    for (final Dataset remaining in datasets.values) {
      _refreshDatasetAvailability(remaining.id);
    }
  }

  void deleteSelected() {
    final Set<String> targetIds = selectedNodeIds.isNotEmpty
        ? Set<String>.from(selectedNodeIds)
        : <String>{if (selectedNodeId != null) selectedNodeId!};
    if (targetIds.isEmpty) return;
    if (targetIds.any(isNodeMutationLocked)) return;

    _recordUndo(targetIds.length == 1 ? 'delete node' : 'delete nodes');
    nodes.removeWhere((node) => targetIds.contains(node.id));
    _ungroupedAutomaticRootNodeIds.removeAll(targetIds);
    _pruneNodeGroups();
    connections.removeWhere(
      (connection) =>
          targetIds.contains(connection['fromNode']) ||
          targetIds.contains(connection['toNode']),
    );

    selectedNodeId = null;
    selectedNodeIds.clear();
    selectedConnectionIndex = null;
    if (targetIds.contains(keyboardFocusedNodeId)) {
      keyboardFocusedNodeId = null;
    }
    _clearPendingConnection();
  }

  void deleteSelectedConnection() {
    final int? index = selectedConnectionIndex;
    if (index == null || index < 0 || index >= connections.length) {
      return;
    }
    if (_connectionMutationLockedAtIndex(index)) {
      return;
    }
    _recordUndo('delete wire');
    connections.removeAt(index);
    selectedConnectionIndex = null;
  }

  void selectNodesInRect(Rect selectionRect) {
    selectedNodeIds.clear();
    for (final NodeModel node in nodes) {
      final Rect nodeRect = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        _cardWidth,
        _cardHeight,
      );
      if (selectionRect.overlaps(nodeRect)) {
        selectedNodeIds.add(node.id);
      }
    }
    selectedNodeId = selectedNodeIds.isEmpty ? null : selectedNodeIds.first;
    selectedConnectionIndex = null;
    if (selectedNodeIds.isNotEmpty) {
      _clearPendingConnection();
    }
  }

  bool selectConnectionAt(Offset canvasOffset) {
    final int? index = _connectionIndexAt(canvasOffset);
    if (index == null) {
      return false;
    }
    selectedNodeId = null;
    selectedNodeIds.clear();
    selectedConnectionIndex = index;
    _clearPendingConnection();
    return true;
  }

  bool deleteConnectionAt(Offset canvasOffset) {
    final int? index = _connectionIndexAt(canvasOffset);
    if (index == null) {
      return false;
    }
    if (_connectionMutationLockedAtIndex(index)) {
      return false;
    }
    _recordUndo('delete wire');
    connections.removeAt(index);
    selectedConnectionIndex = null;
    return true;
  }

  bool _connectionMutationLockedAtIndex(int index) {
    if (!hasActiveRun || index < 0 || index >= connections.length) {
      return false;
    }
    final Map<String, dynamic> connection = connections[index];
    return _runLockedNodeIds.contains(connection['fromNode']) ||
        _runLockedNodeIds.contains(connection['toNode']);
  }

  void clearConnectionDraft() {
    _clearPendingConnection();
  }

  NodeModel? get keyboardFocusedNode {
    final String? focusedId = keyboardFocusedNodeId;
    return focusedId == null ? null : _findNode(focusedId);
  }

  void setKeyboardFocusedNode(NodeModel? node) {
    keyboardFocusedNodeId = node?.id;
  }

  void activateNodeFromKeyboard(NodeModel node) {
    keyboardFocusedNodeId = node.id;
    _handleNodeTap(node);
  }

  void openNodeEditorFromKeyboard({
    required BuildContext context,
    required NodeModel node,
    required VoidCallback update,
  }) {
    if (isNodeMutationLocked(node.id)) {
      _showStatusSnackBar(
        context,
        '${node.title} is locked while its current job is running.',
      );
      return;
    }
    keyboardFocusedNodeId = node.id;
    selectedNodeId = node.id;
    selectedNodeIds
      ..clear()
      ..add(node.id);
    selectedConnectionIndex = null;
    _openNodeEditor(context: context, node: node, update: update);
  }

  void _clearPendingConnection() {
    _pendingFromNodeId = null;
    _pendingFromPortIndex = null;
  }

  void _collectNodeBranches(
    NodeModel node,
    List<NodeModel> currentBranch,
    List<List<NodeModel>> branches,
  ) {
    final List<NodeModel> nextBranch = <NodeModel>[...currentBranch, node];
    final List<NodeModel> children = _immediateChildren(node.id);
    if (children.isEmpty) {
      branches.add(nextBranch);
      return;
    }
    for (final NodeModel child in children) {
      _collectNodeBranches(child, nextBranch, branches);
    }
  }

  String _datasetTypeLabel(Dataset dataset) {
    final String path = dataset.path.toLowerCase();
    if (path.endsWith('.edf')) {
      return 'EDF';
    }
    if (path.endsWith('.cnt')) {
      return 'ANT CNT';
    }
    if (path.endsWith('.set') || path.endsWith('.fdt')) {
      return 'EEGLAB';
    }
    if (path.endsWith('.csv')) {
      return 'CSV';
    }
    if (path.endsWith('.tsv')) {
      return 'TSV';
    }
    if (path.endsWith('.txt')) {
      return 'text';
    }
    return '';
  }

  String _methodsClauseForNode(NodeModel node) {
    final Map<String, dynamic> params = node.params;
    switch (node.title) {
      case 'Import':
        return 'Data were imported into the workflow.';
      case 'Bridge Detector':
        final int windowSamples =
            (params['windowSamples'] as num?)?.toInt() ?? 1000;
        return 'Bridge detection was performed by computing channel-wise correlation matrices over the last $windowSamples samples of each full minute of recording.';
      case 'Resample':
        final double sampleRate =
            (params['newSampleRate'] as num?)?.toDouble() ?? 256.0;
        final String method = (params['method'] ?? 'cubic_spline')
            .toString()
            .replaceAll('_', ' ');
        final bool omitSpikes = (params['omitSpikes'] as bool?) ?? false;
        return 'Signals were resampled to ${sampleRate.toStringAsFixed(sampleRate.truncateToDouble() == sampleRate ? 0 : 2)} Hz using $method interpolation${omitSpikes ? ' with spike omission enabled' : ''}.';
      case 'Bandpass Filter':
        final double low = (params['low'] as num?)?.toDouble() ?? 1.0;
        final double high = (params['high'] as num?)?.toDouble() ?? 40.0;
        final double steepness =
            (params['steepness'] as num?)?.toDouble() ?? 0.5;
        final double? notch = (params['notch'] as num?)?.toDouble();
        return 'A bandpass filter ($low-$high Hz, steepness $steepness${notch == null ? '' : ', notch at $notch Hz'}) was applied.';
      case 'PSD':
        final double fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
        final double fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
        final String outputMode = (params['outputMode'] ?? 'averaged')
            .toString();
        return 'Power spectral density was estimated from $fLow to $fHigh Hz using ${outputMode == 'segments' ? 'segment-wise output' : 'averaged output'}.';
      case 'FOOOF':
        final double fLow = (params['fLow'] as num?)?.toDouble() ?? 1.0;
        final double fHigh = (params['fHigh'] as num?)?.toDouble() ?? 40.0;
        final int maxPeaks = (params['maxPeaks'] as num?)?.toInt() ?? 4;
        return 'Spectral parameterization was performed from $fLow to $fHigh Hz to estimate the aperiodic intercept and exponent and to identify up to $maxPeaks oscillatory peaks.';
      case 'Spectral Features':
        final List<String> groups = _selectedSpectralFeatureGroups(params);
        return 'Spectral features were extracted from the PSD${groups.isEmpty ? '' : ' (${_joinWithCommas(groups)})'} and assembled into a tabular output.';
      case 'Amplitude Features':
        final List<String> groups = _selectedAmplitudeFeatureGroups(params);
        return 'Time-domain amplitude features were extracted from the signal${groups.isEmpty ? '' : ' (${_joinWithCommas(groups)})'} and assembled into a tabular output.';
      case 'Segmentation':
        return _segmentationMethodsClause(params);
      case 'Realign':
        final double upsampleRate =
            (params['upsampleRateHz'] as num?)?.toDouble() ?? 100000.0;
        final String method = (params['method'] ?? 'cubic_spline')
            .toString()
            .replaceAll('_', ' ');
        final double maxShiftMs =
            (params['maxShiftMs'] as num?)?.toDouble() ?? 5.0;
        return 'Segmented data were temporarily upsampled to ${upsampleRate.toStringAsFixed(0)} Hz, realigned by cross-correlation using $method interpolation with a maximum shift of $maxShiftMs ms, and then returned to the original sampling rate.';
      case 'Sleep Staging':
        final double epochSeconds =
            (params['epochSeconds'] as num?)?.toDouble() ?? 30.0;
        return 'Sleep-stage markers were generated in ${epochSeconds.toStringAsFixed(epochSeconds.truncateToDouble() == epochSeconds ? 0 : 1)}-second epochs while the underlying time-series data were passed through unchanged.';
      case 'Eye Blinks':
        return 'Ocular-event marker detection was configured to emit blink, vertical saccade, and horizontal saccade markers.';
      case 'Interactive Artifact Detection':
        return 'Artifact exemplars were labeled interactively in the time-domain viewer, evolving templates were built by aligned averaging, and candidate artifact matches were reviewed and accepted or rejected within the workflow.';
      case 'Edit Markers':
      case 'Add/Remove Markers':
        return 'Manual marker edits were incorporated into the analysis graph.';
      case 'Edit Channels and Markers':
        return 'Manual channel edits and marker edits were incorporated together into the analysis graph.';
      case 'PCA':
      case 'ICA':
      case 'Eigenvalue Decomposition':
      case 'Microstates':
      case 'K-Means':
      case 'CNN':
        return '${node.title} was included as a configured processing stage in the workflow.';
      case 'EEG Visualization':
        return 'A dedicated visualization node was used for explicit comparison of outputs across branches of the pipeline.';
      case 'Debug Output':
        return 'Intermediate outputs were inspected using a debug-output node.';
      case 'Export':
        final String fileType = (params['fileType'] ?? 'edf')
            .toString()
            .toUpperCase();
        return 'Processed outputs were exported as $fileType files.';
      case 'Publish':
        return 'A publish endpoint was configured to generate manuscript-ready descriptions of the workflow and its outputs.';
      default:
        return '${node.title} was included as a processing stage.';
    }
  }

  List<String> _selectedSpectralFeatureGroups(Map<String, dynamic> params) {
    final Map<String, String> labels = <String, String>{
      'power': 'power features',
      'ratios': 'power ratios',
    };
    final List<String> selected = <String>[];
    for (final MapEntry<String, String> entry in labels.entries) {
      if ((params[entry.key] as bool?) ?? false) {
        selected.add(entry.value);
      }
    }
    return selected;
  }

  List<String> _selectedAmplitudeFeatureGroups(Map<String, dynamic> params) {
    final Map<String, String> labels = <String, String>{
      'peak_amplitude': 'peak amplitude',
      'peak_latency': 'peak latency',
      'auc': 'area under the curve',
      'variance': 'variance',
    };
    final Map<String, dynamic> selectedMap = Map<String, dynamic>.from(
      params['amplitudeFeatures'] as Map? ?? <String, dynamic>{},
    );
    final List<String> selected = <String>[];
    for (final MapEntry<String, String> entry in labels.entries) {
      if (selectedMap[entry.key] == true) {
        selected.add(entry.value);
      }
    }
    return selected;
  }

  String _segmentationMethodsClause(Map<String, dynamic> params) {
    final String mode = (params['segmentationMode'] ?? 'events').toString();
    if (mode == 'blocks') {
      final bool concatenate = (params['blocksConcatenate'] as bool?) ?? false;
      final bool invert = (params['blocksInvert'] as bool?) ?? false;
      return 'Data were segmented into marker-defined blocks${concatenate ? ', and multiple blocks were concatenated' : ''}${invert ? ', using the complement of the selected blocks' : ''}.';
    }
    if (mode == 'equal_windows') {
      final double widthMs =
          (params['equalWidthMs'] as num?)?.toDouble() ?? 1000.0;
      final double overlapPct =
          (params['equalOverlapPct'] as num?)?.toDouble() ?? 0.0;
      return 'Data were segmented into equal windows of ${widthMs.toStringAsFixed(widthMs.truncateToDouble() == widthMs ? 0 : 1)} ms with ${overlapPct.toStringAsFixed(overlapPct.truncateToDouble() == overlapPct ? 0 : 1)}% overlap.';
    }
    final double windowStart =
        (params['eventsWindowStartMs'] as num?)?.toDouble() ?? 0.0;
    final double windowStop =
        (params['eventsWindowStopMs'] as num?)?.toDouble() ?? 0.0;
    final bool applyBaseline = params['eventApplyBaseline'] as bool? ?? false;
    final double baselineStart =
        (params['eventBaselineStartMs'] as num?)?.toDouble() ?? -200.0;
    final double baselineStop =
        (params['eventBaselineStopMs'] as num?)?.toDouble() ?? 0.0;
    final String baselineDescription = applyBaseline
        ? ' with artifact baseline correction from ${baselineStart.toStringAsFixed(baselineStart.truncateToDouble() == baselineStart ? 0 : 1)} to ${baselineStop.toStringAsFixed(baselineStop.truncateToDouble() == baselineStop ? 0 : 1)} ms'
        : ' without artifact baseline correction';
    return 'Event-locked segmentation was performed with a window from ${windowStart.toStringAsFixed(windowStart.truncateToDouble() == windowStart ? 0 : 1)} to ${windowStop.toStringAsFixed(windowStop.truncateToDouble() == windowStop ? 0 : 1)} ms$baselineDescription.';
  }

  String _joinWithCommas(List<String> values) {
    if (values.isEmpty) {
      return '';
    }
    if (values.length == 1) {
      return values.first;
    }
    if (values.length == 2) {
      return '${values.first} and ${values.last}';
    }
    return '${values.sublist(0, values.length - 1).join(', ')}, and ${values.last}';
  }

  List<String> _methodsClausesForBranch(List<NodeModel> branch) {
    return branch
        .map(_methodsClauseForNode)
        .where((String clause) => clause.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<String> _longestCommonClausePrefix(List<List<String>> branches) {
    if (branches.isEmpty) {
      return const <String>[];
    }
    final int maxPrefixLength = branches
        .map((List<String> branch) => branch.length)
        .reduce(math.min);
    final List<String> prefix = <String>[];
    for (int index = 0; index < maxPrefixLength; index++) {
      final String candidate = branches.first[index];
      final bool allMatch = branches.every(
        (List<String> branch) => branch[index] == candidate,
      );
      if (!allMatch) {
        break;
      }
      prefix.add(candidate);
    }
    return prefix;
  }

  Future<void> exportBrainStory(BuildContext context) async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'brainstory_project.bst',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'BrainStory Project', extensions: <String>['bst']),
      ],
    );
    if (location == null) {
      return;
    }

    final String jsonPayload = const JsonEncoder.withIndent(
      '  ',
    ).convert(exportProjectJson());
    final String? savedPath = await saveBrainStoryProject(
      suggestedName: 'brainstory_project',
      targetPath: location.path,
      jsonPayload: jsonPayload,
    );
    if (savedPath != null) {
      await _rememberBrainStoryPath(savedPath);
    }
    if (context.mounted) {
      _showStatusSnackBar(
        context,
        savedPath == null
            ? 'BrainStory export was canceled.'
            : 'Saved BrainStory project to $savedPath.',
      );
    }
  }

  Future<void> loadBrainStory(BuildContext context) async {
    if (hasActiveRun) {
      if (context.mounted) {
        _showStatusSnackBar(
          context,
          'Project loading is paused until the active job finishes.',
        );
      }
      return;
    }
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'BrainStory Project', extensions: <String>['bst']),
      ],
    );
    if (file == null) {
      return;
    }

    try {
      await _loadBrainStoryJsonPayload(await file.readAsString());
      final String path = file.path.trim();
      if (path.isNotEmpty) {
        await _rememberBrainStoryPath(path);
      }
      if (context.mounted) {
        _showStatusSnackBar(
          context,
          'Loaded BrainStory project from ${file.name}.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showStatusSnackBar(
          context,
          'Could not load BrainStory project: $error',
        );
      }
    }
  }

  Future<bool> restoreLastBrainStory() async {
    final String? path = await readRecentBrainStoryPath();
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    try {
      await _loadBrainStoryFromPath(path);
      return true;
    } catch (_) {
      await writeRecentBrainStoryPath(null);
      return false;
    }
  }

  Future<void> showPublishDialog(BuildContext context) async {
    final String methodsText = generateMethodsDescription();
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Publish'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(child: SelectableText(methodsText)),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: methodsText));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (context.mounted) {
                  _showStatusSnackBar(
                    context,
                    'Copied publish-ready methods text to the clipboard.',
                  );
                }
              },
              child: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadBrainStoryFromPath(String path) async {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    final String jsonPayload = await XFile(normalizedPath).readAsString();
    await _loadBrainStoryJsonPayload(jsonPayload);
    await _rememberBrainStoryPath(normalizedPath);
  }

  Future<void> _loadBrainStoryJsonPayload(String jsonPayload) async {
    final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(
      jsonDecode(jsonPayload) as Map,
    );
    _recordUndo('load BrainStory');
    importProjectJson(jsonMap);
    await _refreshDiskSnapshotFlagsForLoadedProject();
    _normalizeNodeStatesAfterProjectLoad();
  }

  Future<void> _rememberBrainStoryPath(String path) async {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty || normalizedPath == _currentBrainStoryPath) {
      return;
    }
    _currentBrainStoryPath = normalizedPath;
    await writeRecentBrainStoryPath(normalizedPath);
  }

  String generateMethodsDescription() {
    if (nodes.isEmpty) {
      return 'No BrainStory pipeline is currently defined.';
    }

    final List<String> datasetLabels =
        datasets.values
            .map(
              (Dataset dataset) => dataset.label.trim().isEmpty
                  ? 'Dataset'
                  : dataset.label.trim(),
            )
            .toList(growable: false)
          ..sort();
    final Set<String> datasetTypes = datasets.values
        .map(_datasetTypeLabel)
        .where((String type) => type.isNotEmpty)
        .toSet();
    final List<NodeModel> roots = nodes
        .where((NodeModel node) => _immediateParents(node.id).isEmpty)
        .toList(growable: false);
    final List<List<NodeModel>> branches = <List<NodeModel>>[];
    for (final NodeModel root in roots) {
      _collectNodeBranches(root, <NodeModel>[], branches);
    }
    final List<List<String>> branchClauses = branches
        .map(_methodsClausesForBranch)
        .where((List<String> clauses) => clauses.isNotEmpty)
        .toList(growable: false);
    final List<List<String>> uniqueBranchClauses = <List<String>>[];
    final Set<String> seenBranchTexts = <String>{};
    for (final List<String> clauses in branchClauses) {
      final String branchKey = clauses.join(' ');
      if (seenBranchTexts.add(branchKey)) {
        uniqueBranchClauses.add(clauses);
      }
    }
    final List<String> sharedPrefix = _longestCommonClausePrefix(
      uniqueBranchClauses,
    );
    final List<List<String>> branchSuffixes = uniqueBranchClauses
        .map(
          (List<String> clauses) => clauses.length <= sharedPrefix.length
              ? const <String>[]
              : clauses.sublist(sharedPrefix.length),
        )
        .toList(growable: false);

    final StringBuffer buffer = StringBuffer();
    buffer.writeln(
      'Data were processed in BrainStory using a node-based analysis pipeline.',
    );
    if (datasetLabels.isNotEmpty) {
      final String datasetSummary = datasetLabels.length == 1
          ? datasetLabels.first
          : '${datasetLabels.length} datasets (${_joinWithCommas(datasetLabels)})';
      if (datasetTypes.isNotEmpty) {
        final List<String> sortedTypes = datasetTypes.toList(growable: false)
          ..sort();
        buffer.writeln(
          'The workflow operated on $datasetSummary imported from ${_joinWithCommas(sortedTypes)} source files.',
        );
      } else {
        buffer.writeln('The workflow operated on $datasetSummary.');
      }
    }
    buffer.writeln();
    buffer.writeln('Pipeline summary:');

    if (uniqueBranchClauses.isEmpty) {
      final String fallback = nodes
          .map(_methodsClauseForNode)
          .where((String clause) => clause.isNotEmpty)
          .join(' ');
      buffer.writeln('1. $fallback');
    } else if (uniqueBranchClauses.length == 1) {
      buffer.writeln('1. ${uniqueBranchClauses.first.join(' ')}');
    } else {
      if (sharedPrefix.isNotEmpty) {
        buffer.writeln('Shared preprocessing: ${sharedPrefix.join(' ')}');
        buffer.writeln();
        buffer.writeln(
          'After the shared preprocessing steps, the workflow diverged into ${uniqueBranchClauses.length} analysis branches:',
        );
      }

      int branchNumber = 1;
      for (final List<String> suffix in branchSuffixes) {
        final String branchText = suffix.isEmpty
            ? 'No additional branch-specific processing steps were applied.'
            : suffix.join(' ');
        buffer.writeln('$branchNumber. $branchText');
        branchNumber++;
      }
    }

    if (nodes.any(canVisualizeNode)) {
      buffer.writeln();
      buffer.writeln(
        'Outputs were reviewed visually within BrainStory using node-linked inspection views appropriate to each data type, including raw time-domain traces, power spectra, hypnograms, and bridge-detection heatmaps when available.',
      );
    }

    return buffer.toString().trimRight();
  }

  Map<String, dynamic> exportProjectJson() {
    return <String, dynamic>{
      'format': 'brainstory_project',
      'version': 1,
      'datasets': datasets.values
          .map(
            (Dataset dataset) => <String, dynamic>{
              'id': dataset.id,
              'label': dataset.label,
              'path': dataset.path,
              'loaded': dataset.loaded,
              'sourceFilename': dataset.ram['source.filename'],
              'sourceBytesBase64': dataset.sourceBytes == null
                  ? null
                  : base64Encode(dataset.sourceBytes!),
            },
          )
          .toList(growable: false),
      'nodes': nodes
          .map(
            (NodeModel node) => <String, dynamic>{
              'id': node.id,
              'type': node.type.title,
              'x': node.position.dx,
              'y': node.position.dy,
              'params': _exportableNodeParams(node.params),
              'markerChange': node.markerChange.toJson(),
              'datasetStates': node.datasetStates.map(
                (dynamic key, DatasetState value) =>
                    MapEntry<String, dynamic>(key.toString(), value.name),
              ),
            },
          )
          .toList(growable: false),
      'nodeGroups': nodeGroups
          .map((CanvasNodeGroup group) => group.toJson())
          .toList(growable: false),
      'ungroupedAutomaticRootNodeIds': _ungroupedAutomaticRootNodeIds.toList(
        growable: false,
      ),
      'connections': connections
          .map(
            (Map<String, dynamic> connection) =>
                Map<String, dynamic>.from(connection),
          )
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _exportableNodeParams(Map<String, dynamic> params) {
    return Map<String, dynamic>.fromEntries(
      params.entries.where((MapEntry<String, dynamic> entry) {
        return !entry.key.startsWith('_');
      }),
    );
  }

  void importProjectJson(Map<String, dynamic> jsonMap) {
    clearAll(recordUndo: false);
    datasets.clear();

    final List<dynamic> datasetEntries =
        jsonMap['datasets'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic entry in datasetEntries) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(entry as Map);
      final String path = data['path']?.toString() ?? '';
      final String label = data['label']?.toString() ?? 'Dataset';
      final String id =
          data['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final String? sourceBytesBase64 = data['sourceBytesBase64']?.toString();
      final Uint8List? sourceBytes =
          sourceBytesBase64 == null || sourceBytesBase64.isEmpty
          ? null
          : Uint8List.fromList(base64Decode(sourceBytesBase64));
      final Dataset dataset = Dataset(
        id,
        label: label,
        path: path,
        sourceBytes: sourceBytes,
      );
      dataset.loaded = data['loaded'] as bool? ?? false;
      final String sourceFilename = data['sourceFilename']?.toString() ?? '';
      if (sourceFilename.isNotEmpty) {
        dataset.ram['source.filename'] = sourceFilename;
      }
      datasets[path.isEmpty ? id : path] = dataset;
    }

    final List<dynamic> nodeEntries =
        jsonMap['nodes'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic entry in nodeEntries) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(entry as Map);
      final NodeType? type = _nodeTypeByTitle(data['type']?.toString() ?? '');
      if (type == null) {
        continue;
      }
      final NodeModel node = NodeModel(
        id:
            data['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        position: Offset(
          (data['x'] as num?)?.toDouble() ?? 0,
          (data['y'] as num?)?.toDouble() ?? 0,
        ),
        params: Map<String, dynamic>.from(
          data['params'] as Map? ?? <String, dynamic>{},
        ),
        markerChange: data['markerChange'] is Map<String, dynamic>
            ? MarkerChange.fromJson(
                data['markerChange'] as Map<String, dynamic>,
              )
            : data['markerChange'] is Map
            ? MarkerChange.fromJson(
                Map<String, dynamic>.from(data['markerChange'] as Map),
              )
            : const MarkerChange(),
      );
      final Map<String, dynamic> rawStates = Map<String, dynamic>.from(
        data['datasetStates'] as Map? ?? <String, dynamic>{},
      );
      for (final MapEntry<String, dynamic> stateEntry in rawStates.entries) {
        node.datasetStates[stateEntry.key] = _datasetStateFromName(
          stateEntry.value?.toString(),
        );
      }
      nodes.add(node);
    }

    final Set<String> importedNodeIds = nodes
        .map((NodeModel node) => node.id)
        .toSet();
    final List<dynamic> groupEntries =
        jsonMap['nodeGroups'] as List<dynamic>? ?? const <dynamic>[];
    for (final dynamic entry in groupEntries) {
      final CanvasNodeGroup group = CanvasNodeGroup.fromJson(
        Map<String, dynamic>.from(entry as Map),
      );
      group.nodeIds.removeWhere(
        (String nodeId) => !importedNodeIds.contains(nodeId),
      );
      if (group.id.isNotEmpty && group.nodeIds.length > 1) {
        nodeGroups.add(group);
      }
    }
    _ungroupedAutomaticRootNodeIds.addAll(
      (jsonMap['ungroupedAutomaticRootNodeIds'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic value) => value.toString()),
    );

    final List<dynamic> connectionEntries =
        jsonMap['connections'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic entry in connectionEntries) {
      connections.add(Map<String, dynamic>.from(entry as Map));
    }
  }

  Widget sidebar({
    required double width,
    required VoidCallback publish,
    required VoidCallback memory,
    required VoidCallback export,
    required VoidCallback load,
    required VoidCallback clear,
    required bool projectActionsCollapsed,
    required VoidCallback toggleProjectActionsCollapsed,
    required VoidCallback update,
  }) {
    final List<NodeCategory> categoryOrder = <NodeCategory>[
      NodeCategory.import,
      NodeCategory.transform,
      NodeCategory.machineLearning,
      NodeCategory.markerFunctions,
      NodeCategory.endpoints,
    ];

    return Container(
      width: width,
      color: Colors.grey[900],
      child: Column(
        children: <Widget>[
          const SizedBox(height: 20),
          const Text(
            'Nodes',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                for (final NodeCategory category in categoryOrder)
                  ..._sidebarCategorySection(
                    category: category,
                    update: update,
                  ),
              ],
            ),
          ),
          _ProjectActionsMenu(
            collapsed: projectActionsCollapsed,
            onToggleCollapsed: toggleProjectActionsCollapsed,
            publish: publish,
            memory: memory,
            export: export,
            load: load,
            clear: clear,
            processingResponsiveness: processingResponsiveness.value,
            onProcessingResponsivenessChanged:
                (ProcessingResponsiveness value) {
                  processingResponsiveness.value = value;
                  update();
                },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<Widget> _sidebarCategorySection({
    required NodeCategory category,
    required VoidCallback update,
  }) {
    final List<NodeType> categoryNodes = availableNodes
        .where((NodeType node) {
          return node.allPlacements.any(
            (NodePlacement placement) => placement.category == category,
          );
        })
        .toList(growable: false);
    final Map<String, List<NodeType>> nodesBySubcategory =
        <String, List<NodeType>>{};
    for (final NodeType type in categoryNodes) {
      for (final NodePlacement placement in type.allPlacements) {
        if (placement.category != category) {
          continue;
        }
        nodesBySubcategory
            .putIfAbsent(placement.subcategory, () => <NodeType>[])
            .add(type);
      }
    }
    for (final List<NodeType> types in nodesBySubcategory.values) {
      types.sort((NodeType a, NodeType b) => a.title.compareTo(b.title));
    }
    final List<String> subcategoryOrder = nodesBySubcategory.keys.toList()
      ..sort();
    final bool collapsed = _collapsedCategories[category] ?? false;

    return <Widget>[
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          _collapsedCategories[category] = !collapsed;
          update();
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: <Widget>[
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                color: category.color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.label,
                  style: TextStyle(
                    color: category.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (!collapsed && categoryNodes.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 32, right: 4, bottom: 6),
          child: Text(
            'No nodes yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
        ),
      if (!collapsed)
        for (final String subcategory in subcategoryOrder) ...<Widget>[
          Builder(
            builder: (BuildContext context) {
              final String collapseKey = '${category.name}::$subcategory';
              final bool subcategoryCollapsed =
                  _collapsedSubcategories[collapseKey] ?? false;
              return Column(
                children: <Widget>[
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _collapsedSubcategories[collapseKey] =
                          !subcategoryCollapsed;
                      update();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 28,
                        bottom: 6,
                        top: 2,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            subcategoryCollapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            color: Colors.white.withValues(alpha: 0.72),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              subcategory,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!subcategoryCollapsed)
                    for (final NodeType type
                        in nodesBySubcategory[subcategory]!)
                      Padding(
                        padding: const EdgeInsets.only(left: 36, bottom: 6),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: category.color.withValues(
                                alpha: 0.18,
                              ),
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: category.color.withValues(alpha: 0.35),
                              ),
                            ),
                            onPressed: () {
                              addNode(type);
                              update();
                            },
                            child: Text('+ ${type.title}'),
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ],
    ];
  }

  List<Widget> connectionWidgets() {
    final Map<String, NodeModel> nodeById = <String, NodeModel>{
      for (final NodeModel node in nodes) node.id: node,
    };
    return connections.asMap().entries.map((
      MapEntry<int, Map<String, dynamic>> entry,
    ) {
      final int connectionIndex = entry.key;
      final Map<String, dynamic> connection = entry.value;
      final NodeModel? fromNode = nodeById[connection['fromNode'] as String];
      final NodeModel? toNode = nodeById[connection['toNode'] as String];

      if (fromNode == null || toNode == null) {
        return const SizedBox.shrink();
      }

      final int fromPort = (connection['fromPort'] as num?)?.toInt() ?? 0;
      final Offset start = _outputAnchor(
        fromNode,
        toNode,
        fromPortIndex: fromPort,
      );
      final Offset end = _inputAnchor(fromNode, toNode);
      final bool preferVertical = _shouldUseVerticalAnchors(fromNode, toNode);

      return CustomPaint(
        painter: ConnectionPainter(
          start: start,
          end: end,
          preferVertical: preferVertical,
          gridWidth: _gridWidth,
          gridHeight: _gridHeight,
          obstacles: _connectionObstacles(fromNode, toNode),
          selected: selectedConnectionIndex == connectionIndex,
          color: _outputColorForPort(fromNode, fromPort),
        ),
        size: Size.infinite,
      );
    }).toList();
  }

  List<Widget> nodeGroupWidgets({required VoidCallback update}) {
    _pruneNodeGroups();
    final Map<String, NodeModel> nodeById = <String, NodeModel>{
      for (final NodeModel node in nodes) node.id: node,
    };
    return nodeGroups
        .map((CanvasNodeGroup group) {
          final List<NodeModel> members = group.nodeIds
              .map((String nodeId) => nodeById[nodeId])
              .whereType<NodeModel>()
              .toList(growable: false);
          final double left = members
              .map((NodeModel node) => node.position.dx)
              .reduce(math.min);
          final double top = members
              .map((NodeModel node) => node.position.dy)
              .reduce(math.min);
          final double right = members
              .map((NodeModel node) => node.position.dx + _cardWidth)
              .reduce(math.max);
          final double bottom = members
              .map((NodeModel node) => node.position.dy + _cardHeight)
              .reduce(math.max);
          return _CanvasNodeGroupOutline(
            rect: Rect.fromLTRB(left - 18, top - 30, right + 18, bottom + 18),
            label: group.label,
            onUngroup: () {
              ungroupNodes(group.id);
              update();
            },
          );
        })
        .toList(growable: false);
  }

  void ungroupNodes(String groupId) {
    CanvasNodeGroup? target;
    for (final CanvasNodeGroup group in nodeGroups) {
      if (group.id == groupId) {
        target = group;
        break;
      }
    }
    if (target == null) {
      return;
    }
    _recordUndo('ungroup nodes');
    if (target.automaticRootNodeId != null) {
      _ungroupedAutomaticRootNodeIds.add(target.automaticRootNodeId!);
    }
    nodeGroups.remove(target);
  }

  CanvasNodeGroup? _groupForNode(String nodeId) {
    for (final CanvasNodeGroup group in nodeGroups) {
      if (group.nodeIds.contains(nodeId)) {
        return group;
      }
    }
    return null;
  }

  void _createNodeGroup({
    required String label,
    required Set<String> nodeIds,
    String? automaticRootNodeId,
  }) {
    final Set<String> existingNodeIds = nodes
        .map((NodeModel node) => node.id)
        .toSet();
    final Set<String> validIds = nodeIds.intersection(existingNodeIds);
    if (validIds.length < 2) {
      return;
    }
    CanvasNodeGroup? existing;
    if (automaticRootNodeId != null) {
      for (final CanvasNodeGroup group in nodeGroups) {
        if (group.automaticRootNodeId == automaticRootNodeId) {
          existing = group;
          break;
        }
      }
    }
    if (existing != null) {
      existing.nodeIds
        ..clear()
        ..addAll(validIds);
      return;
    }
    for (final CanvasNodeGroup group in nodeGroups) {
      group.nodeIds.removeAll(validIds);
    }
    _pruneNodeGroups();
    nodeGroups.add(
      CanvasNodeGroup(
        id: 'group_${_nextNodeId()}',
        label: label,
        nodeIds: validIds,
        automaticRootNodeId: automaticRootNodeId,
      ),
    );
  }

  void _pruneNodeGroups() {
    final Set<String> existingNodeIds = nodes
        .map((NodeModel node) => node.id)
        .toSet();
    for (final CanvasNodeGroup group in nodeGroups) {
      group.nodeIds.removeWhere(
        (String nodeId) => !existingNodeIds.contains(nodeId),
      );
    }
    nodeGroups.removeWhere((CanvasNodeGroup group) => group.nodeIds.length < 2);
  }

  List<Widget> nodeWidgets({
    required BuildContext context,
    required VoidCallback update,
    required Offset Function(Offset globalOffset) translateDropOffset,
    required void Function(NodeModel node) openVisualizationWindow,
  }) {
    return nodes.asMap().entries.map((MapEntry<int, NodeModel> entry) {
      final int nodeNumber = entry.key + 1;
      final NodeModel node = entry.value;
      return NodeCard(
        width: _cardWidth,
        height: _cardHeight,
        title: node.title,
        nodeNumber: nodeNumber,
        position: node.position,
        color: _nodeColor(node),
        statusLabel: _statusLabel(node),
        highlighted: _isHighlighted(node),
        highlightColor: _nodeHighlightColor(node),
        done: node.visualState == DatasetState.done,
        onDragEnd: (Offset globalOffset) {
          moveNodeOrSelection(node, translateDropOffset(globalOffset));
          update();
        },
        onTap: () {
          _handleNodeTap(node);
          update();
        },
        onDoubleTap: () {
          selectedNodeId = node.id;
          selectedNodeIds
            ..clear()
            ..add(node.id);
          if (hasVisualizationOutput(node)) {
            openVisualizationWindow(node);
            return;
          }
          if (isNodeMutationLocked(node.id)) {
            _showStatusSnackBar(
              context,
              '${node.title} is locked while its current job is running.',
            );
            return;
          }
          _openNodeEditor(context: context, node: node, update: update);
        },
        onContextMenuAt: (Offset globalPosition) {
          showNodeContextMenu(
            context: context,
            node: node,
            globalPosition: globalPosition,
            update: update,
            openVisualizationWindow: openVisualizationWindow,
          );
        },
      );
    }).toList();
  }

  Future<void> showNodeContextMenu({
    required BuildContext context,
    required NodeModel node,
    required Offset globalPosition,
    required VoidCallback update,
    required void Function(NodeModel node) openVisualizationWindow,
  }) async {
    final bool mutationLocked = isNodeMutationLocked(node.id);
    final bool queueRun = hasActiveRun;
    final _NodeCombinationPlan? previousCombination =
        _combinationPlanWithPrevious(node);
    final _NodeCombinationPlan? nextCombination = previousCombination == null
        ? _combinationPlanWithNext(node)
        : null;
    final _NodeCombinationPlan? combination =
        previousCombination ?? nextCombination;
    final bool combinationLocked =
        combination != null &&
        (isNodeMutationLocked(combination.upstream.id) ||
            isNodeMutationLocked(combination.downstream.id));
    final CanvasNodeGroup? nodeGroup = _groupForNode(node.id);
    final Set<String> nodeDatasetIds = _datasetsForNode(node);
    final bool canLoadFromDisk = await _nodeHasLoadableDiskCache(
      node: node,
      datasetIds: nodeDatasetIds,
    );
    if (!context.mounted) {
      return;
    }
    final String? choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          enabled: !mutationLocked,
          child: Text(
            mutationLocked ? 'Edit Parameters (locked)' : 'Edit Parameters',
          ),
        ),
        PopupMenuItem<String>(
          value: 'run_this',
          child: Text(queueRun ? 'Queue This Step' : 'Run This Step'),
        ),
        PopupMenuItem<String>(
          value: 'run_start',
          child: Text(queueRun ? 'Queue From Start' : 'Run From Start'),
        ),
        PopupMenuItem<String>(
          value: 'load_from_disk',
          enabled: canLoadFromDisk,
          child: const Text('Load from disk'),
        ),
        const PopupMenuItem<String>(
          value: 'memory',
          child: Text('Memory management'),
        ),
        if (combination != null)
          PopupMenuItem<String>(
            value: 'combine',
            enabled: !combinationLocked,
            child: Text(
              previousCombination != null
                  ? 'Combine with Previous Node'
                  : 'Combine with Next Node',
            ),
          ),
        if (nodeGroup != null)
          const PopupMenuItem<String>(
            value: 'ungroup',
            child: Text('Ungroup Nodes'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: !mutationLocked,
          child: Text('Delete Node', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
    if (!context.mounted) {
      return;
    }

    switch (choice) {
      case 'run_this':
        if (await promptLoadFromDiskInsteadOfRun(
          context: context,
          node: node,
          datasetIds: nodeDatasetIds,
          update: update,
        )) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        String? finalDetail;
        try {
          finalDetail = await runQueued(
            label: 'Running ${node.title}',
            lockedNodeIds: _collectAncestorsInclusive(node.id),
            action: () => runThisStep(node.id),
            successDetail: () => _lastRunDatasetCount == 0
                ? 'No datasets matched ${node.title}.'
                : 'Ran ${node.title} for $_lastRunDatasetCount dataset(s).',
          );
          update();
          if (node.type is VisualizationNodeType &&
              visualizationDisplayMode(node) == 'window') {
            openVisualizationWindow(node);
          }
          if (context.mounted) {
            _showStatusSnackBar(context, finalDetail);
          }
        } catch (error) {
          finalDetail = 'Run failed: $error';
          if (context.mounted) {
            _showStatusSnackBar(context, finalDetail);
          }
        }
        return;
      case 'run_start':
        if (await promptLoadFromDiskInsteadOfRun(
          context: context,
          node: node,
          datasetIds: nodeDatasetIds,
          update: update,
        )) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        String? finalDetail;
        try {
          finalDetail = await runQueued(
            label: 'Running pipeline to ${node.title}',
            lockedNodeIds: _collectAncestorsInclusive(node.id),
            action: () => runFromStart(node.id),
            successDetail: () => _lastRunDatasetCount == 0
                ? 'No datasets matched ${node.title}.'
                : 'Ran pipeline to ${node.title} for $_lastRunDatasetCount dataset(s).',
          );
          update();
          if (node.type is VisualizationNodeType &&
              visualizationDisplayMode(node) == 'window') {
            openVisualizationWindow(node);
          }
          if (context.mounted) {
            _showStatusSnackBar(context, finalDetail);
          }
        } catch (error) {
          finalDetail = 'Run failed: $error';
          if (context.mounted) {
            _showStatusSnackBar(context, finalDetail);
          }
        }
        return;
      case 'load_from_disk':
        final String message = await _loadNodeSnapshotsToRam(
          node: node,
          datasetIds: nodeDatasetIds,
          update: update,
        );
        if (context.mounted) {
          _showStatusSnackBar(context, message);
        }
        return;
      case 'memory':
        await showMemoryManagerDialog(context, update: update, node: node);
        return;
      case 'edit':
        _openNodeEditor(context: context, node: node, update: update);
        return;
      case 'combine':
        if (combination == null) {
          return;
        }
        final String? combinedTitle = combineConsecutiveEditNodes(
          combination.upstream.id,
          combination.downstream.id,
        );
        update();
        if (context.mounted && combinedTitle != null) {
          _showStatusSnackBar(context, 'Combined into $combinedTitle.');
        }
        return;
      case 'ungroup':
        if (nodeGroup != null) {
          ungroupNodes(nodeGroup.id);
          update();
        }
        return;
      case 'delete':
        selectedNodeId = node.id;
        selectedNodeIds
          ..clear()
          ..add(node.id);
        deleteSelected();
        update();
        return;
      case null:
        return;
    }
  }

  void _handleNodeTap(NodeModel node) {
    final bool canUseSelectionAsConnectionSource =
        selectedNodeId != null &&
        selectedNodeId != node.id &&
        selectedNodeIds.length <= 1;
    if (!canUseSelectionAsConnectionSource) {
      selectedNodeId = node.id;
      selectedNodeIds
        ..clear()
        ..add(node.id);
      selectedConnectionIndex = null;
      return;
    }

    final NodeModel? fromNode = _findNode(selectedNodeId!);
    if (fromNode == null) {
      selectedNodeId = node.id;
      selectedNodeIds
        ..clear()
        ..add(node.id);
      selectedConnectionIndex = null;
      _clearPendingConnection();
      return;
    }
    if (isNodeMutationLocked(fromNode.id) || isNodeMutationLocked(node.id)) {
      selectedNodeId = node.id;
      selectedNodeIds
        ..clear()
        ..add(node.id);
      selectedConnectionIndex = null;
      _clearPendingConnection();
      return;
    }

    final _PortConnection? portConnection = _firstMatchingPortConnection(
      fromNode,
      node,
    );
    final bool validDirection = _isValidDownstreamPlacement(fromNode, node);
    final bool introducesCycle = _collectDescendantsInclusive(
      node.id,
    ).contains(fromNode.id);

    if (portConnection == null || !validDirection || introducesCycle) {
      selectedNodeId = node.id;
      selectedNodeIds
        ..clear()
        ..add(node.id);
      selectedConnectionIndex = null;
      return;
    }

    final Map<String, dynamic> nextConnection = <String, dynamic>{
      'fromNode': fromNode.id,
      'fromPort': portConnection.fromPortIndex,
      'toNode': node.id,
      'toPort': portConnection.toPortIndex,
    };

    final bool duplicate = connections.any(
      (Map<String, dynamic> connection) =>
          connection['fromNode'] == nextConnection['fromNode'] &&
          connection['fromPort'] == nextConnection['fromPort'] &&
          connection['toNode'] == nextConnection['toNode'] &&
          connection['toPort'] == nextConnection['toPort'],
    );

    if (!duplicate) {
      _recordUndo('connect nodes');
      connections.add(nextConnection);
    }

    selectedNodeId = node.id;
    selectedNodeIds
      ..clear()
      ..add(node.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  _NodeCombinationPlan? _combinationPlanWithPrevious(NodeModel node) {
    final List<NodeModel> parents = _immediateParents(node.id);
    return parents.length == 1
        ? _buildNodeCombinationPlan(parents.single, node)
        : null;
  }

  _NodeCombinationPlan? _combinationPlanWithNext(NodeModel node) {
    final List<NodeModel> children = _immediateChildren(node.id);
    return children.length == 1
        ? _buildNodeCombinationPlan(node, children.single)
        : null;
  }

  _NodeCombinationPlan? _buildNodeCombinationPlan(
    NodeModel upstream,
    NodeModel downstream,
  ) {
    final Set<String> upstreamDatasets = _selectedDatasetIdsForCombination(
      upstream,
    );
    final Set<String> downstreamDatasets = _selectedDatasetIdsForCombination(
      downstream,
    );
    if (_immediateChildren(upstream.id).length != 1 ||
        _immediateParents(downstream.id).length != 1 ||
        upstream.params.containsKey('_runtimeGeneratedByNodeId') ||
        downstream.params.containsKey('_runtimeGeneratedByNodeId') ||
        !setEquals(upstreamDatasets, downstreamDatasets)) {
      return null;
    }

    final bool upstreamChannels = upstream.type is EditChannelsNodeType;
    final bool upstreamCombined =
        upstream.type is EditChannelsAndMarkersNodeType;
    final bool upstreamMarkers = upstream.type is AddRemoveMarkersNodeType;
    final bool downstreamMarkers = downstream.type is AddRemoveMarkersNodeType;
    if (downstreamMarkers &&
        (upstream.params['markerGenerator'] != null ||
            downstream.params['markerGenerator'] != null)) {
      return null;
    }

    if ((upstreamChannels || upstreamCombined) && downstreamMarkers) {
      final NodeType type = EditChannelsAndMarkersNodeType();
      final Map<String, dynamic> params = _deepCloneJsonMap(type.defaultParams);
      params['channelEditsByDataset'] = _deepCloneJsonMap(
        Map<String, dynamic>.from(
          upstream.params['channelEditsByDataset'] as Map? ??
              const <String, dynamic>{},
        ),
      );
      params['markers'] = _deepCloneJsonList(
        downstream.params['markers'] as List<dynamic>? ?? const <dynamic>[],
      );
      params['applyEmptyMarkerSet'] =
          downstream.params['applyEmptyMarkerSet'] == true;
      params['selectedDatasetIds'] = upstreamDatasets.toList(growable: false);
      return _NodeCombinationPlan(
        upstream: upstream,
        downstream: downstream,
        type: type,
        params: params,
      );
    }

    if (upstreamMarkers && downstreamMarkers) {
      final bool downstreamAppliesMarkers =
          downstream.params['applyEmptyMarkerSet'] == true ||
          (downstream.params['markers'] as List<dynamic>? ?? const <dynamic>[])
              .isNotEmpty;
      final NodeModel effectiveNode = downstreamAppliesMarkers
          ? downstream
          : upstream;
      final NodeType type = AddRemoveMarkersNodeType();
      final Map<String, dynamic> params = _deepCloneJsonMap(
        effectiveNode.params,
      );
      params['selectedDatasetIds'] = upstreamDatasets.toList(growable: false);
      return _NodeCombinationPlan(
        upstream: upstream,
        downstream: downstream,
        type: type,
        params: params,
      );
    }
    return null;
  }

  Set<String> _selectedDatasetIdsForCombination(NodeModel node) {
    final List<dynamic>? selected =
        node.params['selectedDatasetIds'] as List<dynamic>?;
    return selected == null
        ? datasets.values.map((Dataset dataset) => dataset.id).toSet()
        : selected.map((dynamic value) => value.toString()).toSet();
  }

  List<dynamic> _deepCloneJsonList(List<dynamic> values) {
    return jsonDecode(jsonEncode(values)) as List<dynamic>;
  }

  String? combineConsecutiveEditNodes(
    String upstreamNodeId,
    String downstreamNodeId,
  ) {
    final NodeModel? upstream = _findNode(upstreamNodeId);
    final NodeModel? downstream = _findNode(downstreamNodeId);
    if (upstream == null || downstream == null) {
      return null;
    }
    final _NodeCombinationPlan? plan = _buildNodeCombinationPlan(
      upstream,
      downstream,
    );
    if (plan == null ||
        isNodeMutationLocked(upstream.id) ||
        isNodeMutationLocked(downstream.id)) {
      return null;
    }

    _recordUndo('combine edit nodes');
    final Set<String> replacedIds = <String>{upstream.id, downstream.id};
    final List<Map<String, dynamic>> incomingConnections = connections
        .where(
          (Map<String, dynamic> connection) =>
              connection['toNode'] == upstream.id &&
              !replacedIds.contains(connection['fromNode']),
        )
        .map((Map<String, dynamic> value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final List<Map<String, dynamic>> outgoingConnections = connections
        .where(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == downstream.id &&
              !replacedIds.contains(connection['toNode']),
        )
        .map((Map<String, dynamic> value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final NodeModel replacement = _buildNode(
      type: plan.type,
      position: downstream.position,
      params: plan.params,
    );

    nodes.removeWhere((NodeModel node) => replacedIds.contains(node.id));
    connections.removeWhere(
      (Map<String, dynamic> connection) =>
          replacedIds.contains(connection['fromNode']) ||
          replacedIds.contains(connection['toNode']),
    );
    nodes.add(replacement);
    for (final Map<String, dynamic> connection in incomingConnections) {
      connection['toNode'] = replacement.id;
      connection['toPort'] = 0;
      connections.add(connection);
    }
    for (final Map<String, dynamic> connection in outgoingConnections) {
      connection['fromNode'] = replacement.id;
      if ((connection['fromPort'] as int? ?? 0) >=
          replacement.outputPorts.length) {
        connection['fromPort'] = 0;
      }
      connections.add(connection);
    }

    _nodeRamSnapshots.remove(upstream.id);
    _nodeRamSnapshots.remove(downstream.id);
    _nodeDiskSnapshotIds.remove(upstream.id);
    _nodeDiskSnapshotIds.remove(downstream.id);
    _seedNodeDatasetStates(replacement);
    for (final Dataset dataset in datasets.values) {
      _markImmediateChildrenStale(replacement.id, dataset.id);
    }
    selectedNodeId = replacement.id;
    selectedNodeIds
      ..clear()
      ..add(replacement.id);
    selectedConnectionIndex = null;
    keyboardFocusedNodeId = replacement.id;
    _clearPendingConnection();
    return replacement.title;
  }

  NodeModel? _findNode(String id) {
    for (final NodeModel node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  void _openNodeEditor({
    required BuildContext context,
    required NodeModel node,
    required VoidCallback update,
  }) {
    final Map<String, dynamic> editorParams = Map<String, dynamic>.from(
      node.params,
    );
    if (node.type is PSDNodeType) {
      editorParams['_parentSegmentOptions'] = _psdParentSegmentOptions(node);
    }
    showDialog<void>(
      context: context,
      builder: (_) => node.type.buildConfigWidget(
        editorParams,
        (params) {
          _applyNodeParams(node: node, params: params, update: update);
        },
        onSaveAndRun: (Map<String, dynamic> params) async {
          _applyNodeParams(node: node, params: params, update: update);
          String? finalDetail;
          try {
            finalDetail = await runQueued(
              label: 'Running ${node.title}',
              lockedNodeIds: _collectAncestorsInclusive(node.id),
              action: () => runThisStep(node.id),
              successDetail: () => _lastRunDatasetCount == 0
                  ? 'No datasets matched ${node.title}.'
                  : 'Ran ${node.title} for $_lastRunDatasetCount dataset(s).',
            );
            update();
            if (context.mounted) {
              _showStatusSnackBar(context, finalDetail);
            }
          } catch (error) {
            finalDetail = 'Run failed: $error';
            if (context.mounted) {
              _showStatusSnackBar(context, finalDetail);
            }
          }
        },
        datasetActions: _datasetActionsForNode(node: node, update: update),
        datasets: _datasetsById(),
        availableDatasetIds: _availableDatasetIdsForNode(node),
        datasetSourceLabels: _datasetSourceLabelsForNode(node),
        processedDatasetStates: _processedDatasetStatesForNode(node),
        portStatusSummary: _portStatusSummaryForNode(node),
        processingSteps: processingStepsForNode(node.id),
      ),
    );
  }

  void _applyNodeParams({
    required NodeModel node,
    required Map<String, dynamic> params,
    required VoidCallback update,
  }) {
    if (isNodeMutationLocked(node.id)) {
      return;
    }
    _recordUndo('edit ${node.title} parameters');
    final Map<String, dynamic> previousParams = _deepCloneJsonMap(node.params);
    final Set<String> previousAvailableDatasetIds = _availableDatasetIdsForNode(
      node,
    );
    final Map<String, dynamic> nextParams = Map<String, dynamic>.from(params);
    for (final MapEntry<String, dynamic> entry in node.params.entries) {
      if (entry.key.startsWith('_')) {
        nextParams[entry.key] = entry.value;
      }
    }
    node.params = nextParams;
    if (node.type is ImportNodeType) {
      ImportNodeType.applyDatasetAliases(node.params, datasets.values);
    }
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(node);
    for (final Dataset dataset in datasets.values) {
      final NodeParameterChangeImpact impact = node.type.parameterChangeImpact(
        previousParams,
        nextParams,
        dataset,
      );
      if (impact == NodeParameterChangeImpact.metadataOnly) {
        node.type.applyMetadataOnlyParams(previousParams, nextParams, dataset);
        _propagateDatasetMetadata(dataset);
      }

      if (!availableDatasetIds.contains(dataset.id)) {
        node.datasetStates[dataset.id] = DatasetState.notReady;
        continue;
      }
      final DatasetState currentState =
          node.datasetStates[dataset.id] ?? DatasetState.notReady;
      if (!previousAvailableDatasetIds.contains(dataset.id) ||
          currentState == DatasetState.notReady) {
        node.datasetStates[dataset.id] = DatasetState.ready;
        continue;
      }
      if (impact == NodeParameterChangeImpact.computation) {
        node.datasetStates[dataset.id] = DatasetState.stale;
        _markImmediateChildrenStale(node.id, dataset.id);
      }
    }
    update();
  }

  void _propagateDatasetMetadata(Dataset dataset) {
    for (final Map<String, DatasetArtifactSnapshot> snapshots
        in _nodeRamSnapshots.values) {
      final DatasetArtifactSnapshot? snapshot = snapshots[dataset.id];
      if (snapshot != null) {
        snapshots[dataset.id] = snapshot.withDatasetLabel(dataset.label);
      }
    }
    if (!supportsNodeSnapshotDiskStore) {
      return;
    }
    final String metadataJson = jsonEncode(<String, dynamic>{
      'datasetLabel': dataset.label,
    });
    for (final MapEntry<String, Set<String>> entry
        in _nodeDiskSnapshotIds.entries) {
      if (!entry.value.contains(dataset.id)) {
        continue;
      }
      try {
        saveNodeSnapshotMetadataJsonSync(
          nodeId: entry.key,
          datasetId: dataset.id,
          jsonPayload: metadataJson,
        );
      } catch (_) {
        // The in-memory rename remains valid if a cache sidecar is unavailable.
      }
    }
  }

  @visibleForTesting
  void applyNodeParamsForTest(NodeModel node, Map<String, dynamic> params) {
    _applyNodeParams(node: node, params: params, update: () {});
  }

  @visibleForTesting
  Future<String> releaseNodeActiveMemoryForTest(
    NodeModel node,
    Set<String> datasetIds,
  ) {
    return _releaseNodeSnapshotsFromRam(
      node: node,
      datasetIds: datasetIds,
      update: () {},
    );
  }

  Set<String> _expandPsdRuntimePipeline(NodeModel psdNode) {
    final Set<String> forcedDependencyIds = _psdUsesParentSegments(psdNode)
        ? const <String>{}
        : _ensurePsdSegmentationParent(psdNode);
    _ensurePsdAverageChild(psdNode);
    psdNode.params['deferAverageToDownstream'] =
        (psdNode.params['outputMode'] ?? 'averaged').toString() == 'averaged';
    return forcedDependencyIds;
  }

  Set<String> _ensurePsdSegmentationParent(NodeModel psdNode) {
    final double windowWidthMs = _psdWindowWidthMs(psdNode);
    final double windowOverlapPercent = _psdWindowOverlapPercent(psdNode);
    final List<NodeModel> parents = _immediateParents(psdNode.id);
    final List<NodeModel> segmentationParents = parents
        .where(
          (NodeModel parent) =>
              parent.type is SegmentationNodeType &&
              _isRuntimeDependencyFor(parent, psdNode.id),
        )
        .toList(growable: false);
    if (segmentationParents.isNotEmpty) {
      final Set<String> changedParentIds = <String>{};
      for (final NodeModel segmentationParent in segmentationParents) {
        final String windowMarkerName = _equalWindowMarkerName(
          segmentationParent,
        );
        bool changed = false;
        changed =
            _setParamIfChanged(segmentationParent, 'mode', 'equal_windows') ||
            changed;
        changed =
            _setParamIfChanged(
              segmentationParent,
              'equalWindowWidthMs',
              windowWidthMs,
            ) ||
            changed;
        changed =
            _setParamIfChanged(
              segmentationParent,
              'equalWindowOverlapPercent',
              windowOverlapPercent,
            ) ||
            changed;
        final Map<String, dynamic> includedMarkers = <String, dynamic>{
          markerKeyForKindAndLabel(
            kind: MarkerType.window,
            label: windowMarkerName,
          ): true,
        };
        changed =
            _setParamIfChanged(
              segmentationParent,
              'includedMarkers',
              includedMarkers,
            ) ||
            changed;
        if (changed) {
          _markRuntimeDependencyStale(segmentationParent);
          if (_isRuntimeDependencyFor(segmentationParent, psdNode.id)) {
            changedParentIds.add(segmentationParent.id);
          }
        } else if (_isRuntimeDependencyFor(segmentationParent, psdNode.id) &&
            _nodeHasPendingRuntimeDatasets(segmentationParent)) {
          changedParentIds.add(segmentationParent.id);
        }
      }
      return changedParentIds;
    }
    final List<NodeModel> sourceParents = _psdSignalParents(psdNode);
    if (sourceParents.isEmpty) {
      return const <String>{};
    }

    final NodeModel anchorParent = sourceParents.first;
    final NodeModel segmentationNode = _buildNode(
      type: SegmentationNodeType(),
      position: _nearestAvailablePosition(
        Offset(
          (anchorParent.position.dx + psdNode.position.dx) / 2,
          (anchorParent.position.dy + psdNode.position.dy) / 2,
        ),
      ),
      params: <String, dynamic>{
        ...SegmentationNodeType().defaultParams,
        'mode': 'equal_windows',
        'windowMarkerName': 'FFT Window',
        'includedMarkers': <String, dynamic>{
          markerKeyForKindAndLabel(
            kind: MarkerType.window,
            label: 'FFT Window',
          ): true,
        },
        'equalWindowWidthMs': windowWidthMs,
        'equalWindowOverlapPercent': windowOverlapPercent,
        '_runtimeGeneratedByNodeId': psdNode.id,
        if (psdNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            psdNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(segmentationNode);

    connections.removeWhere((Map<String, dynamic> connection) {
      return connection['toNode'] == psdNode.id &&
          parents.any(
            (NodeModel parent) => parent.id == connection['fromNode'],
          );
    });
    for (final NodeModel parent in sourceParents) {
      _addAllMatchingConnections(parent, segmentationNode);
    }
    _addAllMatchingConnections(segmentationNode, psdNode);
    _seedNodeDatasetStates(segmentationNode);
    return <String>{segmentationNode.id};
  }

  bool _setParamIfChanged(NodeModel node, String key, Object? value) {
    if (node.params[key].toString() == value.toString()) {
      return false;
    }
    node.params[key] = value;
    return true;
  }

  double _psdWindowWidthMs(NodeModel psdNode) {
    final double lengthSeconds =
        (psdNode.params['windowLengthSec'] as num?)?.toDouble() ?? 1.0;
    return (lengthSeconds * 1000.0).clamp(1.0, double.infinity).toDouble();
  }

  double _psdWindowOverlapPercent(NodeModel psdNode) {
    return ((psdNode.params['windowOverlapPercent'] as num?)?.toDouble() ?? 0.0)
        .clamp(0.0, 95.0)
        .toDouble();
  }

  bool _ensurePsdAverageChild(NodeModel psdNode) {
    final String outputMode = (psdNode.params['outputMode'] ?? 'averaged')
        .toString();
    if (outputMode != 'averaged') {
      return false;
    }
    final List<NodeModel> children = _immediateChildren(psdNode.id);
    if (children.any((NodeModel child) => child.type is PSDAverageNodeType)) {
      return false;
    }

    final NodeModel averageNode = _buildNode(
      type: PSDAverageNodeType(),
      position: _nearestAvailablePosition(
        Offset(
          psdNode.position.dx,
          psdNode.position.dy + _cardHeight + _spawnGap,
        ),
      ),
      params: <String, dynamic>{
        ...PSDAverageNodeType().defaultParams,
        '_runtimeGeneratedByNodeId': psdNode.id,
        if (psdNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            psdNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(averageNode);

    final List<Map<String, dynamic>> downstreamConnections = connections
        .where(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == psdNode.id,
        )
        .map((Map<String, dynamic> connection) {
          return Map<String, dynamic>.from(connection);
        })
        .toList(growable: false);
    connections.removeWhere(
      (Map<String, dynamic> connection) => connection['fromNode'] == psdNode.id,
    );
    _addAllMatchingConnections(psdNode, averageNode);
    for (final Map<String, dynamic> connection in downstreamConnections) {
      final NodeModel? downstream = _findNode(
        connection['toNode']?.toString() ?? '',
      );
      if (downstream == null || downstream.id == averageNode.id) {
        continue;
      }
      final _PortConnection? portConnection = _firstMatchingPortConnection(
        averageNode,
        downstream,
      );
      if (portConnection == null) {
        continue;
      }
      connections.add(<String, dynamic>{
        'fromNode': averageNode.id,
        'fromPort': portConnection.fromPortIndex,
        'toNode': downstream.id,
        'toPort': portConnection.toPortIndex,
      });
    }
    _seedNodeDatasetStates(averageNode);
    return true;
  }

  Set<String> _ensureEqualWindowMarkerParent(NodeModel segmentationNode) {
    if (segmentationNode.type is! SegmentationNodeType ||
        (segmentationNode.params['mode'] ?? 'events').toString() !=
            'equal_windows') {
      return const <String>{};
    }
    final String windowMarkerName = _equalWindowMarkerName(segmentationNode);
    final List<NodeModel> parents = _immediateParents(segmentationNode.id);
    NodeModel? existingGenerator;
    for (final NodeModel parent in parents) {
      if (parent.type is AddRemoveMarkersNodeType &&
          parent.params['generatedMarkerLabel'] == windowMarkerName) {
        existingGenerator = parent;
        break;
      }
    }
    if (existingGenerator != null) {
      bool changed = false;
      changed =
          _setParamIfChanged(
            existingGenerator,
            'markerGenerator',
            'fft_windows',
          ) ||
          changed;
      changed =
          _setParamIfChanged(
            existingGenerator,
            'generatedMarkerLabel',
            windowMarkerName,
          ) ||
          changed;
      changed =
          _setParamIfChanged(
            existingGenerator,
            'windowWidthMs',
            (segmentationNode.params['equalWindowWidthMs'] as num?)
                    ?.toDouble() ??
                1000.0,
          ) ||
          changed;
      changed =
          _setParamIfChanged(
            existingGenerator,
            'windowOverlapPercent',
            (segmentationNode.params['equalWindowOverlapPercent'] as num?)
                    ?.toDouble() ??
                0.0,
          ) ||
          changed;
      changed =
          _setParamIfChanged(
            existingGenerator,
            'markerDurationMode',
            'window',
          ) ||
          changed;
      if (segmentationNode.params['selectedDatasetIds'] != null) {
        changed =
            _setParamIfChanged(existingGenerator, 'selectedDatasetIds', <
              dynamic
            >[
              ...List<dynamic>.from(
                segmentationNode.params['selectedDatasetIds'] as List<dynamic>,
              ),
            ]) ||
            changed;
      }
      if (changed) {
        _markRuntimeDependencyStale(existingGenerator);
        if (_isRuntimeDependencyFor(existingGenerator, segmentationNode.id)) {
          return <String>{existingGenerator.id};
        }
      }
      if (_isRuntimeDependencyFor(existingGenerator, segmentationNode.id) &&
          _nodeHasPendingRuntimeDatasets(existingGenerator)) {
        return <String>{existingGenerator.id};
      }
      return const <String>{};
    }
    if (parents.isEmpty) {
      return const <String>{};
    }

    final NodeModel anchorParent = parents.first;
    final NodeModel markerNode = _buildNode(
      type: AddRemoveMarkersNodeType(),
      position: _nearestAvailablePosition(
        Offset(
          (anchorParent.position.dx + segmentationNode.position.dx) / 2,
          (anchorParent.position.dy + segmentationNode.position.dy) / 2,
        ),
      ),
      params: <String, dynamic>{
        ...AddRemoveMarkersNodeType().defaultParams,
        'markerGenerator': 'fft_windows',
        'generatedMarkerLabel': windowMarkerName,
        'windowWidthMs':
            (segmentationNode.params['equalWindowWidthMs'] as num?)
                ?.toDouble() ??
            1000.0,
        'windowOverlapPercent':
            (segmentationNode.params['equalWindowOverlapPercent'] as num?)
                ?.toDouble() ??
            0.0,
        'markerDurationMode': 'window',
        '_runtimeGeneratedByNodeId': segmentationNode.id,
        if (segmentationNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            segmentationNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(markerNode);

    connections.removeWhere((Map<String, dynamic> connection) {
      return connection['toNode'] == segmentationNode.id &&
          parents.any(
            (NodeModel parent) => parent.id == connection['fromNode'],
          );
    });
    for (final NodeModel parent in parents) {
      _addAllMatchingConnections(parent, markerNode);
    }
    _addAllMatchingConnections(markerNode, segmentationNode);
    _seedNodeDatasetStates(markerNode);
    return <String>{markerNode.id};
  }

  void _markRuntimeDependencyStale(NodeModel node) {
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(node);
    for (final Dataset dataset in datasets.values) {
      node.datasetStates[dataset.id] = availableDatasetIds.contains(dataset.id)
          ? DatasetState.stale
          : DatasetState.notReady;
    }
  }

  bool _nodeHasPendingRuntimeDatasets(NodeModel node) {
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(node);
    for (final String datasetId in availableDatasetIds) {
      final DatasetState state =
          node.datasetStates[datasetId] ?? DatasetState.notReady;
      if (state != DatasetState.done && state != DatasetState.notReady) {
        return true;
      }
    }
    return false;
  }

  bool _isRuntimeDependencyFor(NodeModel node, String ownerNodeId) {
    return node.params['_runtimeGeneratedByNodeId'] == ownerNodeId;
  }

  bool _psdUsesParentSegments(NodeModel node) {
    return node.type is PSDNodeType && node.params['useParentSegments'] == true;
  }

  List<NodeModel> _psdSignalParents(NodeModel psdNode) {
    final int signalInputIndex = psdNode.inputPorts.indexWhere(
      (PortSpec port) => port.name == 'signal',
    );
    if (signalInputIndex < 0) {
      return const <NodeModel>[];
    }
    return connections
        .where(
          (Map<String, dynamic> connection) =>
              connection['toNode'] == psdNode.id &&
              (connection['toPort'] as int? ?? -1) == signalInputIndex,
        )
        .where((Map<String, dynamic> connection) {
          final NodeModel? fromNode = _findNode(
            connection['fromNode'] as String? ?? '',
          );
          final int fromPortIndex =
              (connection['fromPort'] as num?)?.toInt() ?? 0;
          return fromNode != null &&
              fromPortIndex >= 0 &&
              fromPortIndex < fromNode.outputPorts.length &&
              fromNode.outputPorts[fromPortIndex].type == PortType.signal;
        })
        .map((Map<String, dynamic> connection) {
          return _findNode(connection['fromNode'] as String? ?? '');
        })
        .whereType<NodeModel>()
        .toList(growable: false);
  }

  List<NodeModel> _psdSegmentParents(NodeModel psdNode) {
    final int segmentsInputIndex = psdNode.inputPorts.indexWhere(
      (PortSpec port) => port.name == 'segments',
    );
    if (segmentsInputIndex < 0) {
      return const <NodeModel>[];
    }
    return connections
        .where(
          (Map<String, dynamic> connection) =>
              connection['toNode'] == psdNode.id &&
              (connection['toPort'] as int? ?? -1) == segmentsInputIndex,
        )
        .map((Map<String, dynamic> connection) {
          return _findNode(connection['fromNode'] as String? ?? '');
        })
        .whereType<NodeModel>()
        .where((NodeModel node) => node.type is SegmentationNodeType)
        .toList(growable: false);
  }

  List<NodeModel> _dependencyParentsForNode(NodeModel node) {
    if (!_psdUsesParentSegments(node)) {
      return _immediateParents(node.id);
    }
    final List<NodeModel> parents = <NodeModel>[..._psdSignalParents(node)];
    final String? selectedSegmentParentId = _selectedPsdSegmentParentId(node);
    if (selectedSegmentParentId == null) {
      return parents;
    }
    final NodeModel? selectedParent = _findNode(selectedSegmentParentId);
    if (selectedParent != null && !parents.contains(selectedParent)) {
      parents.add(selectedParent);
    }
    return parents;
  }

  List<Map<String, dynamic>> _psdParentSegmentOptions(NodeModel psdNode) {
    final List<Map<String, dynamic>> options = <Map<String, dynamic>>[];
    for (final NodeModel parent in _psdSegmentParents(psdNode)) {
      final int? segmentCount = _segmentCountForNode(parent);
      if (segmentCount == null || segmentCount <= 0) {
        continue;
      }
      options.add(<String, dynamic>{
        'id': parent.id,
        'label': '${_nodeDescriptor(parent)} ($segmentCount segments)',
        'segmentCount': segmentCount,
      });
    }
    return options;
  }

  int? _segmentCountForNode(NodeModel node) {
    final DatasetArtifactSnapshot? snapshot = _primarySnapshotForNode(node);
    final int? snapshotCount = snapshot?.segmentedTimeSeries?.segmentCount;
    if (snapshotCount != null) {
      return snapshotCount;
    }
    for (final Dataset dataset in datasets.values) {
      if (dataset.segmentedTimeSeries != null &&
          dataset
                  .artifactIdentityFor(
                    BrainStoryArtifactKind.segmentedTimeSeries,
                  )
                  ?.producerNodeId ==
              node.id) {
        return dataset.segmentedTimeSeries!.segmentCount;
      }
    }
    return null;
  }

  String? _selectedPsdSegmentParentId(NodeModel psdNode) {
    final List<NodeModel> parents = _psdSegmentParents(psdNode);
    if (parents.isEmpty) {
      return null;
    }
    final String selectedId =
        psdNode.params['parentSegmentsNodeId']?.toString().trim() ?? '';
    if (selectedId.isNotEmpty &&
        parents.any((NodeModel parent) => parent.id == selectedId)) {
      return selectedId;
    }
    return parents.first.id;
  }

  String _equalWindowMarkerName(NodeModel segmentationNode) {
    final String name =
        segmentationNode.params['windowMarkerName']?.toString().trim() ?? '';
    return name.isEmpty ? 'FFT Window' : name;
  }

  void _addAllMatchingConnections(NodeModel fromNode, NodeModel toNode) {
    final List<_EffectiveOutputPort> effectivePorts = _effectiveOutputPorts(
      fromNode,
    );
    final Set<int> filledInputs = connections
        .where(
          (Map<String, dynamic> connection) =>
              connection['fromNode'] == fromNode.id &&
              connection['toNode'] == toNode.id,
        )
        .map((Map<String, dynamic> connection) => connection['toPort'])
        .whereType<int>()
        .toSet();
    for (final _EffectiveOutputPort outputPort in effectivePorts) {
      for (
        int toPortIndex = 0;
        toPortIndex < toNode.inputPorts.length;
        toPortIndex++
      ) {
        if (filledInputs.contains(toPortIndex)) {
          continue;
        }
        if (toNode.inputPorts[toPortIndex].type != outputPort.port.type) {
          continue;
        }
        connections.add(<String, dynamic>{
          'fromNode': fromNode.id,
          'fromPort': outputPort.portIndex,
          'toNode': toNode.id,
          'toPort': toPortIndex,
        });
        filledInputs.add(toPortIndex);
        break;
      }
    }
  }

  NodeModel? get selectedNode =>
      selectedNodeId == null ? null : _findNode(selectedNodeId!);

  NodeModel? get selectedVisualizationNode {
    final NodeModel? node = selectedNode;
    if (node == null || node.type is! VisualizationNodeType) {
      return null;
    }
    return node;
  }

  NodeModel? get selectedVisualizationTarget => selectedNode;

  List<Dataset> get datasetsForSelectedVisualizationNode {
    final NodeModel? node = selectedVisualizationNode;
    if (node == null) {
      return <Dataset>[];
    }

    return sourceDatasetsForVisualizationNode(node.id);
  }

  Future<List<Dataset>> datasetsForVisualizationNode(String nodeId) async {
    return materializedDatasetViewsForSourceRefs(
      visualizationSourceRefsForNode(nodeId),
    );
  }

  List<Dataset> sourceDatasetsForVisualizationNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return <Dataset>[];
    }

    final Set<String> datasetIds = _datasetsForNode(node);
    final List<Dataset> matchingDatasets = datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList(growable: false);
    matchingDatasets.sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    return matchingDatasets;
  }

  List<VisualizationSourceRef> visualizationSourceRefsForNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return const <VisualizationSourceRef>[];
    }

    final List<VisualizationSourceRef> refs = <VisualizationSourceRef>[];
    if (node.type is ImpedancesNodeType) {
      final Set<String> datasetIds = _datasetsForNode(node);
      final List<Dataset> matchingDatasets =
          datasets.values
              .where((Dataset dataset) => datasetIds.contains(dataset.id))
              .toList(growable: false)
            ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
      for (final Dataset dataset in matchingDatasets) {
        refs.add(
          VisualizationSourceRef(
            key: '${node.id}|${dataset.id}',
            datasetId: dataset.id,
            datasetLabel: dataset.label,
            materializeFromNodeId: node.id,
            sourceDescriptor: _nodeDescriptor(node),
          ),
        );
      }
      return refs;
    }
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents =
          _immediateParents(node.id)
              .where((NodeModel parent) => parent.outputPorts.isNotEmpty)
              .toList(growable: false)
            ..sort(
              (NodeModel a, NodeModel b) =>
                  _nodeDescriptor(a).compareTo(_nodeDescriptor(b)),
            );
      for (final NodeModel parent in parents) {
        final Set<String> datasetIds = _datasetsForNode(parent);
        final List<Dataset> matchingDatasets =
            datasets.values
                .where((Dataset dataset) => datasetIds.contains(dataset.id))
                .toList(growable: false)
              ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
        for (final Dataset dataset in matchingDatasets) {
          refs.add(
            VisualizationSourceRef(
              key: '${parent.id}|${dataset.id}',
              datasetId: dataset.id,
              datasetLabel: dataset.label,
              materializeFromNodeId: parent.id,
              sourceDescriptor: _nodeDescriptor(parent),
            ),
          );
        }
      }
      return refs;
    }

    final Set<String> datasetIds = _datasetsForNode(node);
    final List<Dataset> matchingDatasets =
        datasets.values
            .where((Dataset dataset) => datasetIds.contains(dataset.id))
            .toList(growable: false)
          ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    for (final Dataset dataset in matchingDatasets) {
      refs.add(
        VisualizationSourceRef(
          key: '${node.id}|${dataset.id}',
          datasetId: dataset.id,
          datasetLabel: dataset.label,
          materializeFromNodeId: node.id,
          sourceDescriptor: _nodeDescriptor(node),
        ),
      );
    }
    return refs;
  }

  Future<List<Dataset>> materializedDatasetViewsForNode(
    String nodeId,
    List<Dataset> sources,
  ) async {
    return _withVisualizerPriority(() async {
      final List<Dataset> views = <Dataset>[];
      for (final Dataset source in sources) {
        views.add(await materializedDatasetViewForNode(nodeId, source));
      }
      return views;
    });
  }

  Future<List<Dataset>> materializedDatasetViewsForSourceRefs(
    List<VisualizationSourceRef> sources,
  ) async {
    return _withVisualizerPriority(() async {
      final List<Dataset> views = <Dataset>[];
      for (final VisualizationSourceRef source in sources) {
        views.add(await materializedDatasetViewForSourceRef(source));
      }
      return views;
    });
  }

  Future<Dataset> materializedDatasetViewForSourceRef(
    VisualizationSourceRef source,
  ) async {
    final Dataset? dataset = _datasetsById()[source.datasetId];
    if (dataset == null) {
      return Dataset(source.datasetId, label: source.displayLabel);
    }
    final Dataset view = await materializedDatasetViewForNode(
      source.materializeFromNodeId,
      dataset,
    );
    view.label = source.displayLabel;
    view.ram['viewer.sourceKey'] = source.key;
    view.ram['viewer.sourceDescriptor'] = source.sourceDescriptor;
    view.ram['viewer.baseDatasetLabel'] = source.datasetLabel;
    return view;
  }

  Future<Dataset> materializedDatasetViewForNode(
    String nodeId,
    Dataset source,
  ) async {
    final Dataset view = _datasetShell(source);
    final Set<String> ancestorIds = _collectAncestorsInclusive(nodeId);
    final List<NodeModel> orderedAncestors = _orderedNodes(ancestorIds);
    bool appliedAnySnapshot = false;

    for (final NodeModel ancestor in orderedAncestors) {
      if (ancestor.datasetStates[source.id] != DatasetState.done) {
        continue;
      }
      final DatasetArtifactSnapshot? snapshot =
          await _loadSnapshotForNodeDataset(ancestor.id, source.id);
      if (snapshot != null && !snapshot.isEmpty) {
        _snapshotScopedToNodeOutputs(ancestor, snapshot).applyToDataset(view);
        appliedAnySnapshot = true;
        continue;
      }
      if (ancestor.type is ImportNodeType && !appliedAnySnapshot) {
        _applyLiveSourceArtifacts(view, source);
      }
    }

    if (!appliedAnySnapshot && view.timeSeries == null) {
      _applyLiveSourceArtifacts(view, source);
    }
    return view;
  }

  Dataset _datasetShell(Dataset source) {
    final Dataset shell = Dataset(source.id, label: source.label);
    shell.loaded = source.loaded;
    return shell;
  }

  void _applyLiveSourceArtifacts(Dataset target, Dataset source) {
    target.timeSeries = source.timeSeries == null
        ? null
        : TimeSeriesData.fromJson(source.timeSeries!.toJson());
    final Map<BrainStoryArtifactKind, ArtifactIdentity> sourceIdentities =
        source.artifactIdentities;
    target.artifactIdentities =
        Map<BrainStoryArtifactKind, ArtifactIdentity>.fromEntries(
          sourceIdentities.entries.where(
            (MapEntry<BrainStoryArtifactKind, ArtifactIdentity> entry) =>
                entry.key == BrainStoryArtifactKind.timeSeries ||
                entry.key == BrainStoryArtifactKind.markers,
          ),
        );
  }

  bool isVisualizationNode(NodeModel? node) =>
      node?.type is VisualizationNodeType;

  bool isMarkerEditNode(NodeModel? node) =>
      node?.type is AddRemoveMarkersNodeType ||
      node?.type is EditChannelsAndMarkersNodeType;

  bool canVisualizeNode(NodeModel? node) {
    return node != null;
  }

  bool hasVisualizationOutput(NodeModel? node) {
    if (!canVisualizeNode(node)) {
      return false;
    }
    if (node!.type is VisualizationNodeType) {
      return _immediateParents(
        node.id,
      ).any((NodeModel parent) => hasVisualizationOutput(parent));
    }
    return node.datasetStates.values.any(
      (DatasetState state) => state == DatasetState.done,
    );
  }

  String visualizationViewForNode(NodeModel node) {
    return _fallbackVisualizationViewForNode(node);
  }

  String visualizationViewForNodeAndDatasets(
    NodeModel node,
    List<Dataset> datasets,
  ) {
    if (node.type is ImpedancesNodeType) {
      return 'impedances';
    }
    for (final Dataset dataset in datasets) {
      if (dataset.bridgeDetection != null) {
        return 'bridge';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.timeFrequency != null) {
        return 'time_frequency';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.spectrum != null) {
        return 'psd';
      }
    }
    for (final Dataset dataset in datasets) {
      final TimeSeriesData? timeSeries = dataset.timeSeries;
      if (timeSeries != null &&
          timeSeries.markers.any(
            (TimeMarker marker) => isSleepStageMarker(marker),
          )) {
        return 'hypnogram';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.segmentedTimeSeries != null) {
        return 'segments';
      }
    }
    for (final Dataset dataset in datasets) {
      if (dataset.timeSeries != null || dataset.segmentedTimeSeries != null) {
        return 'raw';
      }
    }
    return _fallbackVisualizationViewForNode(node);
  }

  String _fallbackVisualizationViewForNode(NodeModel node) {
    if (node.type is ImpedancesNodeType) {
      return 'impedances';
    }
    if (node.type is SleepStagingNodeType) {
      return 'hypnogram';
    }
    if (node.type is BridgeDetectorNodeType) {
      return 'bridge';
    }
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id);
      if (parents.any(
        (NodeModel parent) => parent.type is SleepStagingNodeType,
      )) {
        return 'hypnogram';
      }
      if (parents.any(
        (NodeModel parent) => parent.type is BridgeDetectorNodeType,
      )) {
        return 'bridge';
      }
      if (parents.any((NodeModel parent) => parent.type is PSDNodeType)) {
        return 'psd';
      }
      if (parents.any(
        (NodeModel parent) =>
            parent.type is SegmentationNodeType ||
            parent.type is RealignNodeType,
      )) {
        return 'segments';
      }
      if (parents.any(
        (NodeModel parent) => parent.type.title.contains('Time-Frequency'),
      )) {
        return 'time_frequency';
      }
      return 'raw';
    }
    if (node.type is SegmentationNodeType || node.type is RealignNodeType) {
      return 'segments';
    }
    return node.type is PSDNodeType ? 'psd' : 'raw';
  }

  List<String> processingStepsForNode(String nodeId) {
    final Set<String> ancestorIds = _collectAncestorsInclusive(nodeId);
    final List<NodeModel> orderedNodes = _orderedNodes(ancestorIds);
    return orderedNodes
        .map((NodeModel node) => _nodeDescriptor(node))
        .toList(growable: false);
  }

  String visualizationDisplayMode(NodeModel? node) {
    if (node == null || node.type is! VisualizationNodeType) {
      return 'panel';
    }
    return (node.params['display_mode'] ?? 'panel').toString();
  }

  int _lastRunDatasetCount = 0;
  int _lastSkippedNodeCount = 0;

  Future<String> runQueued({
    required String label,
    required Future<void> Function() action,
    required String Function() successDetail,
    Set<String> lockedNodeIds = const <String>{},
  }) {
    final _QueuedRunTask task = _QueuedRunTask(
      id: ++_runQueueTaskCounter,
      label: label,
      lockedNodeIds: Set<String>.from(lockedNodeIds),
      action: action,
      successDetail: successDetail,
    );
    _queuedRunTasks.add(task);
    _publishQueuedRunJobs();
    _runQueueTail = _runQueueTail.then<void>(
      (_) => _executeQueuedRunTask(task),
      onError: (Object _, StackTrace __) => _executeQueuedRunTask(task),
    );
    return task.completer.future;
  }

  Future<void> _executeQueuedRunTask(_QueuedRunTask task) async {
    await _waitForVisualizerPriorityBeforeRun();
    _queuedRunTasks.removeWhere((_QueuedRunTask item) => item.id == task.id);
    _publishQueuedRunJobs();
    bool succeeded = false;
    String? finalDetail;
    try {
      await prepareRunUi(task.label, lockedNodeIds: task.lockedNodeIds);
      await _waitForVisualizerPriorityDuringRun();
      await task.action();
      await setRunDetail(
        'Committing run results...',
        phase: RunActivityPhase.finalizing,
      );
      succeeded = true;
      finalDetail = _decorateRunDetailWithSkips(task.successDetail());
      if (!task.completer.isCompleted) {
        task.completer.complete(finalDetail);
      }
    } catch (error, stackTrace) {
      finalDetail = 'Run failed: $error';
      if (!task.completer.isCompleted) {
        task.completer.completeError(error, stackTrace);
      }
    } finally {
      finishRunUi(succeeded: succeeded, detail: finalDetail);
    }
  }

  void _publishQueuedRunJobs() {
    queuedRunJobs.value = _queuedRunTasks
        .map(
          (_QueuedRunTask task) => RunJobEntry(
            label: task.label,
            detail: visualizerPriorityActive.value
                ? 'Paused while a visualizer is using priority resources.'
                : 'Waiting for the current job to finish.',
            state: RunJobState.queued,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _waitForVisualizerPriorityBeforeRun() async {
    while (visualizerPriorityActive.value) {
      _publishQueuedRunJobs();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _waitForVisualizerPriorityDuringRun() async {
    while (visualizerPriorityActive.value) {
      await setRunDetail(
        'Visualizer is active; processing is paused...',
        phase: RunActivityPhase.running,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _executionChunkBoundary() async {
    await _waitForVisualizerPriorityDuringRun();
    final ProcessingResponsiveness policy = processingResponsiveness.value;
    if (!_executionChunkStopwatch.isRunning) {
      _executionChunkStopwatch.start();
    }
    if (!policy.chunkingEnabled ||
        _executionChunkStopwatch.elapsed < policy.workBudget) {
      await Future<void>.delayed(Duration.zero);
      return;
    }
    _executionChunkStopwatch
      ..reset()
      ..stop();
    await WidgetsBinding.instance.endOfFrame;
    if (policy.yieldBudget > Duration.zero) {
      await Future<void>.delayed(policy.yieldBudget);
    }
    _executionChunkStopwatch.start();
  }

  Future<T> _withVisualizerPriority<T>(Future<T> Function() action) async {
    _visualizerPriorityCount++;
    visualizerPriorityActive.value = true;
    _publishQueuedRunJobs();
    try {
      return await action();
    } finally {
      _visualizerPriorityCount = _visualizerPriorityCount <= 1
          ? 0
          : _visualizerPriorityCount - 1;
      visualizerPriorityActive.value = _visualizerPriorityCount > 0;
      _publishQueuedRunJobs();
    }
  }

  Future<void> prepareRunUi(
    String label, {
    Set<String> lockedNodeIds = const <String>{},
  }) async {
    _lastSkippedNodeCount = 0;
    _runStartedAt = DateTime.now();
    _executionChunkStopwatch
      ..reset()
      ..start();
    _runLockedNodeIds
      ..clear()
      ..addAll(lockedNodeIds);
    runActivity.value = RunActivity(
      label: label,
      detail: 'Preparing run state...',
      phase: RunActivityPhase.initializing,
    );
    await _yieldToUi();
    await setRunDetail('Settling the interface...');
    await _yieldToUi();
    await setRunDetail('Preparing data flow...');
    await _yieldToUi(extraDelayMs: 24);
  }

  String _decorateRunDetailWithSkips(String detail) {
    if (_lastSkippedNodeCount <= 0) {
      return detail;
    }
    final String noun = _lastSkippedNodeCount == 1
        ? 'node result'
        : 'node results';
    return '$detail Reused $_lastSkippedNodeCount completed $noun.';
  }

  void finishRunUi({bool succeeded = true, String? detail}) {
    final RunActivity? current = runActivity.value;
    if (current != null) {
      final Duration elapsed = _runStartedAt == null
          ? Duration.zero
          : DateTime.now().difference(_runStartedAt!);
      final List<RunJobEntry> nextJobs = <RunJobEntry>[
        RunJobEntry(
          label: current.label,
          detail: (detail ?? current.detail).trim(),
          state: succeeded ? RunJobState.done : RunJobState.failed,
          finishedAt: DateTime.now(),
          elapsed: elapsed,
        ),
        ...recentRunJobs.value,
      ];
      recentRunJobs.value = nextJobs.take(6).toList(growable: false);
    }
    _runWaitingNodeIds.clear();
    _runLockedNodeIds.clear();
    _runActiveNodeId = null;
    _runStartedAt = null;
    _executionChunkStopwatch
      ..reset()
      ..stop();
    runActivity.value = null;
  }

  Future<void> setRunDetail(String detail, {RunActivityPhase? phase}) async {
    final RunActivity? current = runActivity.value;
    if (current == null) {
      return;
    }
    runActivity.value = current.copyWith(detail: detail, phase: phase);
    await _yieldToUi();
  }

  Future<void> setRunDetailQuiet(
    String detail, {
    RunActivityPhase? phase,
  }) async {
    final RunActivity? current = runActivity.value;
    if (current == null) {
      return;
    }
    runActivity.value = current.copyWith(detail: detail, phase: phase);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> runThisStep(String nodeId, {Set<String>? datasetIds}) async {
    final Set<String> expandedNodeIds = <String>{nodeId};
    _expandRuntimeDependencies(expandedNodeIds, includeAncestors: false);
    _assertCanRunNodeSet(expandedNodeIds, datasetIds: datasetIds);
    await _runNodeSet(expandedNodeIds, datasetIds: datasetIds);
  }

  void _assertCanRunNodeSet(Set<String> nodeIds, {Set<String>? datasetIds}) {
    final List<NodeModel> orderedNodes = _orderedNodes(nodeIds);
    final Set<String> targetDatasetIds = <String>{};
    for (final NodeModel node in orderedNodes) {
      targetDatasetIds.addAll(_datasetsForNode(node));
    }
    if (datasetIds != null) {
      targetDatasetIds.retainAll(datasetIds);
    }
    for (final String datasetId in targetDatasetIds) {
      final Dataset? dataset = _datasetById(datasetId);
      final String datasetLabel = dataset?.label ?? datasetId;
      for (final NodeModel node in orderedNodes) {
        if (node.type is ImportNodeType ||
            !_datasetsForNode(node).contains(datasetId)) {
          continue;
        }
        for (final NodeModel parent in _dependencyParentsForNode(node)) {
          if (nodeIds.contains(parent.id)) {
            continue;
          }
          final DatasetState state =
              parent.datasetStates[datasetId] ?? DatasetState.notReady;
          if (state != DatasetState.done) {
            throw StateError(
              'Cannot run ${node.title} for $datasetLabel because upstream node '
              '${parent.title} is ${_datasetStateLabel(state)}. Use Run From Start '
              'to recompute upstream dependencies.',
            );
          }
        }
      }
    }
  }

  Future<void> runFromStart(String nodeId, {Set<String>? datasetIds}) async {
    await _runNodeSet(
      _collectAncestorsInclusive(nodeId),
      datasetIds: datasetIds,
      includeAncestors: true,
    );
  }

  Future<void> _runNodeSet(
    Set<String> nodeIds, {
    Set<String>? datasetIds,
    bool includeAncestors = false,
  }) async {
    final Set<String> expandedNodeIds = Set<String>.from(nodeIds);
    _expandRuntimeDependencies(
      expandedNodeIds,
      includeAncestors: includeAncestors,
    );

    final List<NodeModel> orderedNodes = _orderedNodes(expandedNodeIds);
    if (orderedNodes.isEmpty) {
      _lastRunDatasetCount = 0;
      return;
    }

    await setRunDetail('Resolving datasets...');

    final Set<String> candidateDatasetIds = <String>{};
    for (final NodeModel node in orderedNodes) {
      candidateDatasetIds.addAll(_datasetsForNode(node));
    }

    if (datasetIds != null) {
      candidateDatasetIds.retainAll(datasetIds);
    }

    final List<Dataset> targetDatasets = datasets.values
        .where((Dataset dataset) => candidateDatasetIds.contains(dataset.id))
        .toList();

    _lastRunDatasetCount = targetDatasets.length;
    if (targetDatasets.isEmpty) {
      return;
    }

    _runWaitingNodeIds
      ..clear()
      ..addAll(orderedNodes.map((NodeModel node) => node.id));
    _runActiveNodeId = null;
    final String hotDatasetId = targetDatasets.first.id;

    for (final Dataset dataset in targetDatasets) {
      await setRunDetail('Preparing ${dataset.label}...');
      for (final NodeModel node in orderedNodes) {
        if (!_datasetsForNode(node).contains(dataset.id)) {
          continue;
        }

        if (node.datasetStates[dataset.id] == DatasetState.done) {
          _lastSkippedNodeCount += 1;
          _runWaitingNodeIds.remove(node.id);
          await setRunDetail(
            'Skipping ${node.title} for ${dataset.label} (already done)...',
          );
          await _restoreMaterializedOutputIfNeeded(node, dataset);
          continue;
        }

        _runWaitingNodeIds.remove(node.id);
        _runActiveNodeId = node.id;
        final bool wasStale =
            node.datasetStates[dataset.id] == DatasetState.stale;
        node.datasetStates[dataset.id] = DatasetState.ready;
        try {
          dataset.ram.remove('artifact.lastChangeSet');
          await _restoreUpstreamInputForRun(node, dataset);
          if (wasStale) {
            await _restoreStaleNodeOutputForRun(node, dataset);
          }
          final List<String> sourceArtifactIds = node.type is ImportNodeType
              ? const <String>[]
              : _sourceArtifactIdsForDataset(dataset);
          await setRunDetail(
            'Running ${node.title} on ${dataset.label} (${processingResponsiveness.value.label}, ${node.type.executionChunkingStrategy})...',
            phase: RunActivityPhase.running,
          );
          await node.type.runChunked(
            dataset,
            node.params,
            NodeExecutionContext(
              setProgress: (String detail) =>
                  setRunDetailQuiet(detail, phase: RunActivityPhase.running),
              yieldIfNeeded: _executionChunkBoundary,
            ),
          );
          node.datasetStates[dataset.id] = DatasetState.done;
          _rememberLastRunParams(node, dataset.id);
          await _materializeNodeOutput(
            node,
            dataset,
            sourceArtifactIds: sourceArtifactIds,
            keepRamSnapshot: dataset.id == hotDatasetId,
          );
          _markImmediateChildrenStale(
            node.id,
            dataset.id,
            changeSet: _takeLastChangeSet(dataset),
          );
        } catch (_) {
          node.datasetStates[dataset.id] =
              _availableDatasetIdsForNode(node).contains(dataset.id)
              ? DatasetState.ready
              : DatasetState.notReady;
          rethrow;
        } finally {
          if (_runActiveNodeId == node.id) {
            _runActiveNodeId = null;
          }
        }
      }
      if (dataset.id != hotDatasetId) {
        _releasePreferDiskActiveOutputsForDataset(orderedNodes, dataset);
      }
    }
  }

  void _expandRuntimeDependencies(
    Set<String> expandedNodeIds, {
    required bool includeAncestors,
  }) {
    bool graphChanged;
    do {
      graphChanged = false;
      for (final String nodeId in expandedNodeIds.toList(growable: false)) {
        final NodeModel? node = _findNode(nodeId);
        if (node == null) {
          continue;
        }
        if (node.type is PSDNodeType) {
          final Set<String> forcedDependencies = _expandPsdRuntimePipeline(
            node,
          );
          final int previousExpandedCount = expandedNodeIds.length;
          expandedNodeIds.addAll(forcedDependencies);
          graphChanged =
              expandedNodeIds.length != previousExpandedCount || graphChanged;
        }
        if (node.type is SegmentationNodeType &&
            (node.params['mode'] ?? 'events').toString() == 'equal_windows') {
          final Set<String> forcedDependencies = _ensureEqualWindowMarkerParent(
            node,
          );
          final int previousExpandedCount = expandedNodeIds.length;
          expandedNodeIds.addAll(forcedDependencies);
          graphChanged =
              expandedNodeIds.length != previousExpandedCount || graphChanged;
        }
        final int previousExpandedCount = expandedNodeIds.length;
        if (includeAncestors) {
          expandedNodeIds.addAll(_collectAncestorsInclusive(node.id));
        }
        graphChanged =
            expandedNodeIds.length != previousExpandedCount || graphChanged;
      }
    } while (graphChanged);
    for (final String nodeId in expandedNodeIds) {
      final NodeModel? root = _findNode(nodeId);
      if (root == null ||
          root.params.containsKey('_runtimeGeneratedByNodeId')) {
        continue;
      }
      if (root.type is PSDNodeType ||
          (root.type is SegmentationNodeType &&
              (root.params['mode'] ?? 'events').toString() ==
                  'equal_windows')) {
        _syncAutomaticNodeGroup(root);
      }
    }
  }

  void _syncAutomaticNodeGroup(NodeModel root) {
    if (_ungroupedAutomaticRootNodeIds.contains(root.id)) {
      return;
    }
    final Set<String> memberIds = <String>{root.id};
    bool changed;
    do {
      changed = false;
      for (final NodeModel node in nodes) {
        final String? ownerId = node.params['_runtimeGeneratedByNodeId']
            ?.toString();
        if (ownerId != null &&
            memberIds.contains(ownerId) &&
            memberIds.add(node.id)) {
          changed = true;
        }
      }
    } while (changed);
    _createNodeGroup(
      label: root.type is PSDNodeType ? 'PSD setup' : 'Segmentation setup',
      nodeIds: memberIds,
      automaticRootNodeId: root.id,
    );
  }

  Set<String> _datasetsForNode(NodeModel node) {
    if (datasets.isEmpty) {
      return <String>{};
    }

    if (node.type is ImportNodeType) {
      final Set<String> availableDatasetIds = datasets.values
          .map((Dataset dataset) => dataset.id)
          .toSet();
      return _selectedDatasetIdsForNode(node, availableDatasetIds);
    }

    final Set<String> upstreamImports = <String>{};
    final Set<String> visited = <String>{};
    _collectUpstreamImports(node.id, upstreamImports, visited);

    if (upstreamImports.isEmpty) {
      if (node.type is ImpedancesNodeType) {
        return _selectedDatasetIdsForNode(
          node,
          datasets.values.map((Dataset dataset) => dataset.id).toSet(),
        );
      }
      return <String>{};
    }

    final Set<String> datasetIds = <String>{};
    for (final String importNodeId in upstreamImports) {
      final NodeModel? importNode = _findNode(importNodeId);
      if (importNode == null) continue;
      final Set<String> importDatasetIds = _selectedDatasetIdsForNode(
        importNode,
        datasets.values.map((Dataset dataset) => dataset.id).toSet(),
      );
      datasetIds.addAll(importDatasetIds);
    }
    return _selectedDatasetIdsForNode(node, datasetIds);
  }

  Map<String, Dataset> _datasetsById() {
    return <String, Dataset>{
      for (final Dataset dataset in datasets.values) dataset.id: dataset,
    };
  }

  Dataset? _datasetById(String datasetId) {
    for (final Dataset dataset in datasets.values) {
      if (dataset.id == datasetId) {
        return dataset;
      }
    }
    return null;
  }

  Set<String> _availableDatasetIdsForNode(NodeModel node) {
    if (node.type is ImportNodeType) {
      return datasets.values.map((Dataset dataset) => dataset.id).toSet();
    }

    final List<NodeModel> parents = _dependencyParentsForNode(node);
    if (parents.isEmpty) {
      return <String>{};
    }

    return datasets.values
        .where((Dataset dataset) {
          return parents.every(
            (NodeModel parent) =>
                (parent.datasetStates[dataset.id] ?? DatasetState.notReady) !=
                DatasetState.notReady,
          );
        })
        .map((Dataset dataset) => dataset.id)
        .toSet();
  }

  Map<String, DatasetState> _processedDatasetStatesForNode(NodeModel node) {
    return <String, DatasetState>{
      for (final Dataset dataset in datasets.values)
        dataset.id: _effectiveDatasetStateForNode(node, dataset.id),
    };
  }

  NodePortStatusSummary _portStatusSummaryForNode(NodeModel node) {
    return NodePortStatusSummary(
      inputs: node.inputPorts
          .map(
            (PortSpec input) =>
                _inputPortStatusSummaryForNode(node: node, input: input),
          )
          .toList(growable: false),
      outputs: node.outputPorts
          .map(
            (PortSpec output) => NodePortDatasetSummary(
              label: output.name,
              type: output.type,
              readyCount: _createdDatasetCountForNode(node),
              totalCount: _availableDatasetIdsForNode(node).length,
            ),
          )
          .toList(growable: false),
    );
  }

  NodePortDatasetSummary _inputPortStatusSummaryForNode({
    required NodeModel node,
    required PortSpec input,
  }) {
    final int inputIndex = node.inputPorts.indexOf(input);
    final List<NodeModel> parents = connections
        .where((Map<String, dynamic> connection) {
          return connection['toNode'] == node.id &&
              (connection['toPort'] as int? ?? -1) == inputIndex;
        })
        .map((Map<String, dynamic> connection) {
          return _findNode(connection['fromNode'] as String? ?? '');
        })
        .whereType<NodeModel>()
        .toList(growable: false);

    if (parents.isEmpty) {
      return NodePortDatasetSummary(
        label: input.name,
        type: input.type,
        readyCount: 0,
        totalCount: 0,
      );
    }

    final Set<String> totalDatasetIds = <String>{};
    final Set<String> createdDatasetIds = <String>{};
    for (final NodeModel parent in parents) {
      totalDatasetIds.addAll(_datasetsForNode(parent));
      for (final Dataset dataset in datasets.values) {
        if (_datasetStateHasCreatedOutput(parent, dataset.id)) {
          createdDatasetIds.add(dataset.id);
        }
      }
    }

    return NodePortDatasetSummary(
      label: input.name,
      type: input.type,
      readyCount: createdDatasetIds.intersection(totalDatasetIds).length,
      totalCount: totalDatasetIds.length,
    );
  }

  int _createdDatasetCountForNode(NodeModel node) {
    int count = 0;
    for (final Dataset dataset in datasets.values) {
      if (_datasetStateHasCreatedOutput(node, dataset.id)) {
        count++;
      }
    }
    return count;
  }

  bool _datasetStateHasCreatedOutput(NodeModel node, String datasetId) {
    final DatasetState state = _effectiveDatasetStateForNode(node, datasetId);
    return state == DatasetState.done ||
        state == DatasetState.partial ||
        state == DatasetState.stale;
  }

  Map<String, List<String>> _datasetSourceLabelsForNode(NodeModel node) {
    if (node.type is ImportNodeType) {
      return <String, List<String>>{
        for (final Dataset dataset in datasets.values)
          dataset.id: <String>['Source file'],
      };
    }

    final Map<String, List<String>> labelsByDataset = <String, List<String>>{};
    final List<NodeModel> parents = _immediateParents(node.id);
    for (final NodeModel parent in parents) {
      final String descriptor = _nodeDescriptor(parent);
      for (final Dataset dataset in datasets.values) {
        if ((parent.datasetStates[dataset.id] ?? DatasetState.notReady) !=
            DatasetState.notReady) {
          labelsByDataset
              .putIfAbsent(dataset.id, () => <String>[])
              .add(descriptor);
        }
      }
    }

    for (final List<String> labels in labelsByDataset.values) {
      labels.sort();
    }
    return labelsByDataset;
  }

  Set<String> _selectedDatasetIdsForNode(
    NodeModel node,
    Set<String> availableDatasetIds,
  ) {
    final List<dynamic> selectedDatasetIds =
        (node.params['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[]);
    if (selectedDatasetIds.isEmpty) {
      return Set<String>.from(availableDatasetIds);
    }

    final Set<String> resolvedSelection = <String>{};
    for (final Dataset dataset in datasets.values) {
      if (selectedDatasetIds.contains(dataset.id) ||
          selectedDatasetIds.contains(dataset.path)) {
        resolvedSelection.add(dataset.id);
      }
    }
    return resolvedSelection.intersection(availableDatasetIds);
  }

  List<NodeModel> _immediateParents(String nodeId) {
    final List<NodeModel> parents = <NodeModel>[];
    for (final Map<String, dynamic> connection in connections) {
      if (connection['toNode'] != nodeId) continue;
      final NodeModel? parent = _findNode(connection['fromNode'] as String);
      if (parent != null) {
        parents.add(parent);
      }
    }
    return parents;
  }

  List<NodeModel> _immediateChildren(String nodeId) {
    final List<NodeModel> children = <NodeModel>[];
    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != nodeId) continue;
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child != null) {
        children.add(child);
      }
    }
    return children;
  }

  List<NodeModel> _orderedNodes(Set<String> nodeIds) {
    final Map<String, int> inDegree = <String, int>{
      for (final String id in nodeIds) id: 0,
    };
    final Map<String, List<String>> outgoingEdges = <String, List<String>>{
      for (final String id in nodeIds) id: <String>[],
    };

    for (final Map<String, dynamic> connection in connections) {
      final String fromNode = connection['fromNode'] as String;
      final String toNode = connection['toNode'] as String;
      if (nodeIds.contains(fromNode) && nodeIds.contains(toNode)) {
        inDegree[toNode] = (inDegree[toNode] ?? 0) + 1;
        outgoingEdges.putIfAbsent(fromNode, () => <String>[]).add(toNode);
      }
    }

    final List<String> queue = nodes
        .map((NodeModel node) => node.id)
        .where((String id) => nodeIds.contains(id) && inDegree[id] == 0)
        .toList();
    final List<String> orderedIds = <String>[];
    int queueIndex = 0;

    while (queueIndex < queue.length) {
      final String current = queue[queueIndex++];
      orderedIds.add(current);

      for (final String target in outgoingEdges[current] ?? const <String>[]) {
        inDegree[target] = (inDegree[target] ?? 1) - 1;
        if (inDegree[target] == 0) {
          queue.add(target);
        }
      }
    }

    for (final NodeModel node in nodes) {
      if (nodeIds.contains(node.id) && !orderedIds.contains(node.id)) {
        orderedIds.add(node.id);
      }
    }

    return orderedIds
        .map(_findNode)
        .whereType<NodeModel>()
        .toList(growable: false);
  }

  Set<String> _collectAncestorsInclusive(String nodeId) {
    final Set<String> result = <String>{nodeId};
    final List<String> stack = <String>[nodeId];

    while (stack.isNotEmpty) {
      final String current = stack.removeLast();
      for (final Map<String, dynamic> connection in connections) {
        if (connection['toNode'] != current) continue;
        final String parentId = connection['fromNode'] as String;
        if (result.add(parentId)) {
          stack.add(parentId);
        }
      }
    }

    return result;
  }

  Set<String> _collectDescendantsInclusive(String nodeId) {
    final Set<String> result = <String>{nodeId};
    final List<String> stack = <String>[nodeId];

    while (stack.isNotEmpty) {
      final String current = stack.removeLast();
      for (final Map<String, dynamic> connection in connections) {
        if (connection['fromNode'] != current) continue;
        final String childId = connection['toNode'] as String;
        if (result.add(childId)) {
          stack.add(childId);
        }
      }
    }

    return result;
  }

  void _collectUpstreamImports(
    String nodeId,
    Set<String> imports,
    Set<String> visited,
  ) {
    if (!visited.add(nodeId)) {
      return;
    }

    final NodeModel? node = _findNode(nodeId);
    if (node?.type is ImportNodeType) {
      imports.add(nodeId);
    }

    for (final Map<String, dynamic> connection in connections) {
      if (connection['toNode'] != nodeId) continue;
      _collectUpstreamImports(
        connection['fromNode'] as String,
        imports,
        visited,
      );
    }
  }

  void _markAllNodes(String datasetId, DatasetState state) {
    for (final NodeModel node in nodes) {
      node.datasetStates[datasetId] = state;
    }
  }

  void _refreshDatasetAvailability(String datasetId) {
    final List<NodeModel> orderedNodes = _orderedNodes(
      nodes.map((NodeModel node) => node.id).toSet(),
    );
    for (final NodeModel node in orderedNodes) {
      final bool selectedForNode = _datasetsForNode(node).contains(datasetId);
      if (!selectedForNode) {
        if ((node.datasetStates[datasetId] ?? DatasetState.notReady) !=
            DatasetState.done) {
          node.datasetStates[datasetId] = DatasetState.notReady;
        }
        continue;
      }

      final List<NodeModel> parents = _immediateParents(node.id);
      final bool structurallyReady =
          node.type is ImportNodeType ||
          parents.every(
            (NodeModel parent) =>
                (parent.datasetStates[datasetId] ?? DatasetState.notReady) !=
                DatasetState.notReady,
          );

      if (!structurallyReady) {
        if ((node.datasetStates[datasetId] ?? DatasetState.notReady) !=
            DatasetState.done) {
          node.datasetStates[datasetId] = DatasetState.notReady;
        }
        continue;
      }

      final DatasetState currentState =
          node.datasetStates[datasetId] ?? DatasetState.notReady;
      final bool hasMaterializedResult =
          _nodeRamSnapshots[node.id]?.containsKey(datasetId) == true ||
          _nodeDiskSnapshotIds[node.id]?.contains(datasetId) == true;
      if ((currentState == DatasetState.done ||
              currentState == DatasetState.stale) &&
          hasMaterializedResult) {
        continue;
      }

      node.datasetStates[datasetId] = DatasetState.ready;
    }
  }

  ArtifactChangeSet? _takeLastChangeSet(Dataset dataset) {
    final Object? rawValue = dataset.ram.remove('artifact.lastChangeSet');
    if (rawValue is ArtifactChangeSet) {
      return rawValue;
    }
    if (rawValue is Map) {
      return ArtifactChangeSet.fromJson(Map<String, dynamic>.from(rawValue));
    }
    return null;
  }

  void _markImmediateChildrenStale(
    String nodeId,
    String datasetId, {
    ArtifactChangeSet? changeSet,
  }) {
    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != nodeId) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child == null) {
        continue;
      }
      if (child.datasetStates[datasetId] == DatasetState.done &&
          _nodeInvalidatedByChangeSet(child, changeSet)) {
        child.datasetStates[datasetId] = DatasetState.stale;
      }
    }
  }

  bool _nodeInvalidatedByChangeSet(
    NodeModel node,
    ArtifactChangeSet? changeSet,
  ) {
    if (changeSet == null) {
      return true;
    }
    if (changeSet.changeTypes.isEmpty) {
      return false;
    }
    if (changeSet.changeTypes.every(
      (ArtifactChangeType type) =>
          type == ArtifactChangeType.datasetMetadata ||
          type == ArtifactChangeType.storage,
    )) {
      return false;
    }

    final bool usesSignal = node.inputPorts.any(
      (PortSpec port) => port.type == PortType.signal,
    );
    final bool usesMarkers = node.inputPorts.any(
      (PortSpec port) => port.type == PortType.markers,
    );
    final bool usesMetadata = node.inputPorts.any(
      (PortSpec port) => port.type == PortType.metadata,
    );
    final bool signalChanged =
        changeSet.touchesSamples ||
        changeSet.touchesChannelLabels ||
        changeSet.touchesChannelTopology ||
        changeSet.touchesChannelCoordinates;
    final bool markerOrSegmentChanged =
        changeSet.touchesMarkers || changeSet.touchesSegmentWindows;

    if (changeSet.touchesParams) {
      return true;
    }
    if (signalChanged && usesSignal) {
      return true;
    }
    if (markerOrSegmentChanged && (usesMarkers || usesMetadata)) {
      return true;
    }
    if (!signalChanged && !markerOrSegmentChanged) {
      return true;
    }
    return false;
  }

  void applyMarkersFromVisualization({
    required String nodeId,
    required Dataset dataset,
    required List<dynamic> rawMarkers,
  }) {
    final NodeModel? sourceNode = _markerEditSourceNode(nodeId);
    if (sourceNode == null) {
      return;
    }

    _recordUndo('save marker edits', datasetArtifactIds: <String>{dataset.id});
    final NodeModel markerNode = _ensureMarkerNode(sourceNode);
    markerNode.params['markers'] = rawMarkers;

    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      final List<String> sourceArtifactIds = _sourceArtifactIdsForDataset(
        dataset,
      );
      dataset.timeSeries = timeSeries.copyWith(
        markers: AddRemoveMarkersNodeType.markersForDataset(
          dataset.id,
          rawMarkers,
        ),
      );
      dataset.ram['artifact.lastChangeSet'] = ArtifactChangeSet(
        datasetId: dataset.id,
        sourceNodeId: markerNode.id,
        changeTypes: const <ArtifactChangeType>{ArtifactChangeType.markers},
        description: 'Marker edits',
      );
      _cacheVisualizationEditOutput(
        markerNode,
        dataset,
        sourceArtifactIds: sourceArtifactIds,
      );
    }

    markerNode.datasetStates[dataset.id] = DatasetState.done;
    _markImmediateChildrenStale(
      markerNode.id,
      dataset.id,
      changeSet: _takeLastChangeSet(dataset),
    );
    selectedNodeId = markerNode.id;
    selectedNodeIds
      ..clear()
      ..add(markerNode.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  void applyChannelEditsFromVisualization({
    required String nodeId,
    required Dataset dataset,
    required Map<String, dynamic> datasetConfig,
  }) {
    final NodeModel? sourceNode = _channelEditSourceNode(nodeId);
    if (sourceNode == null) {
      return;
    }

    _recordUndo('save channel edits', datasetArtifactIds: <String>{dataset.id});
    final NodeModel channelNode = _ensureChannelEditNode(sourceNode);
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    final Map<String, dynamic> boundConfig = timeSeries == null
        ? datasetConfig
        : EditChannelsNodeType.bindConfigToChannelLabels(
            datasetConfig,
            timeSeries.channelLabels,
          );
    EditChannelsNodeType.setConfigForDataset(
      channelNode.params,
      dataset.id,
      boundConfig,
    );

    if (timeSeries != null) {
      final List<String> sourceArtifactIds = _sourceArtifactIdsForDataset(
        dataset,
      );
      final ArtifactChangeSet changeSet =
          EditChannelsNodeType.changeSetForConfig(
            datasetId: dataset.id,
            timeSeries: timeSeries,
            config: boundConfig,
            sourceNodeId: channelNode.id,
          );
      dataset.timeSeries = EditChannelsNodeType.applyChannelEdits(
        timeSeries,
        boundConfig,
        warningSink: (String warning) {
          dataset.ram['editChannels.lastWarning'] = warning;
        },
      );
      dataset.ram['artifact.lastChangeSet'] = changeSet;
      _cacheVisualizationEditOutput(
        channelNode,
        dataset,
        sourceArtifactIds: sourceArtifactIds,
      );
    }

    channelNode.datasetStates[dataset.id] = DatasetState.done;
    _markImmediateChildrenStale(
      channelNode.id,
      dataset.id,
      changeSet: _takeLastChangeSet(dataset),
    );
    selectedNodeId = channelNode.id;
    selectedNodeIds
      ..clear()
      ..add(channelNode.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();
  }

  Future<String> persistViewerEdits({
    required String viewerNodeId,
    required Dataset dataset,
    List<Map<String, dynamic>>? markerEdits,
    Map<String, dynamic>? channelEditConfig,
    Map<String, dynamic>? interactiveArtifactParams,
    bool runAfterSave = false,
  }) async {
    final NodeModel? viewerNode = _findNode(viewerNodeId);
    if (viewerNode == null) {
      return 'The visualized node is no longer available.';
    }
    final NodeModel? sourceNode = _viewerEditSourceNodeForDataset(
      viewerNodeId,
      dataset,
    );
    if (sourceNode == null) {
      return 'Could not resolve the source branch for this visualizer.';
    }

    List<Map<String, dynamic>>? markerEditsValue = markerEdits;
    if (interactiveArtifactParams != null) {
      final TimeSeriesData? timeSeries = dataset.timeSeries;
      if (timeSeries != null) {
        markerEditsValue =
            InteractiveArtifactDetectionNodeType.acceptedMarkersForDataset(
                  dataset.id,
                  interactiveArtifactParams,
                  baseMarkers: markerEdits == null
                      ? timeSeries.markers
                      : AddRemoveMarkersNodeType.markersForDataset(
                          dataset.id,
                          markerEdits,
                        ),
                )
                .map((TimeMarker marker) {
                  return <String, dynamic>{
                    ...marker.toJson(),
                    'datasetId': dataset.id,
                  };
                })
                .toList(growable: false);
      }
    }

    final bool hasMarkerEdits = markerEditsValue != null;
    final bool hasChannelEdits =
        channelEditConfig != null &&
        EditChannelsNodeType.hasMeaningfulChanges(channelEditConfig);
    final bool hasInteractiveEdits = interactiveArtifactParams != null;
    if (!hasMarkerEdits && !hasChannelEdits && !hasInteractiveEdits) {
      return 'No unsaved viewer edits were found.';
    }

    _recordUndo('save viewer edits', datasetArtifactIds: <String>{dataset.id});

    final NodeModel? insertBeforeNode = viewerNode.type is VisualizationNodeType
        ? viewerNode
        : null;
    NodeModel anchorNode = sourceNode;
    NodeModel? lastCreatedNode;
    final List<String> createdNodeTitles = <String>[];
    final Set<String> createdNodeIds = <String>{};
    final Map<String, dynamic>? channelEditConfigValue = channelEditConfig;

    if (hasChannelEdits && hasMarkerEdits) {
      lastCreatedNode = _spawnViewerEditNode(
        sourceNode: anchorNode,
        insertBeforeNode: insertBeforeNode,
        type: EditChannelsAndMarkersNodeType(),
        datasetId: dataset.id,
        params: <String, dynamic>{
          'channelEditsByDataset': <String, dynamic>{
            dataset.id: channelEditConfigValue,
          },
          'markers': markerEditsValue,
          'applyEmptyMarkerSet': true,
        },
      );
      anchorNode = lastCreatedNode;
      createdNodeTitles.add(lastCreatedNode.title);
      createdNodeIds.add(lastCreatedNode.id);
    } else if (hasChannelEdits) {
      lastCreatedNode = _spawnViewerEditNode(
        sourceNode: anchorNode,
        insertBeforeNode: insertBeforeNode,
        type: EditChannelsNodeType(),
        datasetId: dataset.id,
        params: <String, dynamic>{
          'channelEditsByDataset': <String, dynamic>{
            dataset.id: channelEditConfigValue,
          },
        },
      );
      anchorNode = lastCreatedNode;
      createdNodeTitles.add(lastCreatedNode.title);
      createdNodeIds.add(lastCreatedNode.id);
    }
    if (hasMarkerEdits && !hasChannelEdits) {
      lastCreatedNode = _spawnViewerEditNode(
        sourceNode: anchorNode,
        insertBeforeNode: insertBeforeNode,
        type: AddRemoveMarkersNodeType(),
        datasetId: dataset.id,
        params: <String, dynamic>{
          'markers': markerEditsValue,
          'applyEmptyMarkerSet': true,
        },
      );
      anchorNode = lastCreatedNode;
      createdNodeTitles.add(lastCreatedNode.title);
      createdNodeIds.add(lastCreatedNode.id);
    }

    if (lastCreatedNode == null) {
      return 'No viewer edits were persisted.';
    }
    if (createdNodeTitles.length > 1) {
      _createNodeGroup(label: 'Viewer edits', nodeIds: createdNodeIds);
    }

    if (insertBeforeNode != null) {
      _seedNodeDatasetStates(insertBeforeNode);
    }
    // Keep the current visualizer anchored to the node the user opened,
    // even when saving spawns one or more downstream edit nodes.
    selectedNodeId = viewerNode.id;
    selectedNodeIds
      ..clear()
      ..add(viewerNode.id);
    selectedConnectionIndex = null;
    _clearPendingConnection();

    if (!runAfterSave) {
      return _viewerEditSaveMessage(
        createdNodeTitles: createdNodeTitles,
        ranNodes: false,
      );
    }

    String? finalDetail;
    final NodeModel nodeToRun = lastCreatedNode;
    try {
      finalDetail = await runQueued(
        label: 'Running ${nodeToRun.title}',
        lockedNodeIds: _collectAncestorsInclusive(nodeToRun.id),
        action: () =>
            runFromStart(nodeToRun.id, datasetIds: <String>{dataset.id}),
        successDetail: () => _viewerEditSaveMessage(
          createdNodeTitles: createdNodeTitles,
          ranNodes: true,
        ),
      );
      return finalDetail;
    } catch (error) {
      finalDetail = 'Save and run failed: $error';
      rethrow;
    }
  }

  String _viewerEditSaveMessage({
    required List<String> createdNodeTitles,
    required bool ranNodes,
  }) {
    final String createdSummary = createdNodeTitles.length == 1
        ? createdNodeTitles.first
        : createdNodeTitles.join(' -> ');
    return ranNodes
        ? 'Created and ran $createdSummary.'
        : 'Created $createdSummary.';
  }

  NodeModel? _viewerEditSourceNodeForDataset(
    String viewerNodeId,
    Dataset dataset,
  ) {
    final String? sourceKey = dataset.ram['viewer.sourceKey']?.toString();
    if (sourceKey != null && sourceKey.contains('|')) {
      final String sourceNodeId = sourceKey.split('|').first;
      final NodeModel? sourceNode = _findNode(sourceNodeId);
      if (sourceNode != null) {
        return sourceNode;
      }
    }
    final NodeModel? viewerNode = _findNode(viewerNodeId);
    if (viewerNode == null) {
      return null;
    }
    if (viewerNode.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(viewerNode.id)
          .where((NodeModel parent) => parent.outputPorts.isNotEmpty)
          .toList(growable: false);
      if (parents.isNotEmpty) {
        return parents.first;
      }
      return null;
    }
    return viewerNode;
  }

  NodeModel _spawnViewerEditNode({
    required NodeModel sourceNode,
    required NodeType type,
    required String datasetId,
    required Map<String, dynamic> params,
    NodeModel? insertBeforeNode,
  }) {
    final NodeModel node = _buildNode(
      type: type,
      position: _viewerEditSpawnPosition(
        sourceNode: sourceNode,
        insertBeforeNode: insertBeforeNode,
      ),
      params: <String, dynamic>{
        ...type.defaultParams,
        ...params,
        'selectedDatasetIds': <String>[datasetId],
      },
    );
    nodes.add(node);

    if (insertBeforeNode != null) {
      connections.removeWhere(
        (Map<String, dynamic> connection) =>
            connection['fromNode'] == sourceNode.id &&
            connection['toNode'] == insertBeforeNode.id,
      );
    }

    final _PortConnection? fromConnection = _firstMatchingPortConnection(
      sourceNode,
      node,
    );
    if (fromConnection != null) {
      connections.add(<String, dynamic>{
        'fromNode': sourceNode.id,
        'fromPort': fromConnection.fromPortIndex,
        'toNode': node.id,
        'toPort': fromConnection.toPortIndex,
      });
    }

    if (insertBeforeNode != null) {
      final _PortConnection? toConnection = _firstMatchingPortConnection(
        node,
        insertBeforeNode,
      );
      if (toConnection != null) {
        connections.add(<String, dynamic>{
          'fromNode': node.id,
          'fromPort': toConnection.fromPortIndex,
          'toNode': insertBeforeNode.id,
          'toPort': toConnection.toPortIndex,
        });
      }
    }

    _seedNodeDatasetStates(node);

    return node;
  }

  Offset _viewerEditSpawnPosition({
    required NodeModel sourceNode,
    required NodeModel? insertBeforeNode,
  }) {
    final Offset desired = insertBeforeNode == null
        ? Offset(
            sourceNode.position.dx,
            sourceNode.position.dy + _cardHeight + _spawnGap,
          )
        : Offset(
            (sourceNode.position.dx + insertBeforeNode.position.dx) / 2,
            (sourceNode.position.dy + insertBeforeNode.position.dy) / 2,
          );
    return _nearestAvailablePosition(desired);
  }

  void _seedNodeDatasetStates(NodeModel node) {
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(node);
    for (final Dataset dataset in datasets.values) {
      node.datasetStates[dataset.id] = availableDatasetIds.contains(dataset.id)
          ? DatasetState.ready
          : DatasetState.notReady;
    }
  }

  void _cacheVisualizationEditOutput(
    NodeModel node,
    Dataset dataset, {
    List<String> sourceArtifactIds = const <String>[],
  }) {
    _stampArtifactIdentities(
      node: node,
      dataset: dataset,
      sourceArtifactIds: sourceArtifactIds,
    );
    final Set<BrainStoryArtifactKind> outputKinds =
        _artifactKindsForNodeOutputs(node, dataset);
    final DatasetArtifactSnapshot snapshot =
        DatasetArtifactSnapshot.fromDataset(
          dataset,
          includedKinds: outputKinds,
        );
    if (snapshot.isEmpty) {
      _nodeRamSnapshots[node.id]?.remove(dataset.id);
      return;
    }
    _nodeRamSnapshots.putIfAbsent(
      node.id,
      () => <String, DatasetArtifactSnapshot>{},
    )[dataset.id] = snapshot;
  }

  void _showStatusSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  NodeDatasetActions _datasetActionsForNode({
    required NodeModel node,
    required VoidCallback update,
  }) {
    return NodeDatasetActions(
      supportsDisk: supportsNodeSnapshotDiskStore,
      refresh: (Map<String, dynamic> params) =>
          _datasetStatusSnapshotForNode(node: node, params: params),
      hasLoadableDiskCache:
          (Map<String, dynamic> params, Set<String> datasetIds) =>
              _nodeHasLoadableDiskCache(node: node, datasetIds: datasetIds),
      runAllPrevious: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _runNodeDatasetAction(
            runLabel: 'Running pipeline to ${node.title}',
            action: () => runFromStart(node.id, datasetIds: datasetIds),
            node: node,
            update: update,
          ),
      runThisNode: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _runNodeDatasetAction(
            runLabel: 'Running ${node.title}',
            action: () => runThisStep(node.id, datasetIds: datasetIds),
            node: node,
            update: update,
          ),
      clearResults: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _clearNodeResults(
            node: node,
            params: params,
            datasetIds: datasetIds,
            update: update,
          ),
      loadFromDisk: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _loadNodeSnapshotsToRam(
            node: node,
            datasetIds: datasetIds,
            update: update,
          ),
      purgeActiveMemory:
          (Map<String, dynamic> params, Set<String> datasetIds) =>
              _releaseNodeSnapshotsFromRam(
                node: node,
                datasetIds: datasetIds,
                update: update,
              ),
      saveToDisk: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _saveNodeSnapshotsToDisk(
            node: node,
            datasetIds: datasetIds,
            update: update,
          ),
      purgeFromDisk: (Map<String, dynamic> params, Set<String> datasetIds) =>
          _deleteNodeSnapshotsFromDisk(
            node: node,
            datasetIds: datasetIds,
            update: update,
          ),
    );
  }

  Future<void> _materializeNodeOutput(
    NodeModel node,
    Dataset dataset, {
    List<String> sourceArtifactIds = const <String>[],
    bool keepRamSnapshot = true,
  }) async {
    await setRunDetail(
      'Materializing ${node.title} for ${dataset.label}...',
      phase: RunActivityPhase.finalizing,
    );
    _stampArtifactIdentities(
      node: node,
      dataset: dataset,
      sourceArtifactIds: sourceArtifactIds,
    );
    final Set<BrainStoryArtifactKind> outputKinds =
        _artifactKindsForNodeOutputs(node, dataset);
    final DatasetArtifactSnapshot snapshot =
        DatasetArtifactSnapshot.fromDataset(
          dataset,
          includedKinds: outputKinds,
        );
    if (snapshot.isEmpty) {
      _nodeRamSnapshots[node.id]?.remove(dataset.id);
      return;
    }

    final NodeStoragePolicy policy = _storagePolicyForNode(node);
    if (policy != NodeStoragePolicy.onDemand &&
        (policy != NodeStoragePolicy.preferDisk || keepRamSnapshot)) {
      _nodeRamSnapshots.putIfAbsent(
        node.id,
        () => <String, DatasetArtifactSnapshot>{},
      )[dataset.id] = snapshot;
    } else {
      _nodeRamSnapshots[node.id]?.remove(dataset.id);
    }

    if (supportsNodeSnapshotDiskStore &&
        (policy == NodeStoragePolicy.preferDisk ||
            policy == NodeStoragePolicy.ramAndDisk)) {
      await saveNodeSnapshotJson(
        nodeId: node.id,
        datasetId: dataset.id,
        jsonPayload: jsonEncode(snapshot.toJson()),
      );
      _saveSnapshotMetadata(node.id, dataset);
      _nodeDiskSnapshotIds
          .putIfAbsent(node.id, () => <String>{})
          .add(dataset.id);
      if (policy == NodeStoragePolicy.preferDisk && !keepRamSnapshot) {
        _nodeRamSnapshots[node.id]?.remove(dataset.id);
      }
    }
  }

  void _releasePreferDiskActiveOutputsForDataset(
    List<NodeModel> orderedNodes,
    Dataset dataset,
  ) {
    for (final NodeModel node in orderedNodes.reversed) {
      if (node.datasetStates[dataset.id] != DatasetState.done ||
          _storagePolicyForNode(node) != NodeStoragePolicy.preferDisk) {
        continue;
      }
      _releaseActiveDatasetArtifactsProducedBy(node, dataset);
    }
  }

  void _releaseActiveDatasetArtifactsProducedBy(
    NodeModel node,
    Dataset dataset,
  ) {
    final Set<BrainStoryArtifactKind> producedKinds =
        _artifactKindsForNodeOutputs(node, dataset).where((
          BrainStoryArtifactKind kind,
        ) {
          return dataset.artifactIdentityFor(kind)?.producerNodeId == node.id;
        }).toSet();
    if (producedKinds.isEmpty) {
      return;
    }
    for (final BrainStoryArtifactKind kind in producedKinds) {
      switch (kind) {
        case BrainStoryArtifactKind.timeSeries:
          dataset.timeSeries = null;
          break;
        case BrainStoryArtifactKind.segmentedTimeSeries:
          dataset.segmentedTimeSeries = null;
          break;
        case BrainStoryArtifactKind.spectrum:
          dataset.spectrum = null;
          break;
        case BrainStoryArtifactKind.fooofResult:
          dataset.fooofResult = null;
          break;
        case BrainStoryArtifactKind.featureTable:
          dataset.featureTable = null;
          break;
        case BrainStoryArtifactKind.bridgeDetection:
          dataset.bridgeDetection = null;
          break;
        case BrainStoryArtifactKind.timeFrequency:
          dataset.timeFrequency = null;
          break;
        case BrainStoryArtifactKind.matrixTransformation:
          dataset.matrixTransformation = null;
          break;
        case BrainStoryArtifactKind.markers:
        case BrainStoryArtifactKind.markerChange:
        case BrainStoryArtifactKind.channelCoordinates:
        case BrainStoryArtifactKind.unknown:
          break;
      }
    }
  }

  DatasetState _unmaterializedStateForNodeDataset(
    NodeModel node,
    String datasetId,
  ) {
    return _availableDatasetIdsForNode(node).contains(datasetId)
        ? DatasetState.ready
        : DatasetState.notReady;
  }

  List<String> _sourceArtifactIdsForDataset(Dataset dataset) {
    return dataset.artifactIdentities.values
        .map((ArtifactIdentity identity) => identity.artifactId)
        .where((String id) => id.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  void _rememberLastRunParams(NodeModel node, String datasetId) {
    final Map<String, dynamic> lastRunParamsByDataset =
        Map<String, dynamic>.from(
          node.params[_lastRunParamsByDatasetKey] as Map? ??
              const <String, dynamic>{},
        );
    lastRunParamsByDataset[datasetId] = _deepCloneJsonMap(
      _exportableNodeParams(node.params),
    );
    node.params[_lastRunParamsByDatasetKey] = lastRunParamsByDataset;
  }

  void _stampArtifactIdentities({
    required NodeModel node,
    required Dataset dataset,
    List<String> sourceArtifactIds = const <String>[],
  }) {
    for (final BrainStoryArtifactKind kind in _artifactKindsForNodeOutputs(
      node,
      dataset,
    )) {
      final String artifactId = _artifactIdForNodeDatasetKind(
        node: node,
        dataset: dataset,
        kind: kind,
      );
      final ArtifactIdentity? previous = dataset.artifactIdentityFor(kind);
      dataset.setArtifactIdentity(
        ArtifactIdentity(
          artifactId: artifactId,
          datasetId: dataset.id,
          kind: kind,
          producerNodeId: node.id,
          sourceArtifactIds: sourceArtifactIds,
          revision: previous?.artifactId == artifactId
              ? previous!.revision + 1
              : 0,
        ),
      );
    }
  }

  String _artifactIdForNodeDatasetKind({
    required NodeModel node,
    required Dataset dataset,
    required BrainStoryArtifactKind kind,
  }) {
    return '${node.id}:${dataset.id}:${kind.name}';
  }

  Set<BrainStoryArtifactKind> _artifactKindsForNodeOutputs(
    NodeModel node,
    Dataset dataset,
  ) {
    final Set<BrainStoryArtifactKind> kinds = <BrainStoryArtifactKind>{};
    for (final PortSpec output in node.outputPorts) {
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

  Set<BrainStoryArtifactKind> _artifactKindsForSnapshotOutputs(
    NodeModel node,
    DatasetArtifactSnapshot snapshot,
  ) {
    final Set<BrainStoryArtifactKind> kinds = <BrainStoryArtifactKind>{};
    for (final PortSpec output in node.outputPorts) {
      final String outputName = output.name.toLowerCase();
      switch (output.type) {
        case PortType.signal:
          if ((outputName.contains('psd') || outputName.contains('spectrum')) &&
              snapshot.spectrum != null) {
            kinds.add(BrainStoryArtifactKind.spectrum);
          } else if (snapshot.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.timeSeries);
          }
          break;
        case PortType.markers:
          if (snapshot.markers != null || snapshot.timeSeries != null) {
            kinds.add(BrainStoryArtifactKind.markers);
          }
          break;
        case PortType.metadata:
          if (outputName.contains('segment') &&
              snapshot.segmentedTimeSeries != null) {
            kinds.add(BrainStoryArtifactKind.segmentedTimeSeries);
          } else if (snapshot.fooofResult != null) {
            kinds.add(BrainStoryArtifactKind.fooofResult);
          } else if (snapshot.featureTable != null) {
            kinds.add(BrainStoryArtifactKind.featureTable);
          } else if (snapshot.bridgeDetection != null) {
            kinds.add(BrainStoryArtifactKind.bridgeDetection);
          } else if (snapshot.timeFrequency != null) {
            kinds.add(BrainStoryArtifactKind.timeFrequency);
          }
          break;
        case PortType.matrixTransformation:
          if (snapshot.matrixTransformation != null) {
            kinds.add(BrainStoryArtifactKind.matrixTransformation);
          }
          break;
      }
    }
    return kinds;
  }

  Future<NodeDatasetStatusSnapshot> _datasetStatusSnapshotForNode({
    required NodeModel node,
    required Map<String, dynamic> params,
  }) async {
    final NodeModel configuredNode = _nodeWithParams(node, params);
    final Set<String> diskSavedDatasetIds = <String>{};
    if (supportsNodeSnapshotDiskStore) {
      final List<String> datasetIds = datasets.values
          .map((Dataset dataset) => dataset.id)
          .toList(growable: false);
      final List<bool> diskFlags = await Future.wait(
        datasetIds.map((String datasetId) {
          return hasNodeSnapshotOnDisk(nodeId: node.id, datasetId: datasetId);
        }),
      );
      for (int index = 0; index < datasetIds.length; index++) {
        if (diskFlags[index]) {
          diskSavedDatasetIds.add(datasetIds[index]);
        }
      }
      if (diskSavedDatasetIds.isEmpty) {
        _nodeDiskSnapshotIds.remove(node.id);
      } else {
        _nodeDiskSnapshotIds[node.id] = diskSavedDatasetIds;
      }
    }

    return NodeDatasetStatusSnapshot(
      availableDatasetIds: _availableDatasetIdsForNode(configuredNode),
      processedDatasetStates: _processedDatasetStatesForNode(node),
      ramLoadedDatasetIds:
          _nodeRamSnapshots[node.id]?.keys.toSet() ?? const <String>{},
      diskSavedDatasetIds: diskSavedDatasetIds,
    );
  }

  Future<String> _runNodeDatasetAction({
    required String runLabel,
    required Future<void> Function() action,
    required NodeModel node,
    required VoidCallback update,
  }) async {
    try {
      final String finalDetail = await runQueued(
        label: runLabel,
        lockedNodeIds: _collectAncestorsInclusive(node.id),
        action: action,
        successDetail: () => _lastRunDatasetCount == 0
            ? 'No datasets matched ${node.title}.'
            : 'Ran ${node.title} for $_lastRunDatasetCount dataset(s).',
      );
      update();
      return finalDetail;
    } catch (error) {
      rethrow;
    }
  }

  Future<List<_MemoryRowSummary>> _memoryRows({String? nodeId}) async {
    final List<_MemoryRowSummary> rows = <_MemoryRowSummary>[];
    for (final NodeModel node in nodes) {
      if (nodeId != null && node.id != nodeId) {
        continue;
      }
      final Set<String> scopedDatasetIds = nodeId == null
          ? const <String>{}
          : <String>{
              ..._datasetsForNode(node),
              ..._availableDatasetIdsForNode(node),
              ...?_nodeRamSnapshots[node.id]?.keys,
              ...?_nodeDiskSnapshotIds[node.id],
            };
      for (final Dataset dataset in datasets.values) {
        if (nodeId != null && !scopedDatasetIds.contains(dataset.id)) {
          continue;
        }
        final bool inRam =
            _nodeRamSnapshots[node.id]?.containsKey(dataset.id) == true;
        bool onDisk =
            _nodeDiskSnapshotIds[node.id]?.contains(dataset.id) == true;
        final DatasetState state =
            node.datasetStates[dataset.id] ?? DatasetState.notReady;
        final bool hasRun =
            state == DatasetState.done ||
            state == DatasetState.partial ||
            state == DatasetState.stale;
        if (nodeId == null && !inRam && !onDisk && !hasRun) {
          continue;
        }
        if (!onDisk && supportsNodeSnapshotDiskStore) {
          onDisk = await hasNodeSnapshotOnDisk(
            nodeId: node.id,
            datasetId: dataset.id,
          );
          if (onDisk) {
            _nodeDiskSnapshotIds
                .putIfAbsent(node.id, () => <String>{})
                .add(dataset.id);
          }
        }
        final DatasetArtifactSnapshot? snapshot =
            _nodeRamSnapshots[node.id]?[dataset.id];
        rows.add(
          _MemoryRowSummary(
            nodeId: node.id,
            nodeDescriptor: _nodeDescriptor(node),
            nodeTitle: node.title,
            datasetId: dataset.id,
            datasetLabel: dataset.label,
            processingLabel: _datasetProcessingLabel(node, dataset.id),
            inRam: inRam,
            onDisk: onDisk,
            precisionLabel: _memoryPrecisionLabel(
              node: node,
              dataset: dataset,
              snapshot: snapshot,
            ),
          ),
        );
      }
    }
    rows.sort((_MemoryRowSummary a, _MemoryRowSummary b) {
      final int nodeCompare = a.nodeDescriptor.compareTo(b.nodeDescriptor);
      if (nodeCompare != 0) {
        return nodeCompare;
      }
      return a.datasetLabel.compareTo(b.datasetLabel);
    });
    return rows;
  }

  String _datasetProcessingLabel(NodeModel node, String datasetId) {
    if (_runActiveNodeId == node.id) {
      return 'Running';
    }
    if (_runWaitingNodeIds.contains(node.id)) {
      return 'Waiting';
    }
    if (isNodeMutationLocked(node.id)) {
      return 'Input locked';
    }
    final DatasetState state = _effectiveDatasetStateForNode(node, datasetId);
    switch (state) {
      case DatasetState.notReady:
        return 'Not ready';
      case DatasetState.ready:
        return 'Ready';
      case DatasetState.partial:
        return 'Partial';
      case DatasetState.done:
        return 'Done';
      case DatasetState.stale:
        return 'Stale';
    }
  }

  String _datasetStateLabel(DatasetState state) {
    switch (state) {
      case DatasetState.notReady:
        return 'not ready';
      case DatasetState.ready:
        return 'ready';
      case DatasetState.partial:
        return 'partial';
      case DatasetState.done:
        return 'done';
      case DatasetState.stale:
        return 'stale';
    }
  }

  String _memoryPrecisionLabel({
    required NodeModel node,
    required Dataset dataset,
    required DatasetArtifactSnapshot? snapshot,
  }) {
    final Set<BrainStoryArtifactKind> kinds = snapshot == null
        ? _artifactKindsForNodeOutputs(node, dataset)
        : _artifactKindsForSnapshotOutputs(node, snapshot);
    final bool hasNumeric = kinds.any((BrainStoryArtifactKind kind) {
      switch (kind) {
        case BrainStoryArtifactKind.timeSeries:
        case BrainStoryArtifactKind.segmentedTimeSeries:
        case BrainStoryArtifactKind.spectrum:
        case BrainStoryArtifactKind.fooofResult:
        case BrainStoryArtifactKind.bridgeDetection:
        case BrainStoryArtifactKind.timeFrequency:
        case BrainStoryArtifactKind.matrixTransformation:
        case BrainStoryArtifactKind.channelCoordinates:
          return true;
        case BrainStoryArtifactKind.markers:
        case BrainStoryArtifactKind.markerChange:
        case BrainStoryArtifactKind.featureTable:
          return false;
        default:
          return false;
      }
    });
    final bool hasMarkers = kinds.contains(BrainStoryArtifactKind.markers);
    final bool hasTable = kinds.contains(BrainStoryArtifactKind.featureTable);
    if (hasNumeric && (hasMarkers || hasTable)) {
      return '64-bit float + metadata';
    }
    if (hasNumeric) {
      return '64-bit float';
    }
    if (hasTable) {
      return 'Text table';
    }
    if (hasMarkers) {
      return 'Marker metadata';
    }
    return 'Pending';
  }

  Future<bool> _nodeHasLoadableDiskCache({
    required NodeModel node,
    required Set<String> datasetIds,
  }) async {
    if (!supportsNodeSnapshotDiskStore || datasetIds.isEmpty) {
      return false;
    }
    for (final Dataset dataset in _datasetsForAction(datasetIds)) {
      final bool inRam =
          _nodeRamSnapshots[node.id]?.containsKey(dataset.id) == true;
      if (inRam) {
        continue;
      }
      final bool onDisk = await hasNodeSnapshotOnDisk(
        nodeId: node.id,
        datasetId: dataset.id,
      );
      if (onDisk) {
        _nodeDiskSnapshotIds
            .putIfAbsent(node.id, () => <String>{})
            .add(dataset.id);
        return true;
      }
    }
    return false;
  }

  Future<String> _saveNodeSnapshotsToDisk({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    if (!supportsNodeSnapshotDiskStore) {
      return 'Disk cache is not available on this platform.';
    }

    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to save for ${node.title}.';
    }

    int savedCount = 0;
    String? lastPath;
    for (final Dataset dataset in selectedDatasets) {
      DatasetArtifactSnapshot? snapshot =
          _nodeRamSnapshots[node.id]?[dataset.id];
      if (snapshot == null || snapshot.isEmpty) {
        continue;
      }
      _nodeRamSnapshots.putIfAbsent(
        node.id,
        () => <String, DatasetArtifactSnapshot>{},
      )[dataset.id] = snapshot;
      lastPath = await saveNodeSnapshotJson(
        nodeId: node.id,
        datasetId: dataset.id,
        jsonPayload: jsonEncode(snapshot.toJson()),
      );
      _saveSnapshotMetadata(node.id, dataset);
      _nodeDiskSnapshotIds
          .putIfAbsent(node.id, () => <String>{})
          .add(dataset.id);
      savedCount++;
    }

    if (savedCount == 0) {
      return 'Nothing is currently loaded in RAM for ${node.title}.';
    }

    update();
    return lastPath == null
        ? 'Saved $savedCount cached output(s) for ${node.title}.'
        : 'Saved $savedCount cached output(s) for ${node.title} to $lastPath.';
  }

  Future<String> _loadNodeSnapshotsToRam({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to load for ${node.title}.';
    }

    int loadedCount = 0;
    for (final Dataset dataset in selectedDatasets) {
      final String? jsonPayload = await loadNodeSnapshotJson(
        nodeId: node.id,
        datasetId: dataset.id,
      );
      if (jsonPayload == null || jsonPayload.trim().isEmpty) {
        continue;
      }
      final Map<String, dynamic> decoded = Map<String, dynamic>.from(
        jsonDecode(jsonPayload) as Map,
      );
      final DatasetArtifactSnapshot snapshot =
          await _applyStoredSnapshotMetadata(
            node.id,
            dataset.id,
            DatasetArtifactSnapshot.fromJson(decoded),
          );
      if (snapshot.isEmpty) {
        continue;
      }
      _nodeRamSnapshots.putIfAbsent(
        node.id,
        () => <String, DatasetArtifactSnapshot>{},
      )[dataset.id] = snapshot;
      _nodeDiskSnapshotIds
          .putIfAbsent(node.id, () => <String>{})
          .add(dataset.id);
      snapshot.applyToDataset(dataset);
      node.datasetStates[dataset.id] = DatasetState.done;
      _markImmediateChildrenStale(node.id, dataset.id);
      loadedCount++;
    }

    if (loadedCount == 0) {
      return 'No disk cache found yet for ${node.title}.';
    }

    update();
    return 'Loaded $loadedCount cached output(s) into RAM for ${node.title}.';
  }

  Future<String> _releaseNodeSnapshotsFromRam({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to release for ${node.title}.';
    }

    int releasedCount = 0;
    final Map<String, DatasetArtifactSnapshot>? snapshots =
        _nodeRamSnapshots[node.id];
    for (final Dataset dataset in selectedDatasets) {
      bool changed = false;
      if (snapshots?.remove(dataset.id) != null) {
        changed = true;
      }
      _releaseActiveDatasetArtifactsProducedBy(node, dataset);
      if (node.datasetStates[dataset.id] == DatasetState.done) {
        node.datasetStates[dataset.id] = _unmaterializedStateForNodeDataset(
          node,
          dataset.id,
        );
        _markImmediateChildrenStale(node.id, dataset.id);
        changed = true;
      }
      if (changed) {
        releasedCount++;
      }
    }
    if (snapshots != null && snapshots.isEmpty) {
      _nodeRamSnapshots.remove(node.id);
    }

    update();
    return releasedCount == 0
        ? 'No RAM cache was being held for ${node.title}.'
        : 'Released $releasedCount in-memory cached output(s) for ${node.title}.';
  }

  Future<String> _deleteNodeSnapshotsFromDisk({
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    if (!supportsNodeSnapshotDiskStore) {
      return 'Disk cache is not available on this platform.';
    }

    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to purge for ${node.title}.';
    }

    int deletedCount = 0;
    for (final Dataset dataset in selectedDatasets) {
      final bool exists = await hasNodeSnapshotOnDisk(
        nodeId: node.id,
        datasetId: dataset.id,
      );
      if (!exists) {
        continue;
      }
      await deleteNodeSnapshotFromDisk(nodeId: node.id, datasetId: dataset.id);
      _nodeDiskSnapshotIds[node.id]?.remove(dataset.id);
      if (_nodeDiskSnapshotIds[node.id]?.isEmpty ?? false) {
        _nodeDiskSnapshotIds.remove(node.id);
      }
      deletedCount++;
    }

    update();
    return deletedCount == 0
        ? 'Nothing was saved to disk yet for ${node.title}.'
        : 'Purged $deletedCount disk cache file(s) for ${node.title}.';
  }

  Future<String> _clearNodeResults({
    required NodeModel node,
    required Map<String, dynamic> params,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final List<Dataset> selectedDatasets = _datasetsForAction(datasetIds);
    if (selectedDatasets.isEmpty) {
      return 'No checked datasets to clear for ${node.title}.';
    }

    final NodeModel configuredNode = _nodeWithParams(node, params);
    final Set<String> availableDatasetIds = _availableDatasetIdsForNode(
      configuredNode,
    );
    int clearedCount = 0;

    for (final Dataset dataset in selectedDatasets) {
      bool changed = false;
      final Map<String, DatasetArtifactSnapshot>? snapshots =
          _nodeRamSnapshots[node.id];
      if (snapshots?.remove(dataset.id) != null) {
        changed = true;
      }
      if (snapshots != null && snapshots.isEmpty) {
        _nodeRamSnapshots.remove(node.id);
      }
      if (supportsNodeSnapshotDiskStore) {
        final bool exists = await hasNodeSnapshotOnDisk(
          nodeId: node.id,
          datasetId: dataset.id,
        );
        if (exists) {
          await deleteNodeSnapshotFromDisk(
            nodeId: node.id,
            datasetId: dataset.id,
          );
          _nodeDiskSnapshotIds[node.id]?.remove(dataset.id);
          if (_nodeDiskSnapshotIds[node.id]?.isEmpty ?? false) {
            _nodeDiskSnapshotIds.remove(node.id);
          }
          changed = true;
        }
      }

      final DatasetState nextState = availableDatasetIds.contains(dataset.id)
          ? DatasetState.ready
          : DatasetState.notReady;
      if (node.datasetStates[dataset.id] != nextState) {
        node.datasetStates[dataset.id] = nextState;
        changed = true;
      }
      _markImmediateChildrenStale(node.id, dataset.id);
      if (changed) {
        clearedCount++;
      }
    }

    update();
    return clearedCount == 0
        ? 'There were no results to clear for ${node.title}.'
        : 'Cleared $clearedCount result set(s) for ${node.title}.';
  }

  Future<void> _restoreMaterializedOutputIfNeeded(
    NodeModel node,
    Dataset dataset,
  ) async {
    final Dataset view = await materializedDatasetViewForNode(node.id, dataset);
    _replaceDatasetRam(dataset, view);
  }

  Future<bool> promptLoadFromDiskInsteadOfRun({
    required BuildContext context,
    required NodeModel node,
    required Set<String> datasetIds,
    required VoidCallback update,
  }) async {
    final bool hasLoadableCache = await _nodeHasLoadableDiskCache(
      node: node,
      datasetIds: datasetIds,
    );
    if (!hasLoadableCache || !context.mounted) {
      return false;
    }
    final bool? loadInstead = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Load from disk instead?'),
          content: Text(
            'BrainStory found cached output for ${node.title} on disk. Loading it is likely faster than recomputing it.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Run anyway'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Load from disk'),
            ),
          ],
        );
      },
    );
    if (loadInstead != true) {
      return false;
    }
    final String message = await _loadNodeSnapshotsToRam(
      node: node,
      datasetIds: datasetIds,
      update: update,
    );
    if (context.mounted) {
      _showStatusSnackBar(context, message);
    }
    return true;
  }

  Future<void> _restoreUpstreamInputForRun(
    NodeModel node,
    Dataset dataset,
  ) async {
    if (node.type is ImportNodeType || node.type is VisualizationNodeType) {
      return;
    }

    final List<NodeModel> parents = _immediateParents(node.id);
    if (parents.isEmpty) {
      return;
    }

    final Set<String> upstreamIds = _collectAncestorsInclusive(node.id)
      ..remove(node.id);
    final Dataset view = _datasetShell(dataset);
    bool appliedAnySnapshot = false;
    for (final NodeModel upstreamNode in _orderedNodes(upstreamIds)) {
      if (upstreamNode.datasetStates[dataset.id] != DatasetState.done) {
        continue;
      }
      final DatasetArtifactSnapshot? snapshot =
          await _loadSnapshotForNodeDataset(upstreamNode.id, dataset.id);
      if (snapshot != null && !snapshot.isEmpty) {
        DatasetArtifactSnapshot scopedSnapshot = _snapshotScopedToNodeOutputs(
          upstreamNode,
          snapshot,
        );
        if (_shouldSuppressPsdSegmentSnapshot(node, upstreamNode)) {
          scopedSnapshot = _withoutSegmentedTimeSeries(scopedSnapshot);
        }
        scopedSnapshot.applyToDataset(view);
        appliedAnySnapshot = true;
        continue;
      }
      if (upstreamNode.type is ImportNodeType && !appliedAnySnapshot) {
        _applyLiveSourceArtifacts(view, dataset);
      }
    }
    if (appliedAnySnapshot || view.timeSeries != null) {
      _replaceDatasetRam(dataset, view);
    }
  }

  Future<void> _restoreStaleNodeOutputForRun(
    NodeModel node,
    Dataset dataset,
  ) async {
    if (node.type is EditChannelsNodeType ||
        node.type is EditChannelsAndMarkersNodeType) {
      return;
    }
    final DatasetArtifactSnapshot? snapshot = await _loadSnapshotForNodeDataset(
      node.id,
      dataset.id,
    );
    if (snapshot == null || snapshot.isEmpty) {
      return;
    }
    _snapshotScopedToNodeOutputs(node, snapshot).applyToDataset(dataset);
  }

  bool _shouldSuppressPsdSegmentSnapshot(
    NodeModel node,
    NodeModel upstreamNode,
  ) {
    if (!_psdUsesParentSegments(node) ||
        upstreamNode.type is! SegmentationNodeType) {
      return false;
    }
    final String? selectedSegmentParentId = _selectedPsdSegmentParentId(node);
    return selectedSegmentParentId != null &&
        upstreamNode.id != selectedSegmentParentId;
  }

  DatasetArtifactSnapshot _withoutSegmentedTimeSeries(
    DatasetArtifactSnapshot snapshot,
  ) {
    final Set<BrainStoryArtifactKind> includedKinds =
        Set<BrainStoryArtifactKind>.from(
          snapshot.includedKinds ??
              <BrainStoryArtifactKind>{
                if (snapshot.timeSeries != null)
                  BrainStoryArtifactKind.timeSeries,
                if (snapshot.spectrum != null) BrainStoryArtifactKind.spectrum,
                if (snapshot.fooofResult != null)
                  BrainStoryArtifactKind.fooofResult,
                if (snapshot.featureTable != null)
                  BrainStoryArtifactKind.featureTable,
                if (snapshot.bridgeDetection != null)
                  BrainStoryArtifactKind.bridgeDetection,
                if (snapshot.timeFrequency != null)
                  BrainStoryArtifactKind.timeFrequency,
                if (snapshot.matrixTransformation != null)
                  BrainStoryArtifactKind.matrixTransformation,
                if (snapshot.markers != null) BrainStoryArtifactKind.markers,
                ...snapshot.artifactIdentities.keys,
              },
        )..remove(BrainStoryArtifactKind.segmentedTimeSeries);
    return DatasetArtifactSnapshot(
      datasetLabel: snapshot.datasetLabel,
      timeSeries: snapshot.timeSeries,
      spectrum: snapshot.spectrum,
      fooofResult: snapshot.fooofResult,
      featureTable: snapshot.featureTable,
      bridgeDetection: snapshot.bridgeDetection,
      timeFrequency: snapshot.timeFrequency,
      matrixTransformation: snapshot.matrixTransformation,
      markers: snapshot.markers,
      artifactIdentities: Map<BrainStoryArtifactKind, ArtifactIdentity>.from(
        snapshot.artifactIdentities,
      )..remove(BrainStoryArtifactKind.segmentedTimeSeries),
      includedKinds: includedKinds,
    );
  }

  void _replaceDatasetRam(Dataset target, Dataset source) {
    target.ram
      ..clear()
      ..addAll(source.ram);
  }

  DatasetArtifactSnapshot _snapshotScopedToNodeOutputs(
    NodeModel node,
    DatasetArtifactSnapshot snapshot,
  ) {
    if (snapshot.includedKinds != null) {
      return snapshot;
    }
    final Set<BrainStoryArtifactKind> kinds = _artifactKindsForSnapshotOutputs(
      node,
      snapshot,
    );
    if (kinds.isEmpty) {
      return snapshot;
    }
    return DatasetArtifactSnapshot(
      datasetLabel: snapshot.datasetLabel,
      timeSeries: kinds.contains(BrainStoryArtifactKind.timeSeries)
          ? snapshot.timeSeries
          : null,
      segmentedTimeSeries:
          kinds.contains(BrainStoryArtifactKind.segmentedTimeSeries)
          ? snapshot.segmentedTimeSeries
          : null,
      spectrum: kinds.contains(BrainStoryArtifactKind.spectrum)
          ? snapshot.spectrum
          : null,
      fooofResult: kinds.contains(BrainStoryArtifactKind.fooofResult)
          ? snapshot.fooofResult
          : null,
      featureTable: kinds.contains(BrainStoryArtifactKind.featureTable)
          ? snapshot.featureTable
          : null,
      bridgeDetection: kinds.contains(BrainStoryArtifactKind.bridgeDetection)
          ? snapshot.bridgeDetection
          : null,
      timeFrequency: kinds.contains(BrainStoryArtifactKind.timeFrequency)
          ? snapshot.timeFrequency
          : null,
      matrixTransformation:
          kinds.contains(BrainStoryArtifactKind.matrixTransformation)
          ? snapshot.matrixTransformation
          : null,
      markers: kinds.contains(BrainStoryArtifactKind.markers)
          ? snapshot.markers ??
                snapshot.timeSeries?.markers
                    .map(
                      (TimeMarker marker) =>
                          TimeMarker.fromJson(marker.toJson()),
                    )
                    .toList(growable: false)
          : null,
      artifactIdentities:
          Map<BrainStoryArtifactKind, ArtifactIdentity>.fromEntries(
            snapshot.artifactIdentities.entries.where(
              (MapEntry<BrainStoryArtifactKind, ArtifactIdentity> entry) =>
                  kinds.contains(entry.key),
            ),
          ),
      includedKinds: kinds,
    );
  }

  Future<DatasetArtifactSnapshot?> _loadSnapshotForNodeDataset(
    String nodeId,
    String datasetId,
  ) async {
    final DatasetArtifactSnapshot? ramSnapshot =
        _nodeRamSnapshots[nodeId]?[datasetId];
    if (ramSnapshot != null && !ramSnapshot.isEmpty) {
      return ramSnapshot;
    }

    final String? jsonPayload = await loadNodeSnapshotJson(
      nodeId: nodeId,
      datasetId: datasetId,
    );
    if (jsonPayload == null || jsonPayload.trim().isEmpty) {
      return null;
    }

    final Map<String, dynamic> decoded = Map<String, dynamic>.from(
      jsonDecode(jsonPayload) as Map,
    );
    final DatasetArtifactSnapshot snapshot = await _applyStoredSnapshotMetadata(
      nodeId,
      datasetId,
      DatasetArtifactSnapshot.fromJson(decoded),
    );
    if (snapshot.isEmpty) {
      return null;
    }
    _nodeDiskSnapshotIds.putIfAbsent(nodeId, () => <String>{}).add(datasetId);
    _nodeRamSnapshots.putIfAbsent(
      nodeId,
      () => <String, DatasetArtifactSnapshot>{},
    )[datasetId] = snapshot;
    return snapshot;
  }

  void _saveSnapshotMetadata(String nodeId, Dataset dataset) {
    saveNodeSnapshotMetadataJsonSync(
      nodeId: nodeId,
      datasetId: dataset.id,
      jsonPayload: jsonEncode(<String, dynamic>{'datasetLabel': dataset.label}),
    );
  }

  Future<DatasetArtifactSnapshot> _applyStoredSnapshotMetadata(
    String nodeId,
    String datasetId,
    DatasetArtifactSnapshot snapshot,
  ) async {
    final String? metadataJson = await loadNodeSnapshotMetadataJson(
      nodeId: nodeId,
      datasetId: datasetId,
    );
    if (metadataJson == null || metadataJson.trim().isEmpty) {
      return snapshot;
    }
    try {
      final Map<String, dynamic> metadata = Map<String, dynamic>.from(
        jsonDecode(metadataJson) as Map,
      );
      final String? label = metadata['datasetLabel']?.toString();
      return label == null ? snapshot : snapshot.withDatasetLabel(label);
    } catch (_) {
      return snapshot;
    }
  }

  Future<void> _refreshDiskSnapshotFlagsForLoadedProject() async {
    _nodeRamSnapshots.clear();
    _nodeDiskSnapshotIds.clear();
    if (!supportsNodeSnapshotDiskStore) {
      return;
    }
    for (final NodeModel node in nodes) {
      for (final Dataset dataset in datasets.values) {
        final bool exists = await hasNodeSnapshotOnDisk(
          nodeId: node.id,
          datasetId: dataset.id,
        );
        if (exists) {
          _nodeDiskSnapshotIds
              .putIfAbsent(node.id, () => <String>{})
              .add(dataset.id);
        }
      }
    }
  }

  void _normalizeNodeStatesAfterProjectLoad() {
    for (final NodeModel node in nodes) {
      for (final Dataset dataset in datasets.values) {
        final DatasetState rawState =
            node.datasetStates[dataset.id] ?? DatasetState.notReady;
        if (rawState == DatasetState.notReady) {
          node.datasetStates[dataset.id] = DatasetState.notReady;
          continue;
        }
        node.datasetStates[dataset.id] = DatasetState.ready;
      }
    }
  }

  DatasetState _effectiveDatasetStateForNode(NodeModel node, String datasetId) {
    final DatasetState rawState =
        node.datasetStates[datasetId] ?? DatasetState.notReady;
    if (rawState != DatasetState.stale) {
      return rawState;
    }

    final bool hasResult =
        _nodeRamSnapshots[node.id]?.containsKey(datasetId) == true ||
        _nodeDiskSnapshotIds[node.id]?.contains(datasetId) == true;
    if (hasResult) {
      return DatasetState.stale;
    }

    return _availableDatasetIdsForNode(node).contains(datasetId)
        ? DatasetState.ready
        : DatasetState.notReady;
  }

  NodeModel _nodeWithParams(NodeModel node, Map<String, dynamic> params) {
    return NodeModel(
      id: node.id,
      type: node.type,
      position: node.position,
      params: params,
      markerChange: node.markerChange,
    )..datasetStates.addAll(node.datasetStates);
  }

  List<Dataset> _datasetsForAction(Set<String> datasetIds) {
    return datasets.values
        .where((Dataset dataset) => datasetIds.contains(dataset.id))
        .toList(growable: false);
  }

  NodeStoragePolicy _storagePolicyForNode(NodeModel node) {
    final String? rawPolicy = node.params['storagePolicy']?.toString();
    if (rawPolicy == null || rawPolicy.trim().isEmpty) {
      return node.type.defaultStoragePolicy;
    }
    final NodeStoragePolicy policy =
        NodeStoragePolicyPresentation.fromWireValue(
          node.params['storagePolicy']?.toString(),
        );
    return policy == NodeStoragePolicy.automatic
        ? node.type.defaultStoragePolicy
        : policy;
  }

  NodeType? _nodeTypeByTitle(String title) {
    final String normalizedTitle = switch (title) {
      'Add/Remove Markers' => 'Edit Markers',
      _ => title,
    };
    for (final NodeType type in availableNodes) {
      if (type.title == normalizedTitle) {
        return type;
      }
    }
    if (normalizedTitle == 'Channel Coordinates') {
      return ChannelCoordinatesNodeType();
    }
    if (normalizedTitle == 'Interactive Artifact Detection') {
      return InteractiveArtifactDetectionNodeType();
    }
    if (normalizedTitle == 'Average Spectra') {
      return PSDAverageNodeType();
    }
    return null;
  }

  DatasetState _datasetStateFromName(String? stateName) {
    for (final DatasetState state in DatasetState.values) {
      if (state.name == stateName) {
        return state;
      }
    }
    return DatasetState.notReady;
  }

  Future<void> _yieldToUi({int extraDelayMs = 12}) async {
    if (!runUiYieldsEnabled) {
      await Future<void>.delayed(Duration.zero);
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration(milliseconds: extraDelayMs));
  }

  Color _nodeColor(NodeModel node) {
    return node.type.category.color;
  }

  bool _isHighlighted(NodeModel node) {
    return node.id == selectedNodeId ||
        selectedNodeIds.contains(node.id) ||
        node.id == keyboardFocusedNodeId;
  }

  Color _nodeHighlightColor(NodeModel node) {
    if (selectedNodeIds.length > 1 && selectedNodeIds.contains(node.id)) {
      return const Color(0xFF6DD3FF);
    }
    if (node.id == keyboardFocusedNodeId &&
        node.id != selectedNodeId &&
        !selectedNodeIds.contains(node.id)) {
      return const Color(0xFF24D6A7);
    }
    return const Color(0xFF958A52);
  }

  String? _statusLabel(NodeModel node) {
    if (_runActiveNodeId == node.id) {
      return 'Running';
    }
    if (_runWaitingNodeIds.contains(node.id)) {
      return 'Waiting';
    }
    if (isNodeMutationLocked(node.id)) {
      return 'Input locked';
    }
    switch (node.visualState) {
      case DatasetState.notReady:
        return null;
      case DatasetState.ready:
        return 'Ready';
      case DatasetState.partial:
        return 'Partial';
      case DatasetState.done:
        return 'Done';
      case DatasetState.stale:
        return 'Stale';
    }
  }

  Offset _nextSpawnPosition() {
    if (nodes.isEmpty) {
      return snapToGrid(const Offset(100, 100));
    }

    NodeModel lowestNode = nodes.first;
    for (final NodeModel node in nodes.skip(1)) {
      if (node.position.dy > lowestNode.position.dy) {
        lowestNode = node;
      }
    }

    return snapToGrid(
      Offset(
        lowestNode.position.dx,
        lowestNode.position.dy + _cardHeight + _spawnGap,
      ),
    );
  }

  NodeModel? _markerEditSourceNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return null;
    }
    if (node.type is AddRemoveMarkersNodeType) {
      return node;
    }
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id)
          .where((NodeModel parent) => parent.outputPorts.isNotEmpty)
          .toList(growable: false);
      if (parents.isNotEmpty) {
        return parents.first;
      }
      return null;
    }
    return node;
  }

  NodeModel? _channelEditSourceNode(String nodeId) {
    final NodeModel? node = _findNode(nodeId);
    if (node == null) {
      return null;
    }
    if (node.type is EditChannelsNodeType) {
      return node;
    }
    if (node.type is VisualizationNodeType) {
      final List<NodeModel> parents = _immediateParents(node.id)
          .where((NodeModel parent) => parent.outputPorts.isNotEmpty)
          .toList(growable: false);
      if (parents.isNotEmpty) {
        return parents.first;
      }
      return null;
    }
    return node;
  }

  NodeModel _ensureMarkerNode(NodeModel sourceNode) {
    if (sourceNode.type is AddRemoveMarkersNodeType) {
      return sourceNode;
    }

    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != sourceNode.id) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child?.type is AddRemoveMarkersNodeType) {
        return child!;
      }
    }

    final NodeType markerType = AddRemoveMarkersNodeType();
    final NodeModel markerNode = _buildNode(
      type: markerType,
      position: snapToGrid(
        Offset(
          sourceNode.position.dx,
          sourceNode.position.dy + _cardHeight + _spawnGap,
        ),
      ),
      params: <String, dynamic>{
        ...markerType.defaultParams,
        if (sourceNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            sourceNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(markerNode);

    int? fromPortIndex;
    int? toPortIndex;
    for (
      int candidateFromPort = 0;
      candidateFromPort < sourceNode.outputPorts.length;
      candidateFromPort++
    ) {
      final int? candidateToPort = _matchingInputPortForOutputPort(
        sourceNode,
        candidateFromPort,
        markerNode,
      );
      if (candidateToPort != null) {
        fromPortIndex = candidateFromPort;
        toPortIndex = candidateToPort;
        break;
      }
    }
    if (fromPortIndex != null && toPortIndex != null) {
      connections.add(<String, dynamic>{
        'fromNode': sourceNode.id,
        'fromPort': fromPortIndex,
        'toNode': markerNode.id,
        'toPort': toPortIndex,
      });
    }

    return markerNode;
  }

  NodeModel _ensureChannelEditNode(NodeModel sourceNode) {
    if (sourceNode.type is EditChannelsNodeType) {
      return sourceNode;
    }

    for (final Map<String, dynamic> connection in connections) {
      if (connection['fromNode'] != sourceNode.id) {
        continue;
      }
      final NodeModel? child = _findNode(connection['toNode'] as String);
      if (child?.type is EditChannelsNodeType) {
        return child!;
      }
    }

    final NodeType channelType = EditChannelsNodeType();
    final NodeModel channelNode = _buildNode(
      type: channelType,
      position: _nearestAvailablePosition(
        Offset(
          sourceNode.position.dx,
          sourceNode.position.dy + _cardHeight + _spawnGap,
        ),
      ),
      params: <String, dynamic>{
        ...channelType.defaultParams,
        if (sourceNode.params['selectedDatasetIds'] != null)
          'selectedDatasetIds': List<dynamic>.from(
            sourceNode.params['selectedDatasetIds'] as List<dynamic>,
          ),
      },
    );
    nodes.add(channelNode);

    int? fromPortIndex;
    int? toPortIndex;
    for (
      int candidateFromPort = 0;
      candidateFromPort < sourceNode.outputPorts.length;
      candidateFromPort++
    ) {
      final int? candidateToPort = _matchingInputPortForOutputPort(
        sourceNode,
        candidateFromPort,
        channelNode,
      );
      if (candidateToPort != null) {
        fromPortIndex = candidateFromPort;
        toPortIndex = candidateToPort;
        break;
      }
    }
    if (fromPortIndex != null && toPortIndex != null) {
      connections.add(<String, dynamic>{
        'fromNode': sourceNode.id,
        'fromPort': fromPortIndex,
        'toNode': channelNode.id,
        'toPort': toPortIndex,
      });
    }

    return channelNode;
  }

  double _snapCoordinate(double value, double gridSize) {
    return math
        .max(0, (value / gridSize).roundToDouble() * gridSize)
        .toDouble();
  }

  Offset _nearestAvailablePosition(Offset desired, {String? movingNodeId}) {
    Offset candidate = snapToGrid(desired);
    if (!_positionOverlapsAnyNode(candidate, movingNodeId: movingNodeId)) {
      return candidate;
    }

    final int baseColumn = (candidate.dx / _gridWidth).round();
    final int baseRow = (candidate.dy / _gridHeight).round();

    for (int radius = 1; radius <= 24; radius++) {
      for (int rowOffset = -radius; rowOffset <= radius; rowOffset++) {
        for (
          int columnOffset = -radius;
          columnOffset <= radius;
          columnOffset++
        ) {
          if (rowOffset.abs() != radius && columnOffset.abs() != radius) {
            continue;
          }
          final Offset probe = Offset(
            math.max(0, (baseColumn + columnOffset) * _gridWidth).toDouble(),
            math.max(0, (baseRow + rowOffset) * _gridHeight).toDouble(),
          );
          if (!_positionOverlapsAnyNode(probe, movingNodeId: movingNodeId)) {
            return probe;
          }
        }
      }
    }

    return candidate;
  }

  void moveNodeOrSelection(NodeModel draggedNode, Offset targetPosition) {
    final CanvasNodeGroup? nodeGroup = _groupForNode(draggedNode.id);
    final bool movingSelection =
        selectedNodeIds.contains(draggedNode.id) && selectedNodeIds.length > 1;
    if (!movingSelection && nodeGroup == null) {
      final Offset nextPosition = _nearestAvailablePosition(
        targetPosition,
        movingNodeId: draggedNode.id,
      );
      final bool inserted = _insertNodeIntoConnectionIfPossible(
        draggedNode,
        nextPosition,
      );
      if (!inserted && nextPosition != draggedNode.position) {
        _recordUndo('move node');
        draggedNode.position = nextPosition;
      }
      selectedNodeId = draggedNode.id;
      selectedNodeIds
        ..clear()
        ..add(draggedNode.id);
      return;
    }

    final Set<String> movingIds = movingSelection
        ? Set<String>.from(selectedNodeIds)
        : Set<String>.from(nodeGroup!.nodeIds);
    final Offset snappedTarget = snapToGrid(targetPosition);
    final Offset delta = snappedTarget - draggedNode.position;
    if (delta == Offset.zero) {
      return;
    }

    final Map<String, Offset> nextPositions = <String, Offset>{};
    for (final NodeModel node in nodes) {
      if (!movingIds.contains(node.id)) {
        continue;
      }
      nextPositions[node.id] = Offset(
        math.max(0, node.position.dx + delta.dx),
        math.max(0, node.position.dy + delta.dy),
      );
    }

    if (_groupMoveOverlapsAnyNode(nextPositions, movingIds)) {
      return;
    }

    _recordUndo(nodeGroup == null ? 'move nodes' : 'move node group');
    for (final NodeModel node in nodes) {
      final Offset? nextPosition = nextPositions[node.id];
      if (nextPosition != null) {
        node.position = nextPosition;
      }
    }
    selectedNodeId = draggedNode.id;
  }

  Future<void> showMemoryManagerDialog(
    BuildContext context, {
    required VoidCallback update,
    NodeModel? node,
  }) async {
    Future<List<_MemoryRowSummary>> loadRows() => _memoryRows(nodeId: node?.id);
    final String title = node == null
        ? 'Memory'
        : 'Memory: ${_nodeDescriptor(node)} ${node.title}';
    final String emptyMessage = node == null
        ? 'No node outputs are available yet.'
        : 'No datasets are available for this node yet.';
    final String helperText = node == null
        ? 'See what each node is holding in RAM or on disk, and move cached outputs around without opening each node one-by-one.'
        : 'Manage RAM and disk cache for this node only. Disabled buttons mean that dataset has nothing to load, save, or purge right now.';

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        Future<List<_MemoryRowSummary>> rowsFuture = loadRows();

        Future<void> refresh(StateSetter setDialogState) async {
          setDialogState(() {
            rowsFuture = loadRows();
          });
          update();
        }

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey.shade900,
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: node == null ? 980 : 820,
                height: 560,
                child: FutureBuilder<List<_MemoryRowSummary>>(
                  future: rowsFuture,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<List<_MemoryRowSummary>> snapshot,
                      ) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final List<_MemoryRowSummary> rows =
                            snapshot.data ?? const <_MemoryRowSummary>[];
                        if (rows.isEmpty) {
                          return Center(
                            child: Text(
                              emptyMessage,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              helperText,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 18,
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                                itemBuilder: (BuildContext context, int index) {
                                  final _MemoryRowSummary row = rows[index];
                                  return _MemoryRowWidget(
                                    row: row,
                                    supportsDisk: supportsNodeSnapshotDiskStore,
                                    onLoadFromDisk: row.onDisk
                                        ? () async {
                                            final NodeModel? node = _findNode(
                                              row.nodeId,
                                            );
                                            if (node == null) return;
                                            final String message =
                                                await _loadNodeSnapshotsToRam(
                                                  node: node,
                                                  datasetIds: <String>{
                                                    row.datasetId,
                                                  },
                                                  update: update,
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(message),
                                                ),
                                              );
                                            }
                                            await refresh(setDialogState);
                                          }
                                        : null,
                                    onReleaseRam: row.inRam
                                        ? () async {
                                            final NodeModel? node = _findNode(
                                              row.nodeId,
                                            );
                                            if (node == null) return;
                                            final String message =
                                                await _releaseNodeSnapshotsFromRam(
                                                  node: node,
                                                  datasetIds: <String>{
                                                    row.datasetId,
                                                  },
                                                  update: update,
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(message),
                                                ),
                                              );
                                            }
                                            await refresh(setDialogState);
                                          }
                                        : null,
                                    onSaveToDisk:
                                        supportsNodeSnapshotDiskStore &&
                                            row.inRam &&
                                            !row.onDisk
                                        ? () async {
                                            final NodeModel? node = _findNode(
                                              row.nodeId,
                                            );
                                            if (node == null) return;
                                            final String message =
                                                await _saveNodeSnapshotsToDisk(
                                                  node: node,
                                                  datasetIds: <String>{
                                                    row.datasetId,
                                                  },
                                                  update: update,
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(message),
                                                ),
                                              );
                                            }
                                            await refresh(setDialogState);
                                          }
                                        : null,
                                    onPurgeDisk:
                                        supportsNodeSnapshotDiskStore &&
                                            row.onDisk
                                        ? () async {
                                            final NodeModel? node = _findNode(
                                              row.nodeId,
                                            );
                                            if (node == null) return;
                                            final String message =
                                                await _deleteNodeSnapshotsFromDisk(
                                                  node: node,
                                                  datasetIds: <String>{
                                                    row.datasetId,
                                                  },
                                                  update: update,
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(message),
                                                ),
                                              );
                                            }
                                            await refresh(setDialogState);
                                          }
                                        : null,
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _insertNodeIntoConnectionIfPossible(
    NodeModel draggedNode,
    Offset nextPosition,
  ) {
    final Rect nodeRect = Rect.fromLTWH(
      nextPosition.dx,
      nextPosition.dy,
      _cardWidth,
      _cardHeight,
    );
    final int? connectionIndex = _connectionIndexIntersectingRect(nodeRect);
    if (connectionIndex == null ||
        connectionIndex < 0 ||
        connectionIndex >= connections.length) {
      return false;
    }

    final Map<String, dynamic> connection = Map<String, dynamic>.from(
      connections[connectionIndex],
    );
    final String? fromNodeId = connection['fromNode']?.toString();
    final String? toNodeId = connection['toNode']?.toString();
    if (fromNodeId == null || toNodeId == null) {
      return false;
    }
    final NodeModel? fromNode = _findNode(fromNodeId);
    final NodeModel? toNode = _findNode(toNodeId);
    if (fromNode == null ||
        toNode == null ||
        fromNode.id == draggedNode.id ||
        toNode.id == draggedNode.id) {
      return false;
    }

    final _PortConnection? upstream = _firstMatchingPortConnection(
      fromNode,
      draggedNode,
    );
    final _PortConnection? downstream = _firstMatchingPortConnection(
      draggedNode,
      toNode,
    );
    if (upstream == null || downstream == null) {
      return false;
    }

    _recordUndo('insert node');
    draggedNode.position = nextPosition;
    connections.removeAt(connectionIndex);
    connections.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'fromNode': fromNode.id,
        'fromPort': upstream.fromPortIndex,
        'toNode': draggedNode.id,
        'toPort': upstream.toPortIndex,
      },
      <String, dynamic>{
        'fromNode': draggedNode.id,
        'fromPort': downstream.fromPortIndex,
        'toNode': toNode.id,
        'toPort': downstream.toPortIndex,
      },
    ]);

    for (final Dataset dataset in datasets.values) {
      _refreshDatasetAvailability(dataset.id);
      if (toNode.datasetStates[dataset.id] == DatasetState.done) {
        toNode.datasetStates[dataset.id] = DatasetState.stale;
      }
    }
    return true;
  }

  int? _connectionIndexIntersectingRect(Rect rect) {
    final List<Offset> probePoints = <Offset>[
      rect.center,
      rect.topCenter,
      rect.bottomCenter,
      rect.centerLeft,
      rect.centerRight,
    ];
    for (final Offset point in probePoints) {
      final int? index = _connectionIndexAt(point);
      if (index != null) {
        return index;
      }
    }
    const double corridorPadding = 20.0;
    final Offset center = rect.center;
    int? bestIndex;
    double? bestDistance;
    for (int index = connections.length - 1; index >= 0; index--) {
      final Map<String, dynamic> connection = connections[index];
      final NodeModel? fromNode = _findNode(connection['fromNode'] as String);
      final NodeModel? toNode = _findNode(connection['toNode'] as String);
      if (fromNode == null || toNode == null) {
        continue;
      }
      final int fromPort = (connection['fromPort'] as num?)?.toInt() ?? 0;
      final Offset start = _outputAnchor(
        fromNode,
        toNode,
        fromPortIndex: fromPort,
      );
      final Offset end = _inputAnchor(fromNode, toNode);
      final Rect corridor = Rect.fromLTRB(
        math.min(start.dx, end.dx) - corridorPadding,
        math.min(start.dy, end.dy) - corridorPadding,
        math.max(start.dx, end.dx) + corridorPadding,
        math.max(start.dy, end.dy) + corridorPadding,
      );
      if (!corridor.overlaps(rect)) {
        continue;
      }
      final bool preferVertical =
          (end.dy - start.dy).abs() >= (end.dx - start.dx).abs();
      final List<Offset> points = buildConnectionPolyline(
        start: start,
        end: end,
        preferVertical: preferVertical,
        gridWidth: _gridWidth,
        gridHeight: _gridHeight,
        obstacles: _connectionObstacles(fromNode, toNode),
      );
      double distance = double.infinity;
      for (int pointIndex = 1; pointIndex < points.length; pointIndex++) {
        distance = math.min(
          distance,
          _distanceToSegment(
            center,
            points[pointIndex - 1],
            points[pointIndex],
          ),
        );
      }
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  bool _groupMoveOverlapsAnyNode(
    Map<String, Offset> nextPositions,
    Set<String> movingIds,
  ) {
    for (final MapEntry<String, Offset> entry in nextPositions.entries) {
      final Rect probe = Rect.fromLTWH(
        entry.value.dx,
        entry.value.dy,
        _cardWidth,
        _cardHeight,
      );
      for (final NodeModel node in nodes) {
        if (movingIds.contains(node.id)) {
          continue;
        }
        final Rect occupied = Rect.fromLTWH(
          node.position.dx,
          node.position.dy,
          _cardWidth,
          _cardHeight,
        );
        if (probe.overlaps(occupied)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _positionOverlapsAnyNode(Offset position, {String? movingNodeId}) {
    final Rect probe = Rect.fromLTWH(
      position.dx,
      position.dy,
      _cardWidth,
      _cardHeight,
    );

    for (final NodeModel node in nodes) {
      if (node.id == movingNodeId) {
        continue;
      }
      final Rect occupied = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        _cardWidth,
        _cardHeight,
      );
      if (probe.overlaps(occupied)) {
        return true;
      }
    }
    return false;
  }

  String _nodeDescriptor(NodeModel node) {
    return '#${nodes.indexOf(node) + 1}${_branchLabelForNode(node.id)} ${node.title}';
  }

  String descriptorForNode(NodeModel node) => _nodeDescriptor(node);

  String _branchLabelForNode(String nodeId) {
    return _branchLabelsByNodeId()[nodeId] ?? 'A';
  }

  Map<String, String> _branchLabelsByNodeId() {
    final Map<String, String> labels = <String, String>{
      for (final NodeModel node in nodes) node.id: 'A',
    };
    final List<NodeModel> orderedNodes = _orderedNodes(
      nodes.map((NodeModel node) => node.id).toSet(),
    );

    for (final NodeModel mergeNode in orderedNodes) {
      final List<NodeModel> parents = _immediateParents(mergeNode.id);
      if (parents.length < 2) {
        continue;
      }

      final List<NodeModel> orderedParents = List<NodeModel>.from(parents)
        ..sort((NodeModel a, NodeModel b) {
          final int xCompare = a.position.dx.compareTo(b.position.dx);
          if (xCompare != 0) {
            return xCompare;
          }
          return nodes.indexOf(a).compareTo(nodes.indexOf(b));
        });
      final Map<String, Set<String>> ancestorSets = <String, Set<String>>{
        for (final NodeModel parent in orderedParents)
          parent.id: _collectAncestorsInclusive(parent.id),
      };
      Set<String>? commonAncestors;
      for (final Set<String> ancestorSet in ancestorSets.values) {
        commonAncestors = commonAncestors == null
            ? Set<String>.from(ancestorSet)
            : commonAncestors.intersection(ancestorSet);
      }
      final Set<String> shared = commonAncestors ?? const <String>{};

      for (int index = 0; index < orderedParents.length; index++) {
        final NodeModel parent = orderedParents[index];
        final String letter = _branchLetter(index);
        final Set<String> uniqueNodes = Set<String>.from(
          ancestorSets[parent.id] ?? const <String>{},
        )..removeAll(shared);
        for (final String uniqueNodeId in uniqueNodes) {
          labels[uniqueNodeId] = letter;
        }
      }
    }

    return labels;
  }

  String _branchLetter(int index) {
    if (index < 0) {
      return 'A';
    }
    String value = '';
    int current = index;
    do {
      value = String.fromCharCode(65 + (current % 26)) + value;
      current = (current ~/ 26) - 1;
    } while (current >= 0);
    return value;
  }

  int? _matchingInputPortForOutputPort(
    NodeModel fromNode,
    int fromPortIndex,
    NodeModel toNode,
  ) {
    final List<_EffectiveOutputPort> effectivePorts = _effectiveOutputPorts(
      fromNode,
    );
    final _EffectiveOutputPort? effectivePort = effectivePorts
        .cast<_EffectiveOutputPort?>()
        .firstWhere(
          (_EffectiveOutputPort? port) => port?.portIndex == fromPortIndex,
          orElse: () => null,
        );
    if (effectivePort == null) {
      return null;
    }
    final PortType outputType = effectivePort.port.type;
    for (
      int toPortIndex = 0;
      toPortIndex < toNode.inputPorts.length;
      toPortIndex++
    ) {
      if (toNode.inputPorts[toPortIndex].type == outputType) {
        return toPortIndex;
      }
    }
    return null;
  }

  _PortConnection? _firstMatchingPortConnection(
    NodeModel fromNode,
    NodeModel toNode,
  ) {
    final List<_EffectiveOutputPort> effectivePorts = _effectiveOutputPorts(
      fromNode,
    );
    for (final _EffectiveOutputPort outputPort in effectivePorts) {
      final int? toPortIndex = _matchingInputPortForOutputPort(
        fromNode,
        outputPort.portIndex,
        toNode,
      );
      if (toPortIndex != null) {
        return _PortConnection(
          fromPortIndex: outputPort.portIndex,
          toPortIndex: toPortIndex,
        );
      }
    }
    return null;
  }

  bool _isValidDownstreamPlacement(NodeModel fromNode, NodeModel toNode) {
    final double dx = toNode.position.dx - fromNode.position.dx;
    final double dy = toNode.position.dy - fromNode.position.dy;
    return dx >= 24 || dy >= 24;
  }

  Offset _outputAnchor(
    NodeModel fromNode,
    NodeModel toNode, {
    required int fromPortIndex,
  }) {
    if (_shouldUseVerticalAnchors(fromNode, toNode)) {
      return Offset(
        fromNode.position.dx + (_cardWidth / 2),
        fromNode.position.dy + _cardHeight,
      );
    }
    return Offset(
      fromNode.position.dx + _cardWidth,
      fromNode.position.dy + (_cardHeight / 2),
    );
  }

  Offset _inputAnchor(NodeModel fromNode, NodeModel toNode) {
    if (_shouldUseVerticalAnchors(fromNode, toNode)) {
      return Offset(toNode.position.dx + (_cardWidth / 2), toNode.position.dy);
    }
    return Offset(toNode.position.dx, toNode.position.dy + (_cardHeight / 2));
  }

  bool _shouldUseVerticalAnchors(NodeModel fromNode, NodeModel toNode) {
    final double dx = (toNode.position.dx - fromNode.position.dx).abs();
    final double dy = (toNode.position.dy - fromNode.position.dy).abs();
    return dy >= dx;
  }

  int? _connectionIndexAt(Offset point) {
    for (int index = connections.length - 1; index >= 0; index--) {
      final Map<String, dynamic> connection = connections[index];
      final NodeModel? fromNode = _findNode(connection['fromNode'] as String);
      final NodeModel? toNode = _findNode(connection['toNode'] as String);
      if (fromNode == null || toNode == null) {
        continue;
      }

      final int fromPort = (connection['fromPort'] as num?)?.toInt() ?? 0;
      final Offset start = _outputAnchor(
        fromNode,
        toNode,
        fromPortIndex: fromPort,
      );
      final Offset end = _inputAnchor(fromNode, toNode);
      if (_isPointNearConnection(
        point,
        start,
        end,
        obstacles: _connectionObstacles(fromNode, toNode),
      )) {
        return index;
      }
    }
    return null;
  }

  bool _isPointNearConnection(
    Offset point,
    Offset start,
    Offset end, {
    List<Rect> obstacles = const <Rect>[],
  }) {
    const double threshold = 12.0;
    final bool preferVertical =
        (end.dy - start.dy).abs() >= (end.dx - start.dx).abs();
    final List<Offset> points = buildConnectionPolyline(
      start: start,
      end: end,
      preferVertical: preferVertical,
      gridWidth: _gridWidth,
      gridHeight: _gridHeight,
      obstacles: obstacles,
    );

    for (int index = 1; index < points.length; index++) {
      final Offset previous = points[index - 1];
      final Offset current = points[index];
      if (_distanceToSegment(point, previous, current) <= threshold) {
        return true;
      }
    }
    return false;
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) {
      return (point - a).distance;
    }

    final double t =
        (((point.dx - a.dx) * dx) + ((point.dy - a.dy) * dy)) /
        ((dx * dx) + (dy * dy));
    final double clampedT = t.clamp(0.0, 1.0);
    final Offset projection = Offset(
      a.dx + (dx * clampedT),
      a.dy + (dy * clampedT),
    );
    return (point - projection).distance;
  }

  List<Rect> _connectionObstacles(NodeModel fromNode, NodeModel toNode) {
    return nodes
        .where(
          (NodeModel node) => node.id != fromNode.id && node.id != toNode.id,
        )
        .map((NodeModel node) {
          return Rect.fromLTWH(
            node.position.dx,
            node.position.dy,
            _cardWidth,
            _cardHeight,
          );
        })
        .toList(growable: false);
  }

  List<_EffectiveOutputPort> _effectiveOutputPorts(NodeModel node) {
    final List<_EffectiveOutputPort> ports = <_EffectiveOutputPort>[
      for (int index = 0; index < node.outputPorts.length; index++)
        _EffectiveOutputPort(portIndex: index, port: node.outputPorts[index]),
    ];
    final bool hasSignalLikeOutput = node.outputPorts.any(
      (PortSpec port) =>
          port.type == PortType.signal ||
          (port.type == PortType.metadata &&
              port.name.toLowerCase().contains('segments')),
    );
    final bool hasMarkerOutput = node.outputPorts.any(
      (PortSpec port) => port.type == PortType.markers,
    );
    if (hasSignalLikeOutput && !hasMarkerOutput) {
      ports.add(
        _EffectiveOutputPort(
          portIndex: node.outputPorts.length,
          port: const PortSpec(name: 'markers', type: PortType.markers),
        ),
      );
    }
    return ports;
  }

  bool _hasAnyDiskSnapshot(String nodeId) =>
      (_nodeDiskSnapshotIds[nodeId]?.isNotEmpty ?? false);

  DatasetArtifactSnapshot? _primarySnapshotForNode(NodeModel node) {
    final Map<String, DatasetArtifactSnapshot>? snapshots =
        _nodeRamSnapshots[node.id];
    if (snapshots == null || snapshots.isEmpty) {
      return null;
    }

    final List<Dataset> orderedDatasets = datasets.values.toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    for (final Dataset dataset in orderedDatasets) {
      final DatasetArtifactSnapshot? snapshot = snapshots[dataset.id];
      if (snapshot != null && !snapshot.isEmpty) {
        return snapshot;
      }
    }

    for (final DatasetArtifactSnapshot snapshot in snapshots.values) {
      if (!snapshot.isEmpty) {
        return snapshot;
      }
    }
    return null;
  }

  _OutputHandleDescriptor? _outputDescriptorForPort({
    required NodeModel node,
    required int portIndex,
    required PortSpec port,
    required DatasetArtifactSnapshot? snapshot,
  }) {
    final String portName = port.name.toLowerCase();
    switch (port.type) {
      case PortType.signal:
        if (portName.contains('psd') && snapshot?.spectrum != null) {
          final int segmentCount = snapshot!.spectrum!.segmentCount;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.spectrum,
            hasOutput: true,
            badgeText: segmentCount == 1 ? '' : '$segmentCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.timeSeries != null) {
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.timeSeries,
            hasOutput: true,
            badgeText: '',
            tooltip: '${port.name} output',
          );
        }
        return _OutputHandleDescriptor(
          kind: portName.contains('psd')
              ? _OutputHandleKind.spectrum
              : _OutputHandleKind.timeSeries,
          hasOutput: _hasAnyDiskSnapshot(node.id),
          badgeText: '',
          tooltip: '${port.name} output',
        );
      case PortType.markers:
        final int markerCount = snapshot?.timeSeries?.markers.length ?? 0;
        return _OutputHandleDescriptor(
          kind: _OutputHandleKind.markers,
          hasOutput:
              snapshot?.timeSeries != null || _hasAnyDiskSnapshot(node.id),
          badgeText: markerCount == 1 ? '' : '$markerCount',
          tooltip: '${port.name} output',
        );
      case PortType.metadata:
        if (portName.contains('segments') &&
            snapshot?.segmentedTimeSeries != null) {
          final int segmentCount = snapshot!.segmentedTimeSeries!.segmentCount;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.segments,
            hasOutput: true,
            badgeText: segmentCount == 1 ? '' : '$segmentCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.timeFrequency != null &&
            (portName.contains('time_frequency') ||
                portName.contains('time-frequency'))) {
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.timeFrequency,
            hasOutput: true,
            badgeText: '',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.featureTable != null) {
          final int rowCount = snapshot!.featureTable!.rows.length;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.table,
            hasOutput: true,
            badgeText: rowCount == 1 ? '' : '$rowCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.bridgeDetection != null) {
          final int frameCount = snapshot!.bridgeDetection!.frameCount;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.table,
            hasOutput: true,
            badgeText: frameCount == 1 ? '' : '$frameCount',
            tooltip: '${port.name} output',
          );
        }
        if (snapshot?.fooofResult != null) {
          final int peakCount = snapshot!.fooofResult!.peaks.length;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.table,
            hasOutput: true,
            badgeText: peakCount == 1 ? '' : '$peakCount',
            tooltip: '${port.name} output',
          );
        }
        return _OutputHandleDescriptor(
          kind: portName.contains('segments')
              ? _OutputHandleKind.segments
              : _OutputHandleKind.table,
          hasOutput: _hasAnyDiskSnapshot(node.id),
          badgeText: '',
          tooltip: '${port.name} output',
        );
      case PortType.matrixTransformation:
        if (snapshot?.matrixTransformation != null) {
          final int count =
              snapshot!.matrixTransformation!.componentLabels.isNotEmpty
              ? snapshot.matrixTransformation!.componentLabels.length
              : snapshot.matrixTransformation!.matrix.length;
          return _OutputHandleDescriptor(
            kind: _OutputHandleKind.matrix,
            hasOutput: true,
            badgeText: count == 1 ? '' : '$count',
            tooltip: '${port.name} output',
          );
        }
        return _OutputHandleDescriptor(
          kind: _OutputHandleKind.matrix,
          hasOutput: _hasAnyDiskSnapshot(node.id),
          badgeText: '',
          tooltip: '${port.name} output',
        );
    }
  }

  Color _outputColorForPort(NodeModel node, int portIndex) {
    final PortSpec port = _effectiveOutputPorts(node)
        .firstWhere((_EffectiveOutputPort item) => item.portIndex == portIndex)
        .port;
    final _OutputHandleDescriptor? descriptor = _outputDescriptorForPort(
      node: node,
      portIndex: portIndex,
      port: port,
      snapshot: _primarySnapshotForNode(node),
    );
    return _outputHandleColor(descriptor?.kind ?? _OutputHandleKind.other);
  }

  Color _outputHandleColor(_OutputHandleKind kind) {
    switch (kind) {
      case _OutputHandleKind.timeSeries:
        return const Color(0xFF4E9AF1);
      case _OutputHandleKind.spectrum:
        return const Color(0xFF8B5CF6);
      case _OutputHandleKind.timeFrequency:
        return const Color(0xFF14B8A6);
      case _OutputHandleKind.markers:
        return const Color(0xFFF59E0B);
      case _OutputHandleKind.segments:
        return const Color(0xFF06B6D4);
      case _OutputHandleKind.table:
        return const Color(0xFFFF6B6B);
      case _OutputHandleKind.matrix:
        return const Color(0xFFEC4899);
      case _OutputHandleKind.other:
        return Colors.white70;
    }
  }
}

class _OutputHandleDescriptor {
  const _OutputHandleDescriptor({
    required this.kind,
    required this.hasOutput,
    required this.badgeText,
    required this.tooltip,
  });

  final _OutputHandleKind kind;
  final bool hasOutput;
  final String badgeText;
  final String tooltip;
}

class _NodeCombinationPlan {
  const _NodeCombinationPlan({
    required this.upstream,
    required this.downstream,
    required this.type,
    required this.params,
  });

  final NodeModel upstream;
  final NodeModel downstream;
  final NodeType type;
  final Map<String, dynamic> params;
}

class _EffectiveOutputPort {
  const _EffectiveOutputPort({required this.portIndex, required this.port});

  final int portIndex;
  final PortSpec port;
}

class _PortConnection {
  const _PortConnection({
    required this.fromPortIndex,
    required this.toPortIndex,
  });

  final int fromPortIndex;
  final int toPortIndex;
}

class _CanvasNodeGroupOutline extends StatelessWidget {
  const _CanvasNodeGroupOutline({
    required this.rect,
    required this.label,
    required this.onUngroup,
  });

  final Rect rect;
  final String label;
  final VoidCallback onUngroup;

  @override
  Widget build(BuildContext context) {
    const Color outlineColor = Color(0xFF8B93A7);
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: outlineColor.withValues(alpha: 0.58),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 0,
            child: Container(
              height: 28,
              padding: const EdgeInsets.only(left: 7),
              color: const Color(0xFF15171C),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Tooltip(
                    message: 'Ungroup',
                    child: IconButton(
                      onPressed: onUngroup,
                      icon: const Icon(Icons.link_off, size: 15),
                      color: Colors.white60,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
