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
        'markerEdits': <String, dynamic>{},
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
    final List<Dataset> datasetList = datasets.values.toList()
      ..sort((Dataset a, Dataset b) => a.label.compareTo(b.label));
    final List<dynamic> selectedIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final Dataset? activeDataset = _resolveActiveDataset(datasetList, selectedIds);
    final TimeSeriesData? timeSeries = activeDataset?.timeSeries;
    final List<_MarkerLabelRowModel> labels =
        _markerLabelRows(timeSeries?.markers ?? const <TimeMarker>[]);
    if (activeDataset == null || timeSeries == null) {
      return const Text(
        'Select a dataset with markers to recode marker labels.',
        style: TextStyle(color: Colors.black54),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Editing marker-label workflow for ${activeDataset.label}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _MarkerRecodeConfigEditor(
          markerRows: labels,
          config: configForParams(params),
          onChanged: (Map<String, dynamic> config) {
            setState(() {
              params['markerEdits'] = _normalizeConfig(config);
            });
          },
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return;
    }
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      configForParams(params)['edits'] as Map? ?? const <String, dynamic>{},
    );
    if (edits.isEmpty) {
      return;
    }
    final List<TimeMarker> output = <TimeMarker>[];
    for (final TimeMarker marker in timeSeries.markers) {
      final String key = markerKeyForMarker(marker);
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        edits[key] as Map? ?? const <String, dynamic>{},
      );
      final bool remove = edit['remove'] == true;
      if (remove) {
        continue;
      }
      final String rename = (edit['rename'] ?? '').toString().trim();
      if (rename.isEmpty) {
        output.add(marker);
      } else {
        output.add(marker.copyWith(label: rename));
      }
    }
    dataset.timeSeries = timeSeries.copyWith(markers: output);
    dataset.ram['recode_markers.params'] = <String, dynamic>{
      'markerEdits': configForParams(params),
    };
  }

  static Map<String, dynamic> configForParams(Map<String, dynamic> params) {
    final Map<String, dynamic> legacyConfig = _legacyConfigFromParams(params);
    if (legacyConfig.isNotEmpty) {
      return legacyConfig;
    }
    return _normalizeConfig(
      params['markerEdits'] is Map<String, dynamic>
          ? params['markerEdits'] as Map<String, dynamic>
          : null,
    );
  }

  static Map<String, dynamic> _legacyConfigFromParams(Map<String, dynamic> params) {
    final Map<dynamic, dynamic> rawMap = params['recodeMap'] as Map? ?? const <dynamic, dynamic>{};
    if (rawMap.isEmpty) {
      return const <String, dynamic>{};
    }
    final Map<String, dynamic> edits = <String, dynamic>{};
    rawMap.forEach((dynamic rawKey, dynamic rawValue) {
      final String key = rawKey.toString();
      final String rename = rawValue?.toString().trim() ?? '';
      if (key.isEmpty || rename.isEmpty) {
        return;
      }
      edits[key] = <String, dynamic>{
        'rename': rename,
        'remove': false,
      };
    });
    if (edits.isEmpty) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{
      'edits': edits,
      'visibleMarkerKeys': edits.keys.toList(growable: false),
    };
  }

  static Map<String, dynamic> _normalizeConfig(Map<String, dynamic>? raw) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(
      raw ?? const <String, dynamic>{},
    );
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      map['edits'] as Map? ?? const <String, dynamic>{},
    );
    final List<String> visibleMarkerKeys =
        (map['visibleMarkerKeys'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .where((String value) => value.trim().isNotEmpty)
            .toList(growable: false);
    return <String, dynamic>{
      'edits': edits.map<String, dynamic>(
        (String key, dynamic value) => MapEntry<String, dynamic>(
          key,
          () {
            final Map<String, dynamic> valueMap = Map<String, dynamic>.from(
              value is Map ? value : const <String, dynamic>{},
            );
            return <String, dynamic>{
              'rename': valueMap['rename']?.toString() ?? '',
              'remove': valueMap['remove'] == true,
            };
          }(),
        ),
      ),
      'visibleMarkerKeys': visibleMarkerKeys,
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

class _MarkerRecodeConfigEditor extends StatefulWidget {
  const _MarkerRecodeConfigEditor({
    required this.markerRows,
    required this.config,
    required this.onChanged,
  });

  final List<_MarkerLabelRowModel> markerRows;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_MarkerRecodeConfigEditor> createState() => _MarkerRecodeConfigEditorState();
}

class _MarkerRecodeConfigEditorState extends State<_MarkerRecodeConfigEditor> {
  late Map<String, dynamic> _config;
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;
  final Map<String, TextEditingController> _renameControllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
    _config = RecodeMarkersNodeType._normalizeConfig(widget.config);
    _ensureVisibleMarkerKeys();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _MarkerRecodeConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _config = RecodeMarkersNodeType._normalizeConfig(widget.config);
    _ensureVisibleMarkerKeys();
    _syncControllers();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    for (final TextEditingController controller in _renameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _edits => Map<String, dynamic>.from(
        _config['edits'] as Map? ?? const <String, dynamic>{},
      );

  List<String> get _visibleMarkerKeys {
    final Set<String> validKeys = widget.markerRows
        .map((_MarkerLabelRowModel row) => row.key)
        .toSet();
    final List<String> configured =
        (_config['visibleMarkerKeys'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .where(validKeys.contains)
            .toList(growable: false);
    if (configured.isNotEmpty) {
      return configured;
    }
    return widget.markerRows.map((_MarkerLabelRowModel row) => row.key).toList(
          growable: false,
        );
  }

  List<String> get _remainingMarkerKeys {
    final Set<String> visible = _visibleMarkerKeys.toSet();
    return widget.markerRows
        .map((_MarkerLabelRowModel row) => row.key)
        .where((String key) => !visible.contains(key))
        .toList(growable: false);
  }

  void _ensureVisibleMarkerKeys() {
    if ((_config['visibleMarkerKeys'] as List<dynamic>? ?? const <dynamic>[])
        .isNotEmpty) {
      return;
    }
    _config['visibleMarkerKeys'] = widget.markerRows
        .map(( _MarkerLabelRowModel row) => row.key)
        .toList(growable: false);
  }

  void _syncControllers() {
    final Set<String> desiredKeys = widget.markerRows
        .map(( _MarkerLabelRowModel row) => row.key)
        .toSet();
    final List<String> obsoleteKeys = _renameControllers.keys
        .where((String key) => !desiredKeys.contains(key))
        .toList(growable: false);
    for (final String key in obsoleteKeys) {
      _renameControllers.remove(key)?.dispose();
    }
    for (final _MarkerLabelRowModel row in widget.markerRows) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        _edits[row.key] as Map? ?? const <String, dynamic>{},
      );
      final String rename = (edit['rename'] ?? '').toString();
      final TextEditingController controller =
          _renameControllers.putIfAbsent(
        row.key,
        () => TextEditingController(text: rename),
      );
      if (controller.text != rename) {
        controller.value = TextEditingValue(
          text: rename,
          selection: TextSelection.collapsed(offset: rename.length),
        );
      }
    }
  }

  void _notifyChanged() {
    widget.onChanged(RecodeMarkersNodeType._normalizeConfig(_config));
  }

  void _updateEdit(
    String key, {
    String? rename,
    bool? remove,
  }) {
    final Map<String, dynamic> edits = _edits;
    final Map<String, dynamic> next = Map<String, dynamic>.from(
      edits[key] as Map? ?? const <String, dynamic>{},
    );
    if (rename != null) {
      next['rename'] = rename;
    }
    if (remove != null) {
      next['remove'] = remove;
    }
    final String normalizedRename = (next['rename'] ?? '').toString().trim();
    final bool normalizedRemove = next['remove'] == true;
    if (normalizedRename.isEmpty && !normalizedRemove) {
      edits.remove(key);
    } else {
      edits[key] = <String, dynamic>{
        'rename': normalizedRename,
        'remove': normalizedRemove,
      };
    }
    _config['edits'] = edits;
    _notifyChanged();
  }

  void _hideMarkerRow(String key) {
    final List<String> visible = List<String>.from(_visibleMarkerKeys);
    visible.remove(key);
    setState(() {
      _config['visibleMarkerKeys'] = visible;
      _notifyChanged();
    });
  }

  void _showAllMarkerRows() {
    setState(() {
      _config['visibleMarkerKeys'] = widget.markerRows
          .map((_MarkerLabelRowModel row) => row.key)
          .toList(growable: false);
      _notifyChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.markerRows.isEmpty) {
      return const Text('No markers available from the selected upstream dataset.');
    }

    final Map<String, _MarkerLabelRowModel> rowsByKey = <String, _MarkerLabelRowModel>{
      for (final _MarkerLabelRowModel row in widget.markerRows) row.key: row,
    };
    final List<_MarkerLabelRowModel> visibleRows = _visibleMarkerKeys
        .map((String key) => rowsByKey[key])
        .whereType<_MarkerLabelRowModel>()
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Changes apply to all markers with the same label. Individual markers are not edited here.',
                style: TextStyle(color: Colors.black.withValues(alpha: 0.65)),
              ),
            ),
            if (_remainingMarkerKeys.isNotEmpty) ...<Widget>[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _showAllMarkerRows,
                child: const Text('Select all'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      _HeaderCell(width: 180, text: 'Original marker'),
                      SizedBox(width: 10),
                      _HeaderCell(width: 90, text: 'Count'),
                      SizedBox(width: 10),
                      _HeaderCell(width: 180, text: 'Rename'),
                      SizedBox(width: 10),
                      _HeaderCell(width: 180, text: 'Remove'),
                      SizedBox(width: 10),
                      SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Scrollbar(
                      controller: _verticalController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _verticalController,
                        shrinkWrap: true,
                        itemCount: visibleRows.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (BuildContext context, int index) {
                          return _buildMarkerRow(visibleRows[index]);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarkerRow(_MarkerLabelRowModel row) {
    final Map<String, dynamic> edit = Map<String, dynamic>.from(
      _edits[row.key] as Map? ?? const <String, dynamic>{},
    );
    final bool remove = edit['remove'] == true;
    final TextEditingController controller =
        _renameControllers[row.key] ?? TextEditingController();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 180,
            child: Text(
              row.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              '${row.count}',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.72)),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 180,
            child: _GlowTextField(
              controller: controller,
              hintText: 'Rename',
              onChanged: (String value) {
                setState(() {
                  _updateEdit(row.key, rename: value);
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 180,
            child: Row(
              children: <Widget>[
                Checkbox(
                  value: remove,
                  onChanged: (bool? value) {
                    setState(() {
                      _updateEdit(row.key, remove: value == true);
                    });
                  },
                ),
                const Text('remove label'),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: Tooltip(
              message: 'Hide this marker row',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _visibleMarkerKeys.length > 1
                    ? () => _hideMarkerRow(row.key)
                    : null,
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    );
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

class _GlowTextField extends StatelessWidget {
  const _GlowTextField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool active = controller.text.trim().isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.width,
    required this.text,
  });

  final double width;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }
}
