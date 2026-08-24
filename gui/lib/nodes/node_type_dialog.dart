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

  @override
  State<_NodeConfigDialog> createState() => _NodeConfigDialogState();
}

class _NodeConfigDialogState extends State<_NodeConfigDialog> {
  late Map<String, dynamic> localParams;
  bool _fullscreen = false;
  NodeDatasetStatusSnapshot? _statusSnapshot;

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
      content: SizedBox(width: 920, child: content),
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

    return SingleChildScrollView(
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
                localParams['selectedDatasetIds'] = nextSelection.toList();
              });
            },
          ),
        ],
      ),
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

class _DatasetControlSection extends StatefulWidget {
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
  State<_DatasetControlSection> createState() => _DatasetControlSectionState();
}

class _DatasetControlSectionState extends State<_DatasetControlSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.datasets.isEmpty) {
      return const Text('No datasets opened yet.');
    }

    final bool allChecked =
        widget.datasets.isNotEmpty &&
        widget.datasets.every((MapEntry<String, Dataset> entry) {
          return widget.selectedDatasetIds.contains(entry.value.id);
        });
    final int selectedCount = widget.datasets
        .where(
          (MapEntry<String, Dataset> entry) =>
              widget.selectedDatasetIds.contains(entry.value.id),
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
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Datasets',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$selectedCount/${widget.datasets.length}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  widget.onChanged(
                    allChecked
                        ? <String>{}
                        : widget.datasets
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
              for (
                int index = 0;
                index < widget.datasets.length;
                index++
              ) ...<Widget>[
                if (index > 0) const Divider(height: 14),
                _DatasetControlRow(
                  dataset: widget.datasets[index].value,
                  selected: widget.selectedDatasetIds.contains(
                    widget.datasets[index].value.id,
                  ),
                  sourceLabels:
                      widget.datasetSourceLabels[widget
                          .datasets[index]
                          .value
                          .id] ??
                      const <String>[],
                  processingState:
                      widget.statusSnapshot.processedDatasetStates[widget
                          .datasets[index]
                          .value
                          .id] ??
                      DatasetState.notReady,
                  ramLoaded: widget.statusSnapshot.ramLoadedDatasetIds.contains(
                    widget.datasets[index].value.id,
                  ),
                  diskSaved: widget.statusSnapshot.diskSavedDatasetIds.contains(
                    widget.datasets[index].value.id,
                  ),
                  onDatasetNamePressed: () => widget.onDatasetNamePressed(
                    widget.datasets[index].value.id,
                  ),
                  onCheckedChanged: (bool checked) {
                    final Set<String> nextSelection = Set<String>.from(
                      widget.selectedDatasetIds,
                    );
                    if (checked) {
                      nextSelection.add(widget.datasets[index].value.id);
                    } else {
                      nextSelection.remove(widget.datasets[index].value.id);
                    }
                    widget.onChanged(nextSelection);
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
