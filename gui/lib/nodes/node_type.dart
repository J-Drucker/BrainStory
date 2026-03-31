import 'dart:async';

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/dataset_state.dart';

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

class _NodeConfigDialog extends StatefulWidget {
  const _NodeConfigDialog({
    required this.title,
    required this.params,
    required this.datasets,
    required this.availableDatasetIds,
    required this.datasetSourceLabels,
    required this.processedDatasetStates,
    required this.processingSteps,
    required this.buildBody,
    required this.onSave,
    required this.onSaveAndRun,
    required this.datasetActions,
    required this.defaultStoragePolicy,
  });

  final String title;
  final Map<String, dynamic> params;
  final Map<String, Dataset> datasets;
  final Set<String> availableDatasetIds;
  final Map<String, List<String>> datasetSourceLabels;
  final Map<String, DatasetState> processedDatasetStates;
  final List<String> processingSteps;
  final Widget Function(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) buildBody;
  final void Function(Map<String, dynamic>) onSave;
  final FutureOr<void> Function(Map<String, dynamic>)? onSaveAndRun;
  final NodeDatasetActions? datasetActions;
  final NodeStoragePolicy defaultStoragePolicy;

  @override
  State<_NodeConfigDialog> createState() => _NodeConfigDialogState();
}

class _NodeConfigDialogState extends State<_NodeConfigDialog> {
  late Map<String, dynamic> localParams;
  bool _fullscreen = false;
  bool _runningDatasetAction = false;
  NodeDatasetStatusSnapshot? _statusSnapshot;
  String _datasetActionLabel = 'Working...';

  @override
  void initState() {
    super.initState();
    localParams = Map<String, dynamic>.from(widget.params);
    final Set<String> selectedDatasetIds = Set<String>.from(
      localParams['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[],
    ).where(widget.datasets.containsKey).toSet();

    if (selectedDatasetIds.isEmpty) {
      selectedDatasetIds.addAll(widget.availableDatasetIds);
    }

    localParams['selectedDatasetIds'] = selectedDatasetIds.toList();
    localParams.putIfAbsent(
      'storagePolicy',
      () => widget.defaultStoragePolicy.wireValue,
    );
    _statusSnapshot = NodeDatasetStatusSnapshot(
      availableDatasetIds: widget.availableDatasetIds,
      processedDatasetStates: widget.processedDatasetStates,
      ramLoadedDatasetIds: const <String>{},
      diskSavedDatasetIds: const <String>{},
    );
    unawaited(_refreshDatasetStatuses());
  }

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, Dataset>> datasetEntries =
        widget.datasets.entries.toList()
          ..sort((MapEntry<String, Dataset> a, MapEntry<String, Dataset> b) {
            return a.value.label.compareTo(b.value.label);
          });
    final Set<String> selectedDatasetIds = Set<String>.from(
      localParams['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[],
    );

    final Widget content = _buildDialogContent(
      context: context,
      datasetEntries: datasetEntries,
      selectedDatasetIds: selectedDatasetIds,
    );
    final List<Widget> actions = _buildActions(context);

    if (_fullscreen) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: <Widget>[
              IconButton(
                tooltip: 'Exit Full Screen',
                onPressed: () {
                  setState(() {
                    _fullscreen = false;
                  });
                },
                icon: const Icon(Icons.fullscreen_exit),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Expanded(child: content),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Expanded(child: Text(widget.title)),
          IconButton(
            tooltip: 'Full Screen',
            onPressed: () {
              setState(() {
                _fullscreen = true;
              });
            },
            icon: const Icon(Icons.fullscreen),
          ),
        ],
      ),
      content: SizedBox(
        width: 920,
        child: content,
      ),
      actions: actions,
    );
  }

  Widget _buildDialogContent({
    required BuildContext context,
    required List<MapEntry<String, Dataset>> datasetEntries,
    required Set<String> selectedDatasetIds,
  }) {
    final NodeDatasetStatusSnapshot statusSnapshot = _statusSnapshot ??
        NodeDatasetStatusSnapshot(
          availableDatasetIds: widget.availableDatasetIds,
          processedDatasetStates: widget.processedDatasetStates,
          ramLoadedDatasetIds: const <String>{},
          diskSavedDatasetIds: const <String>{},
        );

    return Stack(
      children: <Widget>[
        SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
          widget.buildBody(
            localParams,
            datasets: widget.datasets,
            setState: setState,
          ),
              const SizedBox(height: 12),
              _DatasetControlSection(
            datasets: datasetEntries,
            selectedDatasetIds: selectedDatasetIds,
            statusSnapshot: statusSnapshot,
            datasetSourceLabels: widget.datasetSourceLabels,
            busy: _runningDatasetAction,
            supportsDisk: widget.datasetActions?.supportsDisk ?? false,
            onDatasetNamePressed: (String datasetId) {
              showDialog<void>(
                context: context,
                builder: (_) => _MetadataDialog(
                  datasets: widget.datasets,
                  selectedDatasetIds: <String>{datasetId},
                  processingSteps: widget.processingSteps,
                ),
              );
            },
            onChanged: (Set<String> nextSelection) {
              setState(() {
                localParams['selectedDatasetIds'] = nextSelection.toList();
              });
            },
                onRunAllPrevious: (Set<String> datasetIds) => _runDatasetAction(
                  widget.datasetActions?.runAllPrevious,
                  datasetIds,
                  label: 'Running all previous...',
                ),
                onRunThisNode: (Set<String> datasetIds) => _runDatasetAction(
                  widget.datasetActions?.runThisNode,
                  datasetIds,
                  label: 'Running this node...',
                ),
                onClearResults: (Set<String> datasetIds) => _runDatasetAction(
                  widget.datasetActions?.clearResults,
                  datasetIds,
                  label: 'Clearing results...',
                ),
                onLoadFromDisk: (Set<String> datasetIds) => _runDatasetAction(
                  widget.datasetActions?.loadFromDisk,
                  datasetIds,
                  label: 'Loading from disk...',
                ),
                onPurgeActiveMemory: (Set<String> datasetIds) => _runDatasetAction(
                  widget.datasetActions?.purgeActiveMemory,
                  datasetIds,
                  label: 'Purging active memory...',
                ),
                onSaveToDisk: (Set<String> datasetIds) => _runDatasetAction(
                  widget.datasetActions?.saveToDisk,
                  datasetIds,
                  label: 'Saving to disk...',
                ),
                onPurgeFromDisk: (Set<String> datasetIds) => _runDatasetAction(
                  widget.datasetActions?.purgeFromDisk,
                  datasetIds,
                  label: 'Purging from disk...',
                ),
              ),
            ],
          ),
        ),
        if (_runningDatasetAction)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
              ),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _datasetActionLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _refreshDatasetStatuses() async {
    if (widget.datasetActions == null) {
      return;
    }
    try {
      final NodeDatasetStatusSnapshot snapshot =
          await widget.datasetActions!.refresh(Map<String, dynamic>.from(localParams));
      if (!mounted) {
        return;
      }
      setState(() {
        _statusSnapshot = snapshot;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _runDatasetAction(
    Future<String> Function(
      Map<String, dynamic> params,
      Set<String> datasetIds,
    )? action,
    Set<String> datasetIds,
    {
    required String label,
    }
  ) async {
    if (action == null || datasetIds.isEmpty) {
      return;
    }
    setState(() {
      _runningDatasetAction = true;
      _datasetActionLabel = label;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final String message = await action(
        Map<String, dynamic>.from(localParams),
        datasetIds,
      );
      await _refreshDatasetStatuses();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Dataset action failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _runningDatasetAction = false;
        });
      }
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    return <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (widget.onSaveAndRun != null)
        ElevatedButton(
          onPressed: () async {
            final NavigatorState navigator = Navigator.of(context);
            final Map<String, dynamic> paramsToSave =
                Map<String, dynamic>.from(localParams);
            widget.onSave(paramsToSave);
            navigator.pop();
            await widget.onSaveAndRun!(paramsToSave);
          },
          child: const Text('Save and Run'),
        ),
      ElevatedButton(
        onPressed: () {
          widget.onSave(Map<String, dynamic>.from(localParams));
          Navigator.pop(context);
        },
        child: const Text('Save'),
      ),
    ];
  }
}

class _MetadataDialog extends StatelessWidget {
  const _MetadataDialog({
    required this.datasets,
    required this.selectedDatasetIds,
    required this.processingSteps,
  });

  final Map<String, Dataset> datasets;
  final Set<String> selectedDatasetIds;
  final List<String> processingSteps;

  @override
  Widget build(BuildContext context) {
    final List<Dataset> selectedDatasets = datasets.values
        .where((Dataset dataset) => selectedDatasetIds.contains(dataset.id))
        .toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));

    return AlertDialog(
      title: const Text('Metadata'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Checked Datasets',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (selectedDatasets.isEmpty)
                const Text('No datasets are currently checked for this node.')
              else
                ...selectedDatasets.map(_datasetMetadataCard),
              const SizedBox(height: 20),
              const Text(
                'Processing Steps',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (processingSteps.isEmpty)
                const Text('No upstream processing steps are available yet.')
              else
                ...processingSteps.asMap().entries.map(
                      (MapEntry<int, String> entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${entry.key + 1}. ${entry.value}'),
                      ),
                    ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _datasetMetadataCard(Dataset dataset) {
    final List<Widget> rows = <Widget>[
      _metadataRow('Label', dataset.label),
      _metadataRow('Path', dataset.path.isEmpty ? 'unsaved' : dataset.path),
      _metadataRow('Loaded', dataset.loaded ? 'Yes' : 'No'),
    ];

    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      rows.add(_metadataRow(
        'Time series',
        '${timeSeries.sampleCount} samples across ${timeSeries.channelCount} channel(s) @ ${_formatDouble(timeSeries.sampleRate)} Hz',
      ));
      if (timeSeries.source.isNotEmpty) {
        rows.add(_metadataRow('Signal source', timeSeries.source));
      }
    }

    final FrequencySpectrumData? spectrum = dataset.spectrum;
    if (spectrum != null) {
      rows.add(_metadataRow(
        'Spectrum',
        '${spectrum.frequencies.length} bins, ${spectrum.segmentCount} segment(s)',
      ));
    }

    final SegmentedTimeSeriesData? segmentedTimeSeries =
        dataset.segmentedTimeSeries;
    if (segmentedTimeSeries != null) {
      final int firstSegmentSamples = segmentedTimeSeries.segments.isEmpty
          ? 0
          : segmentedTimeSeries.segments.first.sampleCount;
      rows.add(_metadataRow(
        'Segments',
        '${segmentedTimeSeries.segmentCount} segment(s), first segment: $firstSegmentSamples samples @ ${_formatDouble(segmentedTimeSeries.sampleRate)} Hz',
      ));
    }

    final TimeFrequencyData? timeFrequency = dataset.timeFrequency;
    if (timeFrequency != null) {
      rows.add(_metadataRow(
        'Time-frequency',
        '${timeFrequency.times.length} times x ${timeFrequency.frequencies.length} freqs',
      ));
    }

    final MatrixTransformationData? matrixTransformation =
        dataset.matrixTransformation;
    if (matrixTransformation != null) {
      final int rowCount = matrixTransformation.matrix.length;
      final int columnCount =
          rowCount == 0 ? 0 : matrixTransformation.matrix.first.length;
      rows.add(_metadataRow(
        'Matrix transform',
        '$rowCount x $columnCount',
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ),
    );
  }

  Widget _metadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: <TextSpan>[
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _formatDouble(double value) {
    return value.truncateToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

class _DatasetControlSection extends StatelessWidget {
  const _DatasetControlSection({
    required this.datasets,
    required this.selectedDatasetIds,
    required this.statusSnapshot,
    required this.datasetSourceLabels,
    required this.busy,
    required this.supportsDisk,
    required this.onDatasetNamePressed,
    required this.onChanged,
    required this.onRunAllPrevious,
    required this.onRunThisNode,
    required this.onClearResults,
    required this.onLoadFromDisk,
    required this.onPurgeActiveMemory,
    required this.onSaveToDisk,
    required this.onPurgeFromDisk,
  });

  final List<MapEntry<String, Dataset>> datasets;
  final Set<String> selectedDatasetIds;
  final NodeDatasetStatusSnapshot statusSnapshot;
  final Map<String, List<String>> datasetSourceLabels;
  final bool busy;
  final bool supportsDisk;
  final ValueChanged<String> onDatasetNamePressed;
  final ValueChanged<Set<String>> onChanged;
  final Future<void> Function(Set<String> datasetIds) onRunAllPrevious;
  final Future<void> Function(Set<String> datasetIds) onRunThisNode;
  final Future<void> Function(Set<String> datasetIds) onClearResults;
  final Future<void> Function(Set<String> datasetIds) onLoadFromDisk;
  final Future<void> Function(Set<String> datasetIds) onPurgeActiveMemory;
  final Future<void> Function(Set<String> datasetIds) onSaveToDisk;
  final Future<void> Function(Set<String> datasetIds) onPurgeFromDisk;

  @override
  Widget build(BuildContext context) {
    if (datasets.isEmpty) {
      return const Text('No datasets opened yet.');
    }

    final bool allChecked = datasets.isNotEmpty &&
        datasets.every((MapEntry<String, Dataset> entry) {
          return selectedDatasetIds.contains(entry.value.id);
        });
    final Set<String> checkedDatasetIds = Set<String>.from(selectedDatasetIds);
    final List<Dataset> checkedDatasets = datasets
        .map((MapEntry<String, Dataset> entry) => entry.value)
        .where((Dataset dataset) => checkedDatasetIds.contains(dataset.id))
        .toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Datasets',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Checked datasets are included when this node runs. Use the status controls below to manage processing, active memory, and disk cache.',
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Checkbox(
                  value: allChecked,
                  onChanged: busy
                      ? null
                      : (bool? value) {
                          if (value == true) {
                            onChanged(
                              datasets
                                  .map((MapEntry<String, Dataset> entry) => entry.value.id)
                                  .toSet(),
                            );
                          } else {
                            onChanged(<String>{});
                          }
                        },
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Apply actions to checked datasets',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _bulkActionButton(
                  label: 'Run all previous',
                  enabled: !busy && checkedDatasets.isNotEmpty,
                  onPressed: () => onRunAllPrevious(checkedDatasetIds),
                ),
                _bulkActionButton(
                  label: 'Run this node',
                  enabled: !busy && _anyCanRunThisNode(checkedDatasets),
                  onPressed: () => onRunThisNode(checkedDatasetIds),
                ),
                _bulkActionButton(
                  label: 'Clear results',
                  enabled: !busy && _anyCanClear(checkedDatasets),
                  onPressed: () => onClearResults(checkedDatasetIds),
                ),
                _bulkActionButton(
                  label: 'Load from disk',
                  enabled:
                      !busy && supportsDisk && _anyCanLoadFromDisk(checkedDatasets),
                  onPressed: () => onLoadFromDisk(checkedDatasetIds),
                ),
                _bulkActionButton(
                  label: 'Purge active memory',
                  enabled: !busy && _anyCanPurgeRam(checkedDatasets),
                  onPressed: () => onPurgeActiveMemory(checkedDatasetIds),
                ),
                _bulkActionButton(
                  label: 'Save to disk',
                  enabled:
                      !busy && supportsDisk && _anyCanSaveToDisk(checkedDatasets),
                  onPressed: () => onSaveToDisk(checkedDatasetIds),
                ),
                _bulkActionButton(
                  label: 'Purge from disk',
                  enabled: !busy && supportsDisk && _anyCanPurgeDisk(checkedDatasets),
                  onPressed: () => onPurgeFromDisk(checkedDatasetIds),
                ),
              ],
            ),
            if (!supportsDisk) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                'Disk actions are not available on this platform yet.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
            const SizedBox(height: 10),
            const _DatasetControlHeader(),
            const SizedBox(height: 6),
            for (int index = 0; index < datasets.length; index++) ...<Widget>[
              if (index > 0) const Divider(height: 14),
              _DatasetControlRow(
                dataset: datasets[index].value,
                selected: selectedDatasetIds.contains(datasets[index].value.id),
                sourceLabels:
                    datasetSourceLabels[datasets[index].value.id] ?? const <String>[],
                processingState: statusSnapshot.processedDatasetStates[
                        datasets[index].value.id] ??
                    DatasetState.notReady,
                ramLoaded:
                    statusSnapshot.ramLoadedDatasetIds.contains(datasets[index].value.id),
                diskSaved:
                    statusSnapshot.diskSavedDatasetIds.contains(datasets[index].value.id),
                busy: busy,
                supportsDisk: supportsDisk,
                onDatasetNamePressed: () =>
                    onDatasetNamePressed(datasets[index].value.id),
                onCheckedChanged: (bool checked) {
                  final Set<String> nextSelection = Set<String>.from(selectedDatasetIds);
                  if (checked) {
                    nextSelection.add(datasets[index].value.id);
                  } else {
                    nextSelection.remove(datasets[index].value.id);
                  }
                  onChanged(nextSelection);
                },
                onRunAllPrevious: () =>
                    onRunAllPrevious(<String>{datasets[index].value.id}),
                onRunThisNode: () => onRunThisNode(<String>{datasets[index].value.id}),
                onClearResults: () => onClearResults(<String>{datasets[index].value.id}),
                onLoadFromDisk: () => onLoadFromDisk(<String>{datasets[index].value.id}),
                onPurgeActiveMemory: () =>
                    onPurgeActiveMemory(<String>{datasets[index].value.id}),
                onSaveToDisk: () => onSaveToDisk(<String>{datasets[index].value.id}),
                onPurgeFromDisk: () =>
                    onPurgeFromDisk(<String>{datasets[index].value.id}),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _anyCanClear(List<Dataset> checkedDatasets) {
    return checkedDatasets.any((Dataset dataset) {
      final DatasetState state =
          statusSnapshot.processedDatasetStates[dataset.id] ?? DatasetState.notReady;
      return state == DatasetState.done ||
          state == DatasetState.stale ||
          statusSnapshot.ramLoadedDatasetIds.contains(dataset.id) ||
          statusSnapshot.diskSavedDatasetIds.contains(dataset.id);
    });
  }

  bool _anyCanRunThisNode(List<Dataset> checkedDatasets) {
    return checkedDatasets.any((Dataset dataset) {
      final DatasetState state =
          statusSnapshot.processedDatasetStates[dataset.id] ?? DatasetState.notReady;
      return state != DatasetState.notReady;
    });
  }

  bool _anyCanLoadFromDisk(List<Dataset> checkedDatasets) {
    return checkedDatasets.any((Dataset dataset) {
      return statusSnapshot.diskSavedDatasetIds.contains(dataset.id) &&
          !statusSnapshot.ramLoadedDatasetIds.contains(dataset.id);
    });
  }

  bool _anyCanPurgeRam(List<Dataset> checkedDatasets) {
    return checkedDatasets.any((Dataset dataset) {
      return statusSnapshot.ramLoadedDatasetIds.contains(dataset.id);
    });
  }

  bool _anyCanSaveToDisk(List<Dataset> checkedDatasets) {
    return checkedDatasets.any((Dataset dataset) {
      return statusSnapshot.ramLoadedDatasetIds.contains(dataset.id);
    });
  }

  bool _anyCanPurgeDisk(List<Dataset> checkedDatasets) {
    return checkedDatasets.any((Dataset dataset) {
      return statusSnapshot.diskSavedDatasetIds.contains(dataset.id);
    });
  }

  Widget _bulkActionButton({
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonal(
      onPressed: enabled ? onPressed : null,
      child: Text(label),
    );
  }
}

class _DatasetControlHeader extends StatelessWidget {
  const _DatasetControlHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        Expanded(
          flex: 30,
          child: Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text(
              'Dataset name',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 24,
          child: Text(
            'Processing status',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 22,
          child: Text(
            'RAM status',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 22,
          child: Text(
            'Hard disk',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _DatasetControlRow extends StatelessWidget {
  const _DatasetControlRow({
    required this.dataset,
    required this.selected,
    required this.sourceLabels,
    required this.processingState,
    required this.ramLoaded,
    required this.diskSaved,
    required this.busy,
    required this.supportsDisk,
    required this.onDatasetNamePressed,
    required this.onCheckedChanged,
    required this.onRunAllPrevious,
    required this.onRunThisNode,
    required this.onClearResults,
    required this.onLoadFromDisk,
    required this.onPurgeActiveMemory,
    required this.onSaveToDisk,
    required this.onPurgeFromDisk,
  });

  final Dataset dataset;
  final bool selected;
  final List<String> sourceLabels;
  final DatasetState processingState;
  final bool ramLoaded;
  final bool diskSaved;
  final bool busy;
  final bool supportsDisk;
  final VoidCallback onDatasetNamePressed;
  final ValueChanged<bool> onCheckedChanged;
  final VoidCallback onRunAllPrevious;
  final VoidCallback onRunThisNode;
  final VoidCallback onClearResults;
  final VoidCallback onLoadFromDisk;
  final VoidCallback onPurgeActiveMemory;
  final VoidCallback onSaveToDisk;
  final VoidCallback onPurgeFromDisk;

  @override
  Widget build(BuildContext context) {
    final bool canRun = processingState != DatasetState.notReady;
    final bool canClear =
        processingState == DatasetState.done || processingState == DatasetState.stale || ramLoaded || diskSaved;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: selected,
                onChanged: busy ? null : (bool? value) => onCheckedChanged(value == true),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: onDatasetNamePressed,
                        child: Text(
                          dataset.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (sourceLabels.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            sourceLabels.join(', '),
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 24,
          child: _StatusColumn(
            indicator: _processingIndicator(processingState),
            primaryLabel: 'Run all previous',
            onPrimary: !busy ? onRunAllPrevious : null,
            secondaryLabel: 'Run this node',
            onSecondary: !busy && canRun ? onRunThisNode : null,
            tertiaryLabel: 'Clear results',
            onTertiary: !busy && canClear ? onClearResults : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 22,
          child: _StatusColumn(
            indicator: _StatusIndicator(
              label: ramLoaded ? 'Loaded in active memory' : 'Not loaded',
              color: ramLoaded ? Colors.blue : Colors.grey,
            ),
            primaryLabel: 'Load from disk',
            onPrimary:
                !busy && supportsDisk && diskSaved && !ramLoaded ? onLoadFromDisk : null,
            secondaryLabel: 'Purge active memory',
            onSecondary: !busy && ramLoaded ? onPurgeActiveMemory : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 22,
          child: _StatusColumn(
            indicator: _StatusIndicator(
              label: diskSaved ? 'Saved to disk' : 'Not saved to disk',
              color: diskSaved ? Colors.purple : Colors.grey,
            ),
            primaryLabel: 'Save to disk',
            onPrimary: !busy && supportsDisk && ramLoaded ? onSaveToDisk : null,
            secondaryLabel: 'Purge from disk',
            onSecondary: !busy && supportsDisk && diskSaved ? onPurgeFromDisk : null,
          ),
        ),
      ],
    );
  }

  _StatusIndicator _processingIndicator(DatasetState state) {
    switch (state) {
      case DatasetState.notReady:
        return const _StatusIndicator(label: 'Not ready', color: Colors.grey);
      case DatasetState.ready:
        return const _StatusIndicator(label: 'Ready', color: Colors.blueGrey);
      case DatasetState.done:
        return const _StatusIndicator(label: 'Done', color: Colors.green);
      case DatasetState.stale:
        return const _StatusIndicator(label: 'Stale', color: Colors.orange);
    }
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    required this.indicator,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tertiaryLabel,
    this.onTertiary,
  });

  final _StatusIndicator indicator;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? tertiaryLabel;
  final VoidCallback? onTertiary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        indicator,
        const SizedBox(height: 8),
        _textAction(primaryLabel, onPrimary),
        if (secondaryLabel != null) ...<Widget>[
          const SizedBox(height: 4),
          _textAction(secondaryLabel!, onSecondary),
        ],
        if (tertiaryLabel != null) ...<Widget>[
          const SizedBox(height: 4),
          _textAction(tertiaryLabel!, onTertiary),
        ],
      ],
    );
  }

  Widget _textAction(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 28),
        alignment: Alignment.centerLeft,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
