import 'package:flutter/material.dart';

import '../model/dataset.dart';
import '../model/dataset_state.dart';

enum PortType { signal, metadata, markers }
enum NodeCategory { import, transform, markerFunctions, visualize, export, other }

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
        return Colors.teal;
      case NodeCategory.transform:
        return Colors.indigo;
      case NodeCategory.markerFunctions:
        return Colors.pinkAccent;
      case NodeCategory.visualize:
        return Colors.orange;
      case NodeCategory.export:
        return Colors.green;
      case NodeCategory.other:
        return Colors.grey;
    }
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

abstract class NodeType {
  String get title;
  NodeCategory get category => NodeCategory.other;
  Map<String, dynamic> get defaultParams;

  List<PortSpec> get inputs;
  List<PortSpec> get outputs;

  /// Nodes implement ONLY their body UI here
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      });

  /// Final, shared config panel
  Widget buildConfigWidget(
      Map<String, dynamic> params,
      void Function(Map<String, dynamic>) onSave, {
        required Map<String, Dataset> datasets,
        required Set<String> availableDatasetIds,
        required Map<String, DatasetState> processedDatasetStates,
      }) {
    return _NodeConfigDialog(
      title: title,
      params: params,
      datasets: datasets,
      availableDatasetIds: availableDatasetIds,
      processedDatasetStates: processedDatasetStates,
      buildBody: buildBody,
      onSave: onSave,
    );
  }

  /// Execution hook
  Future<void> run(Dataset dataset, Map<String, dynamic> params);
}

class _NodeConfigDialog extends StatefulWidget {
  final String title;
  final Map<String, dynamic> params;
  final Map<String, Dataset> datasets;
  final Set<String> availableDatasetIds;
  final Map<String, DatasetState> processedDatasetStates;
  final Widget Function(
      Map<String, dynamic> params, {
      required Map<String, Dataset> datasets,
      required void Function(void Function()) setState,
      }) buildBody;
  final void Function(Map<String, dynamic>) onSave;

  const _NodeConfigDialog({
    required this.title,
    required this.params,
    required this.datasets,
    required this.availableDatasetIds,
    required this.processedDatasetStates,
    required this.buildBody,
    required this.onSave,
  });

  @override
  State<_NodeConfigDialog> createState() => _NodeConfigDialogState();
}

class _NodeConfigDialogState extends State<_NodeConfigDialog> {
  late Map<String, dynamic> localParams;

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
  }

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, Dataset>> datasetEntries = widget.datasets.entries.toList()
      ..sort((MapEntry<String, Dataset> a, MapEntry<String, Dataset> b) {
        return a.value.label.compareTo(b.value.label);
      });
    final Set<String> selectedDatasetIds = Set<String>.from(
      localParams['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[],
    );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              widget.buildBody(
                localParams,
                datasets: widget.datasets,
                setState: setState,
              ),
              const SizedBox(height: 20),
              const Text(
                'Datasets',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _DatasetSelectionTable(
                datasets: datasetEntries,
                selectedDatasetIds: selectedDatasetIds,
                availableDatasetIds: widget.availableDatasetIds,
                processedDatasetStates: widget.processedDatasetStates,
                onChanged: (Set<String> nextSelection) {
                  setState(() {
                    localParams['selectedDatasetIds'] = nextSelection.toList();
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(localParams);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DatasetSelectionTable extends StatelessWidget {
  const _DatasetSelectionTable({
    required this.datasets,
    required this.selectedDatasetIds,
    required this.availableDatasetIds,
    required this.processedDatasetStates,
    required this.onChanged,
  });

  final List<MapEntry<String, Dataset>> datasets;
  final Set<String> selectedDatasetIds;
  final Set<String> availableDatasetIds;
  final Map<String, DatasetState> processedDatasetStates;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (datasets.isEmpty) {
      return const Text('No datasets opened yet.');
    }

    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(56),
        1: FlexColumnWidth(),
        2: FixedColumnWidth(88),
        3: FixedColumnWidth(96),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        const TableRow(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Use',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Dataset',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Available',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Processed',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        for (final MapEntry<String, Dataset> entry in datasets)
          _buildRow(entry.value),
      ],
    );
  }

  TableRow _buildRow(Dataset dataset) {
    final bool selected = selectedDatasetIds.contains(dataset.id);
    final bool available = availableDatasetIds.contains(dataset.id);
    final DatasetState processedState =
        processedDatasetStates[dataset.id] ?? DatasetState.notReady;

    return TableRow(
      children: <Widget>[
        Checkbox(
          value: selected,
          onChanged: (bool? value) {
            final Set<String> nextSelection = Set<String>.from(selectedDatasetIds);
            if (value == true) {
              nextSelection.add(dataset.id);
            } else {
              nextSelection.remove(dataset.id);
            }
            onChanged(nextSelection);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(dataset.label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _StatusPill(
            label: available ? 'Yes' : 'No',
            color: available ? Colors.green : Colors.grey,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _StatusPill(
            label: _processedLabel(processedState),
            color: _processedColor(processedState),
          ),
        ),
      ],
    );
  }

  String _processedLabel(DatasetState state) {
    switch (state) {
      case DatasetState.notReady:
        return 'No';
      case DatasetState.ready:
        return 'Ready';
      case DatasetState.done:
        return 'Yes';
      case DatasetState.stale:
        return 'Stale';
    }
  }

  Color _processedColor(DatasetState state) {
    switch (state) {
      case DatasetState.notReady:
        return Colors.grey;
      case DatasetState.ready:
        return Colors.blueGrey;
      case DatasetState.done:
        return Colors.green;
      case DatasetState.stale:
        return Colors.orange;
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
