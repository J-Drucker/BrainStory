import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class RecodeMarkersNodeType extends NodeType {
  @override
  String get title => 'Recode Markers';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'recodeMap': <String, dynamic>{},
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
        PortSpec(name: 'markers', type: PortType.markers),
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
    params.putIfAbsent('recodeMap', () => <String, dynamic>{});
    final List<Dataset> datasetList = datasets.values.toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    final List<dynamic> selectedIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? <dynamic>[];
    final Dataset? activeDataset = _resolveActiveDataset(datasetList, selectedIds);
    final TimeSeriesData? timeSeries = activeDataset?.timeSeries;
    final List<_MarkerLabelRowModel> labels =
        _markerLabelRows(timeSeries?.markers ?? const <TimeMarker>[]);

    return SizedBox(
      width: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            activeDataset == null
                ? 'Recode marker labels for the first selected dataset.'
                : 'Recode marker labels for ${activeDataset.label}.',
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter a new label to recode it. Leave the textbox blank to ignore that marker label.',
          ),
          const SizedBox(height: 14),
          if (labels.isEmpty)
            const Text('No markers available from the selected upstream dataset.')
          else
            Expanded(
              child: ListView.separated(
                itemCount: labels.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final _MarkerLabelRowModel row = labels[index];
                  final Map<String, dynamic> recodeMap =
                      Map<String, dynamic>.from(params['recodeMap'] as Map? ?? <String, dynamic>{});
                  final String currentValue =
                      recodeMap[row.key]?.toString() ?? '';
                  final bool recoded = currentValue.trim().isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 110,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: recoded
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                recoded ? 'Recoding' : 'Ignoring',
                                style: TextStyle(
                                  color: recoded
                                      ? Colors.green.shade800
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${row.label} (${row.count})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RecodeMarkerTextField(
                            key: ValueKey<String>(row.key),
                            currentValue: currentValue,
                            hintText: 'New label',
                            onChanged: (String value) {
                              final Map<String, dynamic> nextMap =
                                  Map<String, dynamic>.from(
                                params['recodeMap'] as Map? ?? <String, dynamic>{},
                              );
                              if (value.trim().isEmpty) {
                                nextMap.remove(row.key);
                              } else {
                                nextMap[row.key] = value.trim();
                              }
                              params['recodeMap'] = nextMap;
                            },
                          ),
                        ),
                      ],
                    ),
                  );
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
    final Map<String, dynamic> recodeMap =
        Map<String, dynamic>.from(params['recodeMap'] as Map? ?? <String, dynamic>{});
    final List<TimeMarker> recodedMarkers = timeSeries.markers.map((TimeMarker marker) {
      final String replacement =
          recodeMap[markerKeyForMarker(marker)]?.toString().trim() ?? '';
      if (replacement.isEmpty) {
        return marker;
      }
      return marker.copyWith(label: replacement);
    }).toList(growable: false);
    dataset.timeSeries = timeSeries.copyWith(markers: recodedMarkers);
    dataset.ram['recode_markers.params'] = <String, dynamic>{
      'recodeMap': recodeMap,
    };
  }

  Dataset? _resolveActiveDataset(List<Dataset> datasets, List<dynamic> selectedIds) {
    if (datasets.isEmpty) {
      return null;
    }
    for (final dynamic id in selectedIds) {
      for (final Dataset dataset in datasets) {
        if (dataset.id == id) {
          return dataset;
        }
      }
    }
    return datasets.first;
  }
}

class _MarkerLabelRowModel {
  const _MarkerLabelRowModel({
    required this.key,
    required this.label,
    required this.count,
  });

  final String key;
  final String label;
  final int count;
}

List<_MarkerLabelRowModel> _markerLabelRows(List<TimeMarker> markers) {
  final Map<String, _MarkerLabelRowModel> rows = <String, _MarkerLabelRowModel>{};
  for (final TimeMarker marker in markers) {
    final String key = markerKeyForMarker(marker);
    final _MarkerLabelRowModel? existing = rows[key];
    rows[key] = _MarkerLabelRowModel(
      key: key,
      label: marker.label,
      count: (existing?.count ?? 0) + 1,
    );
  }
  final List<_MarkerLabelRowModel> sorted = rows.values.toList(growable: false)
    ..sort((_MarkerLabelRowModel a, _MarkerLabelRowModel b) => a.label.compareTo(b.label));
  return sorted;
}

class _RecodeMarkerTextField extends StatefulWidget {
  const _RecodeMarkerTextField({
    super.key,
    required this.currentValue,
    required this.hintText,
    required this.onChanged,
  });

  final String currentValue;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<_RecodeMarkerTextField> createState() => _RecodeMarkerTextFieldState();
}

class _RecodeMarkerTextFieldState extends State<_RecodeMarkerTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void didUpdateWidget(covariant _RecodeMarkerTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentValue != widget.currentValue &&
        _controller.text != widget.currentValue) {
      _controller.value = TextEditingValue(
        text: widget.currentValue,
        selection: TextSelection.collapsed(offset: widget.currentValue.length),
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
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}
