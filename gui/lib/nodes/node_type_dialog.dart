part of 'node_type.dart';

class _NodeConfigDialog extends StatefulWidget {
  const _NodeConfigDialog({
    required this.title,
    required this.helpText,
    required this.params,
    required this.datasets,
    required this.availableDatasetIds,
    required this.datasetSourceLabels,
    required this.processedDatasetStates,
    required this.portStatusSummary,
    required this.processingSteps,
    required this.buildBody,
    required this.onSave,
    required this.onSaveAndRun,
    required this.datasetActions,
    required this.defaultStoragePolicy,
    required this.showSourceFiles,
    required this.initialTabIndex,
    required this.startInExportMode,
  });

  final String title;
  final String? helpText;
  final Map<String, dynamic> params;
  final Map<String, Dataset> datasets;
  final Set<String> availableDatasetIds;
  final Map<String, List<String>> datasetSourceLabels;
  final Map<String, DatasetState> processedDatasetStates;
  final NodePortStatusSummary portStatusSummary;
  final List<String> processingSteps;
  final Widget Function(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  })
  buildBody;
  final void Function(Map<String, dynamic>) onSave;
  final FutureOr<void> Function(Map<String, dynamic>)? onSaveAndRun;
  final NodeDatasetActions? datasetActions;
  final NodeStoragePolicy defaultStoragePolicy;
  final bool showSourceFiles;
  final int initialTabIndex;
  final bool startInExportMode;

  @override
  State<_NodeConfigDialog> createState() => _NodeConfigDialogState();
}

class _NodeConfigDialogState extends State<_NodeConfigDialog>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> localParams;
  late final TabController _tabController;
  bool _fullscreen = false;
  NodeDatasetStatusSnapshot? _statusSnapshot;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            tooltip: 'Help',
            onPressed: () => _showHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
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
        height: math.min(620, MediaQuery.sizeOf(context).height * 0.64),
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
    final NodeDatasetStatusSnapshot statusSnapshot =
        _statusSnapshot ??
        NodeDatasetStatusSnapshot(
          availableDatasetIds: widget.availableDatasetIds,
          processedDatasetStates: widget.processedDatasetStates,
          ramLoadedDatasetIds: const <String>{},
          diskSavedDatasetIds: const <String>{},
        );

    return Column(
      children: <Widget>[
        TabBar(
          controller: _tabController,
          tabs: const <Widget>[
            Tab(text: 'Parameters'),
            Tab(text: 'Persistence'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: <Widget>[
              SingleChildScrollView(
                key: const ValueKey<String>('node-parameters-tab-content'),
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
                      onDatasetNamePressed: (String datasetId) {
                        showDialog<void>(
                          context: context,
                          builder: (_) => _MetadataDialog(
                            datasets: widget.datasets,
                            selectedDatasetIds: <String>{datasetId},
                            processingSteps: widget.processingSteps,
                            showSourceFiles: widget.showSourceFiles,
                          ),
                        );
                      },
                      onChanged: (Set<String> nextSelection) {
                        setState(() {
                          localParams['selectedDatasetIds'] = nextSelection
                              .toList();
                        });
                      },
                    ),
                  ],
                ),
              ),
              _NodePersistenceTab(
                datasets: datasetEntries,
                selectedDatasetIds: selectedDatasetIds,
                statusSnapshot: statusSnapshot,
                storagePolicy: NodeStoragePolicyPresentation.fromWireValue(
                  localParams['storagePolicy']?.toString(),
                ),
                datasetActions: widget.datasetActions,
                onStoragePolicyChanged: (NodeStoragePolicy policy) {
                  setState(() {
                    localParams['storagePolicy'] = policy.wireValue;
                  });
                },
                startInExportMode: widget.startInExportMode,
              ),
            ],
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
      final NodeDatasetStatusSnapshot snapshot = await widget.datasetActions!
          .refresh(Map<String, dynamic>.from(localParams));
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

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _NodeHelpDialog(
        title: widget.title,
        helpText: widget.helpText,
        portStatusSummary: widget.portStatusSummary,
        datasets: widget.datasets,
        selectedDatasetIds: Set<String>.from(
          localParams['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[],
        ),
        processingSteps: widget.processingSteps,
        showSourceFiles: widget.showSourceFiles,
      ),
    );
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
            final Map<String, dynamic> params = Map<String, dynamic>.from(
              localParams,
            );
            Navigator.pop(context);
            await widget.onSaveAndRun!(params);
          },
          child: const Text('Save & Run'),
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

class _NodePersistenceTab extends StatefulWidget {
  const _NodePersistenceTab({
    required this.datasets,
    required this.selectedDatasetIds,
    required this.statusSnapshot,
    required this.storagePolicy,
    required this.datasetActions,
    required this.onStoragePolicyChanged,
    required this.startInExportMode,
  });

  final List<MapEntry<String, Dataset>> datasets;
  final Set<String> selectedDatasetIds;
  final NodeDatasetStatusSnapshot statusSnapshot;
  final NodeStoragePolicy storagePolicy;
  final NodeDatasetActions? datasetActions;
  final ValueChanged<NodeStoragePolicy> onStoragePolicyChanged;
  final bool startInExportMode;

  @override
  State<_NodePersistenceTab> createState() => _NodePersistenceTabState();
}

class _NodePersistenceTabState extends State<_NodePersistenceTab> {
  late bool _exportMode;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _exportMode = widget.startInExportMode;
  }

  @override
  Widget build(BuildContext context) {
    final NodePersistenceTableSnapshot table =
        widget.statusSnapshot.persistenceTable;
    final List<NodePersistenceColumn> exportColumns = table.columns
        .where(
          (NodePersistenceColumn column) =>
              column.direction == NodePersistenceDirection.output &&
              column.selectedNodeOutput,
        )
        .toList(growable: false);
    final Set<String> eligible = <String>{
      for (final NodePersistenceRow row in table.rows)
        for (final NodePersistenceColumn column in exportColumns)
          if (row.cells[column.id]?.status == NodePersistenceStatus.outputDone)
            '${row.datasetId}:${column.artifact.name}',
    };
    _selected.removeWhere((String key) => !eligible.contains(key));
    return Column(
      key: const ValueKey<String>('node-persistence-tab-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              'Storage policy',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            DropdownButton<NodeStoragePolicy>(
              value: widget.storagePolicy,
              onChanged: (NodeStoragePolicy? policy) {
                if (policy != null) {
                  widget.onStoragePolicyChanged(policy);
                }
              },
              items: NodeStoragePolicy.values
                  .map(
                    (NodeStoragePolicy policy) =>
                        DropdownMenuItem<NodeStoragePolicy>(
                          value: policy,
                          child: Text(policy.label),
                        ),
                  )
                  .toList(growable: false),
            ),
            const Spacer(),
            if (!_exportMode)
              OutlinedButton.icon(
                onPressed: widget.datasetActions?.exportArtifacts == null
                    ? null
                    : () => setState(() => _exportMode = true),
                icon: const Icon(Icons.download),
                label: const Text('Export'),
              )
            else ...<Widget>[
              TextButton(
                onPressed: eligible.isEmpty
                    ? null
                    : () => setState(() {
                        if (_selected.length == eligible.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(eligible);
                        }
                      }),
                child: Text(
                  _selected.length == eligible.length && eligible.isNotEmpty
                      ? 'Clear all'
                      : 'Select all',
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _exportMode = false;
                  _selected.clear();
                }),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () async {
                        final Set<NodeArtifactExportSelection>
                        selections = _selected.map((String key) {
                          final int separator = key.lastIndexOf(':');
                          return NodeArtifactExportSelection(
                            datasetId: key.substring(0, separator),
                            artifact: NodePersistenceArtifact.values.firstWhere(
                              (NodePersistenceArtifact artifact) =>
                                  artifact.name == key.substring(separator + 1),
                            ),
                          );
                        }).toSet();
                        await widget.datasetActions?.exportArtifacts?.call(
                          context,
                          selections,
                        );
                      },
                child: const Text('Continue'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: table.rows.isEmpty
              ? const Center(
                  child: Text(
                    'No datasets are exposed by this node\'s parents.',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              : _NodePersistenceTable(
                  table: table,
                  exportMode: _exportMode,
                  selected: _selected,
                  eligible: eligible,
                  onSelectionChanged: (String key, bool selected) {
                    setState(() {
                      selected ? _selected.add(key) : _selected.remove(key);
                    });
                  },
                ),
        ),
      ],
    );
  }
}

class _NodePersistenceTable extends StatelessWidget {
  const _NodePersistenceTable({
    required this.table,
    required this.exportMode,
    required this.selected,
    required this.eligible,
    required this.onSelectionChanged,
  });

  static const double _datasetWidth = 180;
  static const double _columnWidth = 148;
  static const double _headerHeight = 36;
  static const double _rowHeight = 50;

  final NodePersistenceTableSnapshot table;
  final bool exportMode;
  final Set<String> selected;
  final Set<String> eligible;
  final void Function(String key, bool selected) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SizedBox(
        height: _headerHeight * 3 + _rowHeight * table.rows.length,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: _datasetWidth,
                  child: Column(
                    children: <Widget>[
                      _stubHeader('Input / Output'),
                      _stubHeader('Connected node'),
                      _stubHeader('Artifact'),
                      for (final NodePersistenceRow row in table.rows)
                        _datasetCell(row.datasetLabel),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: table.columns.length * _columnWidth,
                      child: Column(
                        children: <Widget>[
                          _headerRow(
                            _headerSpans(
                              table.columns,
                              (NodePersistenceColumn column) =>
                                  column.direction,
                            ),
                            (Object value) =>
                                (value as NodePersistenceDirection) ==
                                    NodePersistenceDirection.input
                                ? 'Input'
                                : 'Output',
                            emphasized: true,
                          ),
                          _headerRow(
                            _headerSpans(
                              table.columns,
                              (NodePersistenceColumn column) =>
                                  '${column.direction.name}:${column.connectedNodeLabel}',
                            ),
                            (Object value) => value.toString().split(':').last,
                          ),
                          Row(
                            children: table.columns
                                .map(
                                  (NodePersistenceColumn column) => _leafHeader(
                                    _persistenceArtifactLabel(column.artifact),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                          for (final NodePersistenceRow row in table.rows)
                            Row(
                              children: table.columns
                                  .map((NodePersistenceColumn column) {
                                    return _statusCell(
                                      row.cells[column.id] ??
                                          const NodePersistenceCell(
                                            status: NodePersistenceStatus
                                                .outputNotReady,
                                          ),
                                      row: row,
                                      column: column,
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stubHeader(String label) {
    return Container(
      width: _datasetWidth,
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.055),
        border: const Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _datasetCell(String label) {
    return Container(
      width: _datasetWidth,
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _headerRow(
    List<_PersistenceHeaderSpan> spans,
    String Function(Object value) labelFor, {
    bool emphasized = false,
  }) {
    return Row(
      children: spans
          .map((_PersistenceHeaderSpan span) {
            return Container(
              width: span.length * _columnWidth,
              height: _headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: emphasized ? 0.08 : 0.055,
                ),
                border: const Border(
                  right: BorderSide(color: Colors.black12),
                  bottom: BorderSide(color: Colors.black12),
                ),
              ),
              child: Text(
                labelFor(span.value),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _leafHeader(String label) {
    return Container(
      width: _columnWidth,
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        border: const Border(
          right: BorderSide(color: Colors.black12),
          bottom: BorderSide(color: Colors.black12),
        ),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _statusCell(
    NodePersistenceCell cell, {
    required NodePersistenceRow row,
    required NodePersistenceColumn column,
  }) {
    final List<_PersistenceBadgeSpec> badges = _persistenceBadges(cell);
    final String selectionKey = '${row.datasetId}:${column.artifact.name}';
    final bool canSelect = eligible.contains(selectionKey);
    return Container(
      width: _columnWidth,
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.black12),
          bottom: BorderSide(color: Colors.black12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (exportMode && column.selectedNodeOutput)
            Checkbox(
              value: selected.contains(selectionKey),
              onChanged: canSelect
                  ? (bool? value) =>
                        onSelectionChanged(selectionKey, value == true)
                  : null,
              visualDensity: VisualDensity.compact,
            ),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 3,
              children: badges
                  .map(
                    (_PersistenceBadgeSpec badge) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: badge.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: badge.color.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          badge.label,
                          style: TextStyle(
                            color: badge.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersistenceHeaderSpan {
  const _PersistenceHeaderSpan({required this.value, required this.length});

  final Object value;
  final int length;
}

class _PersistenceBadgeSpec {
  const _PersistenceBadgeSpec(this.label, this.color);

  final String label;
  final Color color;
}

List<_PersistenceHeaderSpan> _headerSpans(
  List<NodePersistenceColumn> columns,
  Object Function(NodePersistenceColumn column) valueFor,
) {
  final List<_PersistenceHeaderSpan> spans = <_PersistenceHeaderSpan>[];
  for (final NodePersistenceColumn column in columns) {
    final Object value = valueFor(column);
    if (spans.isNotEmpty && spans.last.value == value) {
      final _PersistenceHeaderSpan previous = spans.removeLast();
      spans.add(
        _PersistenceHeaderSpan(value: value, length: previous.length + 1),
      );
    } else {
      spans.add(_PersistenceHeaderSpan(value: value, length: 1));
    }
  }
  return spans;
}

List<_PersistenceBadgeSpec> _persistenceBadges(NodePersistenceCell cell) {
  final _PersistenceBadgeSpec primary = switch (cell.status) {
    NodePersistenceStatus.absent => const _PersistenceBadgeSpec(
      'Absent',
      Colors.red,
    ),
    NodePersistenceStatus.wired => const _PersistenceBadgeSpec(
      'Wired',
      Colors.blueGrey,
    ),
    NodePersistenceStatus.stale => const _PersistenceBadgeSpec(
      'Stale',
      Colors.orange,
    ),
    NodePersistenceStatus.inputReady => const _PersistenceBadgeSpec(
      'Ready',
      Colors.green,
    ),
    NodePersistenceStatus.outputNotReady => const _PersistenceBadgeSpec(
      'Not ready',
      Colors.blueGrey,
    ),
    NodePersistenceStatus.outputReady => const _PersistenceBadgeSpec(
      'Ready',
      Colors.indigo,
    ),
    NodePersistenceStatus.outputDone => const _PersistenceBadgeSpec(
      'Done',
      Colors.green,
    ),
  };
  if (cell.status != NodePersistenceStatus.outputDone) {
    return <_PersistenceBadgeSpec>[primary];
  }
  return <_PersistenceBadgeSpec>[
    primary,
    if (cell.active) const _PersistenceBadgeSpec('Active', Colors.blue),
    if (cell.onDisk) const _PersistenceBadgeSpec('On disk', Colors.brown),
    if (cell.passThrough)
      const _PersistenceBadgeSpec('Pass-through', Colors.teal),
  ];
}

String _persistenceArtifactLabel(NodePersistenceArtifact artifact) {
  return switch (artifact) {
    NodePersistenceArtifact.timeSeries => 'Time series',
    NodePersistenceArtifact.channelNames => 'Channel names',
    NodePersistenceArtifact.channelCoordinates => 'Channel coordinates',
    NodePersistenceArtifact.impedance => 'Impedance',
    NodePersistenceArtifact.markers => 'Markers',
    NodePersistenceArtifact.segmentedTimeSeries => 'Segments',
    NodePersistenceArtifact.spectrum => 'Spectrum',
    NodePersistenceArtifact.fooofResult => 'FOOOF result',
    NodePersistenceArtifact.featureTable => 'Feature table',
    NodePersistenceArtifact.gaussianMixture => 'Gaussian mixture',
    NodePersistenceArtifact.bridgeDetection => 'Bridge detection',
    NodePersistenceArtifact.timeFrequency => 'Time-frequency',
    NodePersistenceArtifact.matrixTransformation => 'Transformation matrix',
    NodePersistenceArtifact.metadata => 'Metadata',
  };
}

class _NodeHelpDialog extends StatelessWidget {
  const _NodeHelpDialog({
    required this.title,
    required this.helpText,
    required this.portStatusSummary,
    required this.datasets,
    required this.selectedDatasetIds,
    required this.processingSteps,
    required this.showSourceFiles,
  });

  final String title;
  final String? helpText;
  final NodePortStatusSummary portStatusSummary;
  final Map<String, Dataset> datasets;
  final Set<String> selectedDatasetIds;
  final List<String> processingSteps;
  final bool showSourceFiles;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('$title help'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (helpText != null) ...<Widget>[
                Text(helpText!),
                const SizedBox(height: 16),
              ],
              _PortStatusHeader(summary: portStatusSummary),
              const SizedBox(height: 16),
              _MetadataDialogBody(
                datasets: datasets,
                selectedDatasetIds: selectedDatasetIds,
                processingSteps: processingSteps,
                showSourceFiles: showSourceFiles,
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
}

class _PortStatusHeader extends StatelessWidget {
  const _PortStatusHeader({required this.summary});

  final NodePortStatusSummary summary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _PortStatusRow(
              title: 'Inputs',
              emptyText: 'No upstream inputs required.',
              summaries: summary.inputs,
            ),
            const SizedBox(height: 10),
            _PortStatusRow(
              title: 'Outputs',
              emptyText: 'This node does not create graph outputs.',
              summaries: summary.outputs,
            ),
          ],
        ),
      ),
    );
  }
}

class _PortStatusRow extends StatelessWidget {
  const _PortStatusRow({
    required this.title,
    required this.emptyText,
    required this.summaries,
  });

  final String title;
  final String emptyText;
  final List<NodePortDatasetSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 78,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: summaries.isEmpty
              ? Text(emptyText, style: const TextStyle(color: Colors.black54))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: summaries
                      .map(
                        (NodePortDatasetSummary summary) =>
                            _PortStatusChip(summary: summary),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }
}

class _PortStatusChip extends StatelessWidget {
  const _PortStatusChip({required this.summary});

  final NodePortDatasetSummary summary;

  @override
  Widget build(BuildContext context) {
    final Color color = _portTypeColor(summary.type);
    return Tooltip(
      message:
          '${_portTypeLabel(summary.type)}: ${summary.readyCount} of '
          '${summary.totalCount} dataset(s)',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                summary.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '${summary.readyCount}/${summary.totalCount}',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _portTypeColor(PortType type) {
  switch (type) {
    case PortType.signal:
      return Colors.indigo;
    case PortType.markers:
      return Colors.amber.shade800;
    case PortType.metadata:
      return Colors.teal;
    case PortType.matrixTransformation:
      return Colors.deepPurple;
  }
}

String _portTypeLabel(PortType type) {
  switch (type) {
    case PortType.signal:
      return 'Signal';
    case PortType.markers:
      return 'Markers';
    case PortType.metadata:
      return 'Metadata';
    case PortType.matrixTransformation:
      return 'Matrix';
  }
}

class _MetadataDialog extends StatelessWidget {
  const _MetadataDialog({
    required this.datasets,
    required this.selectedDatasetIds,
    required this.processingSteps,
    required this.showSourceFiles,
  });

  final Map<String, Dataset> datasets;
  final Set<String> selectedDatasetIds;
  final List<String> processingSteps;
  final bool showSourceFiles;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Metadata'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: _MetadataDialogBody(
            datasets: datasets,
            selectedDatasetIds: selectedDatasetIds,
            processingSteps: processingSteps,
            showSourceFiles: showSourceFiles,
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
}

class _MetadataDialogBody extends StatelessWidget {
  const _MetadataDialogBody({
    required this.datasets,
    required this.selectedDatasetIds,
    required this.processingSteps,
    required this.showSourceFiles,
  });

  final Map<String, Dataset> datasets;
  final Set<String> selectedDatasetIds;
  final List<String> processingSteps;
  final bool showSourceFiles;

  @override
  Widget build(BuildContext context) {
    final List<Dataset> selectedDatasets =
        datasets.values
            .where((Dataset dataset) => selectedDatasetIds.contains(dataset.id))
            .toList()
          ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));

    return Column(
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
    );
  }

  Widget _datasetMetadataCard(Dataset dataset) {
    final List<Widget> rows = <Widget>[
      _metadataRow('Label', dataset.label),
      _metadataRow('Loaded', dataset.loaded ? 'Yes' : 'No'),
    ];
    if (showSourceFiles) {
      rows.insert(
        1,
        _metadataRow('Path', dataset.path.isEmpty ? 'unsaved' : dataset.path),
      );
    }

    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries != null) {
      rows.add(
        _metadataRow(
          'Time series',
          '${timeSeries.sampleCount} samples across ${timeSeries.channelCount} channel(s) @ ${_formatDouble(timeSeries.sampleRate)} Hz',
        ),
      );
      if (timeSeries.source.isNotEmpty) {
        rows.add(_metadataRow('Signal source', timeSeries.source));
      }
    }

    final FrequencySpectrumData? spectrum = dataset.spectrum;
    if (spectrum != null) {
      rows.add(
        _metadataRow(
          'Spectrum',
          '${spectrum.frequencies.length} bins, ${spectrum.segmentCount} segment(s)',
        ),
      );
    }

    final FooofResultData? fooofResult = dataset.fooofResult;
    if (fooofResult != null) {
      rows.add(
        _metadataRow(
          'FOOOF',
          '1/f exponent ${fooofResult.exponent.toStringAsFixed(3)}, intercept ${fooofResult.intercept.toStringAsFixed(3)}, ${fooofResult.peaks.length} peak(s)',
        ),
      );
    }

    final FeatureTableData? featureTable = dataset.featureTable;
    if (featureTable != null) {
      rows.add(
        _metadataRow(
          'Feature table',
          '${featureTable.rows.length} row(s), ${featureTable.columns.length} column(s)',
        ),
      );
    }

    final GaussianMixtureData? gaussianMixture = dataset.gaussianMixture;
    if (gaussianMixture != null) {
      rows.add(
        _metadataRow(
          'Gaussian mixture',
          '${gaussianMixture.componentCount} component(s), '
              '${gaussianMixture.rowCount} row(s), '
              '${gaussianMixture.converged ? 'converged' : 'not converged'} '
              'after ${gaussianMixture.iterationCount} iteration(s)',
        ),
      );
      rows.add(
        _metadataRow(
          'Model selection',
          'AIC ${gaussianMixture.aic.toStringAsFixed(2)}, '
              'BIC ${gaussianMixture.bic.toStringAsFixed(2)}',
        ),
      );
    }

    final BridgeDetectionData? bridgeDetection = dataset.bridgeDetection;
    if (bridgeDetection != null) {
      rows.add(
        _metadataRow(
          'Bridge detector',
          '${bridgeDetection.frameCount} minute frame(s), ${bridgeDetection.channelCount} channel(s), ${bridgeDetection.valueCount} correlation value(s)',
        ),
      );
    }

    final SegmentedTimeSeriesData? segmentedTimeSeries =
        dataset.segmentedTimeSeries;
    if (segmentedTimeSeries != null) {
      final int firstSegmentSamples = segmentedTimeSeries.segments.isEmpty
          ? 0
          : segmentedTimeSeries.segments.first.sampleCount;
      rows.add(
        _metadataRow(
          'Segments',
          '${segmentedTimeSeries.segmentCount} segment(s), first segment: $firstSegmentSamples samples @ ${_formatDouble(segmentedTimeSeries.sampleRate)} Hz',
        ),
      );
    }

    final TimeFrequencyData? timeFrequency = dataset.timeFrequency;
    if (timeFrequency != null) {
      rows.add(
        _metadataRow(
          'Time-frequency',
          '${timeFrequency.times.length} times x ${timeFrequency.frequencies.length} freqs',
        ),
      );
    }

    final MatrixTransformationData? matrixTransformation =
        dataset.matrixTransformation;
    if (matrixTransformation != null) {
      final int rowCount = matrixTransformation.matrix.length;
      final int columnCount = rowCount == 0
          ? 0
          : matrixTransformation.matrix.first.length;
      rows.add(_metadataRow('Matrix transform', '$rowCount x $columnCount'));
      if (matrixTransformation.algorithm.isNotEmpty) {
        final bool? converged = matrixTransformation.converged;
        final String convergence = converged == null
            ? ''
            : converged
            ? 'converged in ${matrixTransformation.iterationCount} iteration(s)'
            : 'NOT CONVERGED after ${matrixTransformation.iterationCount} iteration(s)';
        rows.add(
          _metadataRow(
            matrixTransformation.algorithm,
            <String>[
              '${matrixTransformation.componentCount} component(s)',
              if (convergence.isNotEmpty) convergence,
              if (matrixTransformation.numericalRank > 0)
                'rank ${matrixTransformation.numericalRank}',
            ].join(' • '),
          ),
        );
      }
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

class _DatasetControlHeader extends StatelessWidget {
  const _DatasetControlHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        Expanded(
          flex: 22,
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
          flex: 18,
          child: Text(
            'Source node',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 20,
          child: Text(
            'Processing status',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 20,
          child: Text(
            'RAM status',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 20,
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
    required this.onDatasetNamePressed,
    required this.onCheckedChanged,
  });

  final Dataset dataset;
  final bool selected;
  final List<String> sourceLabels;
  final DatasetState processingState;
  final bool ramLoaded;
  final bool diskSaved;
  final VoidCallback onDatasetNamePressed;
  final ValueChanged<bool> onCheckedChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: selected,
                onChanged: (bool? value) => onCheckedChanged(value == true),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: TextButton(
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
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 18,
          child: Text(
            sourceLabels.isEmpty ? 'Source file' : sourceLabels.join(', '),
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(flex: 20, child: _processingIndicator(processingState)),
        const SizedBox(width: 16),
        Expanded(
          flex: 20,
          child: _StatusIndicator(
            label: ramLoaded ? 'Loaded in active memory' : 'Not loaded',
            color: ramLoaded ? Colors.blue : Colors.grey,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 20,
          child: _StatusIndicator(
            label: diskSaved ? 'Saved to disk' : 'Not saved to disk',
            color: diskSaved ? Colors.purple : Colors.grey,
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
      case DatasetState.partial:
        return const _StatusIndicator(
          label: 'Partial',
          color: Color(0xFFC7D85A),
        );
      case DatasetState.done:
        return const _StatusIndicator(label: 'Done', color: Colors.green);
      case DatasetState.stale:
        return const _StatusIndicator(label: 'Stale', color: Colors.orange);
    }
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
}

class _DatasetControlSection extends StatelessWidget {
  const _DatasetControlSection({
    required this.datasets,
    required this.selectedDatasetIds,
    required this.statusSnapshot,
    required this.datasetSourceLabels,
    required this.onDatasetNamePressed,
    required this.onChanged,
  });

  final List<MapEntry<String, Dataset>> datasets;
  final Set<String> selectedDatasetIds;
  final NodeDatasetStatusSnapshot statusSnapshot;
  final Map<String, List<String>> datasetSourceLabels;
  final ValueChanged<String> onDatasetNamePressed;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (datasets.isEmpty) {
      return const Text('No datasets opened yet.');
    }

    final bool allChecked =
        datasets.isNotEmpty &&
        datasets.every((MapEntry<String, Dataset> entry) {
          return selectedDatasetIds.contains(entry.value.id);
        });
    final int selectedCount = datasets
        .where(
          (MapEntry<String, Dataset> entry) =>
              selectedDatasetIds.contains(entry.value.id),
        )
        .length;
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  const Text(
                    'Datasets',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$selectedCount/${datasets.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                onChanged(
                  allChecked
                      ? <String>{}
                      : datasets
                            .map(
                              (MapEntry<String, Dataset> entry) =>
                                  entry.value.id,
                            )
                            .toSet(),
                );
              },
              child: Text(allChecked ? 'Unselect all' : 'Select all'),
            ),
            const SizedBox(height: 10),
            const _DatasetControlHeader(),
            const SizedBox(height: 6),
            for (int index = 0; index < datasets.length; index++) ...<Widget>[
              if (index > 0) const Divider(height: 14),
              _DatasetControlRow(
                dataset: datasets[index].value,
                selected: selectedDatasetIds.contains(datasets[index].value.id),
                sourceLabels:
                    datasetSourceLabels[datasets[index].value.id] ??
                    const <String>[],
                processingState:
                    statusSnapshot.processedDatasetStates[datasets[index]
                        .value
                        .id] ??
                    DatasetState.notReady,
                ramLoaded: statusSnapshot.ramLoadedDatasetIds.contains(
                  datasets[index].value.id,
                ),
                diskSaved: statusSnapshot.diskSavedDatasetIds.contains(
                  datasets[index].value.id,
                ),
                onDatasetNamePressed: () =>
                    onDatasetNamePressed(datasets[index].value.id),
                onCheckedChanged: (bool checked) {
                  final Set<String> nextSelection = Set<String>.from(
                    selectedDatasetIds,
                  );
                  if (checked) {
                    nextSelection.add(datasets[index].value.id);
                  } else {
                    nextSelection.remove(datasets[index].value.id);
                  }
                  onChanged(nextSelection);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
