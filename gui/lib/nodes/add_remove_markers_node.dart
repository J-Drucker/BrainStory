import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'channel_marker_edit_config_editor.dart';
import 'node_type.dart';

class MarkerBoundaryCombinationResult {
  const MarkerBoundaryCombinationResult({
    required this.markers,
    required this.combinedCount,
    required this.unmatchedStartCount,
    required this.unmatchedStopCount,
  });

  final List<TimeMarker> markers;
  final int combinedCount;
  final int unmatchedStartCount;
  final int unmatchedStopCount;
}

enum MarkerLogicMatchMode { firstSubsequent, mostRecent, withinWindow }

class AddRemoveMarkersNodeType extends NodeType {
  @override
  String get title => 'Edit Markers';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'markers': <Map<String, dynamic>>[],
    'applyEmptyMarkerSet': false,
    'markerEditOperations': <String, dynamic>{},
    'markerEditScope': 'all',
    'markerEditDatasetIds': <String>[],
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'markers', type: PortType.markers),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    final bool generatedMarkers = params['markerGenerator'] == 'fft_windows';
    if (generatedMarkers) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Label: ${params['generatedMarkerLabel'] ?? 'FFT Window'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            'Window: ${(params['windowWidthMs'] as num?)?.toDouble() ?? 1000.0} ms',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    final List<dynamic> selectedDatasetIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final Dataset? dataset = datasets.values
        .where(
          (Dataset item) =>
              item.timeSeries != null &&
              (selectedDatasetIds.isEmpty ||
                  selectedDatasetIds.contains(item.id)),
        )
        .cast<Dataset?>()
        .firstWhere((Dataset? item) => item != null, orElse: () => null);
    if (dataset == null || dataset.timeSeries == null) {
      return const Text('Select a dataset with markers to edit.');
    }
    final List<dynamic> rawMarkers =
        params['markers'] as List<dynamic>? ?? const <dynamic>[];
    final Map<String, dynamic> operations = Map<String, dynamic>.from(
      params['markerEditOperations'] as Map? ?? const <String, dynamic>{},
    );
    final List<TimeMarker> markers = operations.isNotEmpty
        ? dataset.timeSeries!.markers
        : ((params['applyEmptyMarkerSet'] as bool?) ?? false) ||
              rawMarkers.isNotEmpty
        ? markersForDataset(dataset.id, rawMarkers)
        : dataset.timeSeries!.markers;
    params.putIfAbsent('markerEditSourceDatasetId', () => dataset.id);
    return SizedBox(
      height: 590,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MarkerDatasetScopeControl(
            params: params,
            datasets: datasets,
            sourceDatasetId: dataset.id,
            onChanged: (VoidCallback change) => setState(change),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: MarkerLabelEditConfigEditor(
              markers: markers,
              initialOperations: operations,
              onOperationsChanged: (Map<String, dynamic> nextOperations) {
                setState(() {
                  params['markerEditOperations'] = nextOperations;
                  params['markerEditSourceDatasetId'] = dataset.id;
                });
              },
              onChanged: (List<TimeMarker> nextMarkers) {
                setState(() {
                  params['markers'] = nextMarkers
                      .map(
                        (TimeMarker marker) => <String, dynamic>{
                          ...marker.toJson(),
                          'datasetId': dataset.id,
                        },
                      )
                      .toList(growable: false);
                  params['applyEmptyMarkerSet'] = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return;
    }

    if (params['markerGenerator'] == 'fft_windows') {
      final List<TimeMarker> generatedMarkers = fftWindowMarkersForTimeSeries(
        timeSeries,
        label: params['generatedMarkerLabel']?.toString() ?? 'FFT Window',
        widthMs: (params['windowWidthMs'] as num?)?.toDouble() ?? 1000.0,
        overlapPercent:
            (params['windowOverlapPercent'] as num?)?.toDouble() ?? 0.0,
        durationMode: params['markerDurationMode']?.toString() ?? 'window',
      );
      dataset.timeSeries = timeSeries.copyWith(
        markers: <TimeMarker>[
          ...timeSeries.markers.where(
            (TimeMarker marker) =>
                marker.label !=
                (params['generatedMarkerLabel']?.toString() ?? 'FFT Window'),
          ),
          ...generatedMarkers,
        ],
      );
      return;
    }

    final Map<String, dynamic> operations = Map<String, dynamic>.from(
      params['markerEditOperations'] as Map? ?? const <String, dynamic>{},
    );
    final bool operationsApply = markerOperationsApplyToDataset(
      params,
      dataset.id,
    );
    final List<TimeMarker> editedMarkers = operations.isNotEmpty
        ? operationsApply
              ? applyMarkerEditOperations(timeSeries.markers, operations)
              : timeSeries.markers
        : markersForDataset(
            dataset.id,
            params['markers'] as List<dynamic>? ?? const <dynamic>[],
          );
    final bool applyEmptyMarkerSet =
        (params['applyEmptyMarkerSet'] as bool?) ?? false;
    final String sourceDatasetId =
        params['markerEditSourceDatasetId']?.toString() ?? dataset.id;
    final bool hasStoredRowsForDataset =
        (params['markers'] as List<dynamic>? ?? const <dynamic>[]).any(
          (dynamic raw) =>
              raw is Map && raw['datasetId']?.toString() == dataset.id,
        );
    if (operations.isEmpty &&
        !hasStoredRowsForDataset &&
        dataset.id != sourceDatasetId) {
      return;
    }
    if (operations.isEmpty && !applyEmptyMarkerSet && editedMarkers.isEmpty) {
      return;
    }
    dataset.timeSeries = timeSeries.copyWith(markers: editedMarkers);
  }

  static bool markerOperationsApplyToDataset(
    Map<String, dynamic> params,
    String datasetId,
  ) {
    final String scope = (params['markerEditScope'] ?? 'all').toString();
    if (scope == 'all') {
      return true;
    }
    final Set<String> selected =
        (params['markerEditDatasetIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toSet();
    final String sourceId =
        params['markerEditSourceDatasetId']?.toString() ?? '';
    return selected.isEmpty
        ? datasetId == sourceId
        : selected.contains(datasetId);
  }

  static List<TimeMarker> applyMarkerEditOperations(
    List<TimeMarker> markers,
    Map<String, dynamic> operations,
  ) {
    final Map<String, String> renames =
        Map<String, dynamic>.from(
          operations['renames'] as Map? ?? const <String, dynamic>{},
        ).map(
          (String key, dynamic value) =>
              MapEntry<String, String>(key, value.toString().trim()),
        );
    final Set<String> deleted =
        (operations['deletedLabels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toSet();
    List<TimeMarker> result = markers
        .where((TimeMarker marker) => !deleted.contains(marker.label))
        .map((TimeMarker marker) {
          final String replacement = renames[marker.label] ?? '';
          return replacement.isEmpty
              ? marker
              : marker.copyWith(label: replacement);
        })
        .toList(growable: false);

    for (final Map<dynamic, dynamic> rawRule
        in (operations['logicRules'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()) {
      final Map<String, dynamic> rule = Map<String, dynamic>.from(rawRule);
      final Set<String> timeLockLabels =
          (rule['timeLockLabels'] as List<dynamic>? ?? const <dynamic>[])
              .map(
                (dynamic value) =>
                    renames[value.toString()] ?? value.toString(),
              )
              .toSet();
      final Set<String> logicLabels =
          (rule['logicLabels'] as List<dynamic>? ?? const <dynamic>[])
              .map(
                (dynamic value) =>
                    renames[value.toString()] ?? value.toString(),
              )
              .toSet();
      final Map<String, String> rawRecode =
          Map<String, dynamic>.from(
            rule['recodeLabels'] as Map? ?? const <String, dynamic>{},
          ).map(
            (String key, dynamic value) =>
                MapEntry<String, String>(renames[key] ?? key, value.toString()),
          );
      final MarkerLogicMatchMode matchMode = MarkerLogicMatchMode.values
          .firstWhere(
            (MarkerLogicMatchMode mode) =>
                mode.name == rule['matchMode']?.toString(),
            orElse: () => MarkerLogicMatchMode.firstSubsequent,
          );
      result = recodeByMarkerLogic(
        result,
        timeLockLabels: timeLockLabels,
        logicLabels: logicLabels,
        recodeLabels: rawRecode,
        matchMode: matchMode,
        windowStartMs: (rule['windowStartMs'] as num?)?.toDouble() ?? 0,
        windowEndMs: (rule['windowEndMs'] as num?)?.toDouble() ?? 1000,
        keepOriginalMarkers: rule['keepOriginalMarkers'] == true,
      );
    }

    for (final Map<dynamic, dynamic> rawRule
        in (operations['boundaryRules'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()) {
      final Map<String, dynamic> rule = Map<String, dynamic>.from(rawRule);
      final String originalStart = rule['startLabel']?.toString() ?? '';
      final String originalStop = rule['stopLabel']?.toString() ?? '';
      result = combineBoundaryMarkers(
        result,
        startLabel: renames[originalStart] ?? originalStart,
        stopLabel: renames[originalStop] ?? originalStop,
        blockLabel: rule['blockLabel']?.toString() ?? '',
        replaceBoundaries: rule['replaceBoundaries'] != false,
      ).markers;
    }
    return result;
  }

  static MarkerBoundaryCombinationResult combineBoundaryMarkers(
    List<TimeMarker> markers, {
    required String startLabel,
    required String stopLabel,
    required String blockLabel,
    bool replaceBoundaries = true,
  }) {
    final String normalizedStart = startLabel.trim();
    final String normalizedStop = stopLabel.trim();
    final String normalizedBlock = blockLabel.trim();
    if (normalizedStart.isEmpty ||
        normalizedStop.isEmpty ||
        normalizedBlock.isEmpty ||
        normalizedStart == normalizedStop) {
      return MarkerBoundaryCombinationResult(
        markers: List<TimeMarker>.from(markers, growable: false),
        combinedCount: 0,
        unmatchedStartCount: markers
            .where((TimeMarker marker) => marker.label == normalizedStart)
            .length,
        unmatchedStopCount: markers
            .where((TimeMarker marker) => marker.label == normalizedStop)
            .length,
      );
    }

    final List<TimeMarker> ordered = List<TimeMarker>.from(markers)
      ..sort(
        (TimeMarker a, TimeMarker b) => a.onsetMicros.compareTo(b.onsetMicros),
      );
    final List<TimeMarker> openStarts = <TimeMarker>[];
    final Set<TimeMarker> consumed = Set<TimeMarker>.identity();
    final List<TimeMarker> blocks = <TimeMarker>[];
    int unmatchedStops = 0;

    for (final TimeMarker marker in ordered) {
      if (marker.label == normalizedStart) {
        openStarts.add(marker);
        continue;
      }
      if (marker.label != normalizedStop) {
        continue;
      }
      if (openStarts.isEmpty) {
        unmatchedStops += 1;
        continue;
      }
      final TimeMarker start = openStarts.removeAt(0);
      final int durationMicros = marker.onsetMicros - start.onsetMicros;
      if (durationMicros <= 0) {
        unmatchedStops += 1;
        openStarts.insert(0, start);
        continue;
      }
      consumed
        ..add(start)
        ..add(marker);
      blocks.add(
        TimeMarker(
          onsetMicros: start.onsetMicros,
          durationMicros: durationMicros,
          label: normalizedBlock,
          markerType: MarkerType.window,
          channelMask: start.channelMask,
          attributes: <String, dynamic>{
            ...start.attributes,
            'brainstory.boundaryStartLabel': normalizedStart,
            'brainstory.boundaryStopLabel': normalizedStop,
          },
        ),
      );
    }

    final List<TimeMarker> combined =
        <TimeMarker>[
          for (final TimeMarker marker in markers)
            if (!replaceBoundaries || !consumed.contains(marker)) marker,
          ...blocks,
        ]..sort(
          (TimeMarker a, TimeMarker b) =>
              a.onsetMicros.compareTo(b.onsetMicros),
        );
    return MarkerBoundaryCombinationResult(
      markers: List<TimeMarker>.from(combined, growable: false),
      combinedCount: blocks.length,
      unmatchedStartCount: openStarts.length,
      unmatchedStopCount: unmatchedStops,
    );
  }

  static List<TimeMarker> recodeByMarkerLogic(
    List<TimeMarker> markers, {
    required Set<String> timeLockLabels,
    required Set<String> logicLabels,
    required Map<String, String> recodeLabels,
    required MarkerLogicMatchMode matchMode,
    double windowStartMs = 0,
    double windowEndMs = 1000,
    bool keepOriginalMarkers = false,
  }) {
    if (timeLockLabels.isEmpty || logicLabels.isEmpty || recodeLabels.isEmpty) {
      return List<TimeMarker>.from(markers, growable: false);
    }

    final List<({int index, TimeMarker marker})> ordered =
        markers.indexed
            .map(
              ((int, TimeMarker) entry) => (index: entry.$1, marker: entry.$2),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final int byTime = a.marker.onsetMicros.compareTo(
              b.marker.onsetMicros,
            );
            return byTime != 0 ? byTime : a.index.compareTo(b.index);
          });
    final int windowStartMicros = (windowStartMs * 1000).round();
    final int windowEndMicros = (windowEndMs * 1000).round();
    final Map<int, TimeMarker> replacements = <int, TimeMarker>{};
    final List<TimeMarker> additions = <TimeMarker>[];

    for (final ({int index, TimeMarker marker}) anchor in ordered) {
      if (!timeLockLabels.contains(anchor.marker.label)) {
        continue;
      }
      final List<({int index, TimeMarker marker})> candidates = ordered
          .where((({int index, TimeMarker marker}) candidate) {
            if (candidate.index == anchor.index ||
                !logicLabels.contains(candidate.marker.label)) {
              return false;
            }
            final int relativeMicros =
                candidate.marker.onsetMicros - anchor.marker.onsetMicros;
            return switch (matchMode) {
              MarkerLogicMatchMode.firstSubsequent => relativeMicros > 0,
              MarkerLogicMatchMode.mostRecent => relativeMicros < 0,
              MarkerLogicMatchMode.withinWindow =>
                relativeMicros >= windowStartMicros &&
                    relativeMicros <= windowEndMicros,
            };
          })
          .toList(growable: false);
      if (candidates.isEmpty) {
        continue;
      }

      final ({int index, TimeMarker marker}) match = switch (matchMode) {
        MarkerLogicMatchMode.firstSubsequent => candidates.first,
        MarkerLogicMatchMode.mostRecent => candidates.last,
        MarkerLogicMatchMode.withinWindow => candidates.reduce((a, b) {
          final int aDistance =
              (a.marker.onsetMicros - anchor.marker.onsetMicros).abs();
          final int bDistance =
              (b.marker.onsetMicros - anchor.marker.onsetMicros).abs();
          return bDistance < aDistance ? b : a;
        }),
      };
      final String replacementLabel =
          recodeLabels[match.marker.label]?.trim() ?? '';
      if (replacementLabel.isEmpty) {
        continue;
      }
      final TimeMarker recoded = anchor.marker.copyWith(
        label: replacementLabel,
        attributes: <String, dynamic>{
          ...anchor.marker.attributes,
          'brainstory.logicMarkerLabel': match.marker.label,
          'brainstory.logicMarkerOnsetMicros': match.marker.onsetMicros,
          'brainstory.logicMatchMode': matchMode.name,
        },
      );
      if (keepOriginalMarkers) {
        additions.add(recoded);
      } else {
        replacements[anchor.index] = recoded;
      }
    }

    final List<({int index, TimeMarker marker})> result =
        <({int index, TimeMarker marker})>[
          for (final (int, TimeMarker) entry in markers.indexed)
            (index: entry.$1, marker: replacements[entry.$1] ?? entry.$2),
          for (int index = 0; index < additions.length; index++)
            (index: markers.length + index, marker: additions[index]),
        ]..sort((a, b) {
          final int byTime = a.marker.onsetMicros.compareTo(
            b.marker.onsetMicros,
          );
          return byTime != 0 ? byTime : a.index.compareTo(b.index);
        });
    return result.map((entry) => entry.marker).toList(growable: false);
  }

  static List<TimeMarker> markersForDataset(
    String datasetId,
    List<dynamic> rawMarkers,
  ) {
    return rawMarkers
        .whereType<Map<String, dynamic>>()
        .where(
          (Map<String, dynamic> marker) => marker['datasetId'] == datasetId,
        )
        .map((Map<String, dynamic> marker) {
          final Map<String, dynamic> payload = Map<String, dynamic>.from(
            marker,
          );
          payload.remove('datasetId');
          return TimeMarker.fromJson(payload);
        })
        .toList(growable: false);
  }

  static List<TimeMarker> fftWindowMarkersForTimeSeries(
    TimeSeriesData timeSeries, {
    required String label,
    required double widthMs,
    required double overlapPercent,
    required String durationMode,
  }) {
    final int sampleCount = timeSeries.sampleCount;
    final double sampleRate = timeSeries.sampleRate;
    if (sampleCount <= 0 || sampleRate <= 0) {
      return const <TimeMarker>[];
    }

    final int widthSamples = ((widthMs / 1000.0) * sampleRate).round().clamp(
      1,
      sampleCount,
    );
    final double overlapFraction = (overlapPercent / 100.0).clamp(0.0, 0.95);
    final int stepSamples = (widthSamples * (1.0 - overlapFraction))
        .round()
        .clamp(1, widthSamples);
    final int durationMicros = durationMode == 'window'
        ? ((widthSamples / sampleRate) * 1000000.0).round()
        : 0;

    final List<TimeMarker> markers = <TimeMarker>[];
    for (
      int startSample = 0;
      startSample + widthSamples <= sampleCount;
      startSample += stepSamples
    ) {
      markers.add(
        TimeMarker(
          onsetMicros: ((startSample / sampleRate) * 1000000.0).round(),
          durationMicros: durationMicros,
          label: label,
          markerType: MarkerType.window,
        ),
      );
    }

    if (markers.isEmpty) {
      markers.add(
        TimeMarker(
          onsetMicros: 0,
          durationMicros: durationMicros,
          label: label,
          markerType: MarkerType.window,
        ),
      );
    }
    return markers;
  }
}

class MarkerEditConfigEditor extends StatefulWidget {
  const MarkerEditConfigEditor({
    super.key,
    required this.rawMarkers,
    required this.datasets,
    required this.markerCount,
    required this.onChanged,
  });

  final List<dynamic> rawMarkers;
  final List<Dataset> datasets;
  final int markerCount;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<MarkerEditConfigEditor> createState() => _MarkerEditConfigEditorState();
}

class _MarkerEditConfigEditorState extends State<MarkerEditConfigEditor> {
  late List<Map<String, dynamic>> _markers;

  @override
  void initState() {
    super.initState();
    _markers = _normalizeMarkers(widget.rawMarkers);
  }

  @override
  void didUpdateWidget(covariant MarkerEditConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.rawMarkers, oldWidget.rawMarkers)) {
      _markers = _normalizeMarkers(widget.rawMarkers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${widget.markerCount} marker change${widget.markerCount == 1 ? '' : 's'} recorded',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (_markers.isEmpty)
          const Text('No markers are currently recorded.')
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const <DataColumn>[
                      DataColumn(label: Text('Dataset')),
                      DataColumn(label: Text('Label')),
                      DataColumn(label: Text('Onset s')),
                      DataColumn(label: Text('Duration s')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('')),
                    ],
                    rows: _markers
                        .asMap()
                        .entries
                        .map((MapEntry<int, Map<String, dynamic>> entry) {
                          return DataRow(
                            cells: <DataCell>[
                              DataCell(_datasetPicker(entry.key)),
                              DataCell(
                                _textField(entry.key, 'label', width: 150),
                              ),
                              DataCell(
                                _secondsField(
                                  entry.key,
                                  microsKey: 'onsetMicros',
                                  legacySecondsKey: 'timeSeconds',
                                ),
                              ),
                              DataCell(
                                _secondsField(
                                  entry.key,
                                  microsKey: 'durationMicros',
                                ),
                              ),
                              DataCell(_markerTypePicker(entry.key)),
                              DataCell(
                                IconButton(
                                  tooltip: 'Remove marker',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _removeMarker(entry.key),
                                ),
                              ),
                            ],
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _addMarker,
          icon: const Icon(Icons.add),
          label: const Text('Add marker'),
        ),
      ],
    );
  }

  Widget _datasetPicker(int index) {
    final List<Dataset> datasets = widget.datasets;
    final String fallbackDatasetId = datasets.isEmpty ? '' : datasets.first.id;
    final String value =
        _markers[index]['datasetId']?.toString() ?? fallbackDatasetId;
    if (datasets.isEmpty) {
      return const SizedBox(width: 120, child: Text('No dataset'));
    }
    return SizedBox(
      width: 150,
      child: DropdownButton<String>(
        value: datasets.any((Dataset dataset) => dataset.id == value)
            ? value
            : fallbackDatasetId,
        isExpanded: true,
        items: datasets
            .map(
              (Dataset dataset) => DropdownMenuItem<String>(
                value: dataset.id,
                child: Text(dataset.label, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        onChanged: (String? nextValue) {
          if (nextValue == null) {
            return;
          }
          _updateMarker(index, 'datasetId', nextValue);
        },
      ),
    );
  }

  Widget _markerTypePicker(int index) {
    final String value = (_markers[index]['markerType'] ?? MarkerType.event)
        .toString();
    return SizedBox(
      width: 120,
      child: DropdownButton<String>(
        value:
            <String>{
              MarkerType.event,
              MarkerType.window,
              MarkerType.artifact,
              MarkerType.segment,
            }.contains(value)
            ? value
            : MarkerType.event,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: MarkerType.event,
            child: Text('event'),
          ),
          DropdownMenuItem<String>(
            value: MarkerType.window,
            child: Text('window'),
          ),
          DropdownMenuItem<String>(
            value: MarkerType.artifact,
            child: Text('artifact'),
          ),
          DropdownMenuItem<String>(
            value: MarkerType.segment,
            child: Text('segment'),
          ),
        ],
        onChanged: (String? nextValue) {
          if (nextValue == null) {
            return;
          }
          _updateMarker(index, 'markerType', nextValue);
          _updateMarker(index, 'kind', nextValue, emit: false);
          _emit();
        },
      ),
    );
  }

  Widget _textField(int index, String key, {required double width}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey<String>('marker-$index-$key'),
        initialValue: _markers[index][key]?.toString() ?? '',
        decoration: const InputDecoration(isDense: true),
        onChanged: (String value) => _updateMarker(index, key, value),
      ),
    );
  }

  Widget _secondsField(
    int index, {
    required String microsKey,
    String? legacySecondsKey,
  }) {
    final int micros =
        (_markers[index][microsKey] as num?)?.round() ??
        (((_markers[index][legacySecondsKey] as num?)?.toDouble() ?? 0.0) *
                1000000.0)
            .round();
    return SizedBox(
      width: 90,
      child: TextFormField(
        key: ValueKey<String>('marker-$index-$microsKey'),
        initialValue: (micros / 1000000.0).toStringAsFixed(3),
        decoration: const InputDecoration(isDense: true),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (String value) {
          final double? seconds = double.tryParse(value);
          if (seconds == null) {
            return;
          }
          _updateMarker(index, microsKey, (seconds * 1000000.0).round());
          if (legacySecondsKey != null) {
            _updateMarker(index, legacySecondsKey, seconds, emit: false);
            _emit();
          }
        },
      ),
    );
  }

  void _addMarker() {
    final String datasetId = widget.datasets.isEmpty
        ? ''
        : widget.datasets.first.id;
    setState(() {
      _markers.add(<String, dynamic>{
        'datasetId': datasetId,
        'label': 'Marker',
        'onsetMicros': 0,
        'durationMicros': 0,
        'markerType': MarkerType.event,
        'kind': MarkerType.event,
        'channelMask': <int>[],
        'attributes': <String, dynamic>{},
      });
    });
    _emit();
  }

  void _removeMarker(int index) {
    setState(() {
      _markers.removeAt(index);
    });
    _emit();
  }

  void _updateMarker(int index, String key, dynamic value, {bool emit = true}) {
    setState(() {
      _markers[index] = <String, dynamic>{..._markers[index], key: value};
    });
    if (emit) {
      _emit();
    }
  }

  void _emit() {
    widget.onChanged(_markers.map(_normalizeMarker).toList(growable: false));
  }

  static List<Map<String, dynamic>> _normalizeMarkers(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((Map marker) {
          return _normalizeMarker(Map<String, dynamic>.from(marker));
        })
        .toList(growable: true);
  }

  static Map<String, dynamic> _normalizeMarker(Map<String, dynamic> marker) {
    final String markerType =
        marker['markerType']?.toString() ??
        marker['kind']?.toString() ??
        MarkerType.event;
    final int onsetMicros =
        (marker['onsetMicros'] as num?)?.round() ??
        (((marker['timeSeconds'] as num?)?.toDouble() ?? 0.0) * 1000000.0)
            .round();
    final int durationMicros = (marker['durationMicros'] as num?)?.round() ?? 0;
    return <String, dynamic>{
      'datasetId': marker['datasetId']?.toString() ?? '',
      'label': marker['label']?.toString() ?? '',
      'onsetMicros': onsetMicros,
      'durationMicros': durationMicros,
      'markerType': markerType,
      'kind': markerType,
      'channelMask':
          (marker['channelMask'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<num>()
              .map((num value) => value.toInt())
              .toList(growable: false),
      'attributes': Map<String, dynamic>.from(
        marker['attributes'] as Map? ?? const <String, dynamic>{},
      ),
      'timeSeconds': onsetMicros / 1000000.0,
    };
  }
}
