import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'channel_coordinates_node.dart';
import 'node_type.dart';

class EditChannelsNodeType extends NodeType {
  @override
  String get title => 'Edit Channels';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  String get subcategory => 'Quality Control';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'channelEditsByDataset': <String, dynamic>{},
  };

  static const String coordinateImportNone = 'none';
  static const String coordinateImportStandard = 'standard';
  static const String rereferenceNone = 'none';
  static const String rereferenceAverage = 'average';

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    final List<dynamic> selectedDatasetIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final Dataset? visibleDataset = datasets.values
        .where(
          (Dataset dataset) =>
              dataset.timeSeries != null &&
              (selectedDatasetIds.isEmpty ||
                  selectedDatasetIds.contains(dataset.id)),
        )
        .cast<Dataset?>()
        .firstWhere((Dataset? dataset) => dataset != null, orElse: () => null);
    if (visibleDataset == null || visibleDataset.timeSeries == null) {
      return const Text(
        'Select a dataset with time-domain signal to edit channels.',
        style: TextStyle(color: Colors.black54),
      );
    }

    final TimeSeriesData timeSeries = visibleDataset.timeSeries!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          visibleDataset.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ChannelEditConfigEditor(
          channelLabels: _channelLabelsForSeries(timeSeries),
          config: configForDataset(params, visibleDataset.id),
          currentCoordinateCount: timeSeries.channelCoordinates.length,
          onChanged: (Map<String, dynamic> config) {
            setState(() {
              setConfigForDataset(params, visibleDataset.id, config);
            });
          },
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) {
      return;
    }

    final Map<String, dynamic> config = bindConfigToChannelLabels(
      configForDataset(params, dataset.id),
      _channelLabelsForSeries(timeSeries),
    );
    setConfigForDataset(params, dataset.id, config);
    if (!hasMeaningfulChanges(config)) {
      return;
    }

    final ArtifactChangeSet changeSet = changeSetForConfig(
      datasetId: dataset.id,
      timeSeries: timeSeries,
      config: config,
    );
    TimeSeriesData nextSeries = applyChannelEdits(
      timeSeries,
      config,
      warningSink: (String warning) {
        dataset.ram['editChannels.lastWarning'] = warning;
      },
    );
    final String coordinateImportMode =
        (config['coordinateImportMode'] ?? coordinateImportNone)
            .toString()
            .trim()
            .toLowerCase();
    if (coordinateImportMode == coordinateImportStandard) {
      nextSeries = await _applyConfiguredCoordinates(nextSeries);
    }
    dataset.timeSeries = nextSeries;
    dataset.ram['artifact.lastChangeSet'] = changeSet;
  }

  static Map<String, dynamic> configForDataset(
    Map<String, dynamic> params,
    String datasetId,
  ) {
    final Map<String, dynamic> allConfigs = Map<String, dynamic>.from(
      params['channelEditsByDataset'] as Map? ?? const <String, dynamic>{},
    );
    return _normalizeDatasetConfig(
      allConfigs[datasetId] is Map<String, dynamic>
          ? allConfigs[datasetId] as Map<String, dynamic>
          : null,
    );
  }

  static void setConfigForDataset(
    Map<String, dynamic> params,
    String datasetId,
    Map<String, dynamic> config,
  ) {
    final Map<String, dynamic> allConfigs = Map<String, dynamic>.from(
      params['channelEditsByDataset'] as Map? ?? const <String, dynamic>{},
    );
    allConfigs[datasetId] = _normalizeDatasetConfig(config);
    params['channelEditsByDataset'] = allConfigs;
  }

  static Map<String, dynamic> bindConfigToChannelLabels(
    Map<String, dynamic> config,
    List<String> channelLabels,
  ) {
    final Map<String, dynamic> normalized = _normalizeDatasetConfig(config);
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      normalized['edits'] as Map? ?? const <String, dynamic>{},
    );
    for (final MapEntry<String, dynamic> entry in edits.entries.toList(
      growable: false,
    )) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        entry.value as Map? ?? const <String, dynamic>{},
      );
      final int? index = int.tryParse(entry.key);
      if ((edit['sourceLabel'] ?? '').toString().trim().isEmpty &&
          index != null &&
          index >= 0 &&
          index < channelLabels.length) {
        edit['sourceLabel'] = channelLabels[index];
      }
      edits[entry.key] = edit;
    }
    normalized['edits'] = edits;
    return normalized;
  }

  static bool hasMeaningfulChanges(Map<String, dynamic> config) {
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      config['edits'] as Map? ?? const <String, dynamic>{},
    );
    final String coordinateImportMode =
        (config['coordinateImportMode'] ?? coordinateImportNone)
            .toString()
            .trim()
            .toLowerCase();
    final String rereferenceMode =
        (config['rereferenceMode'] ?? rereferenceNone)
            .toString()
            .trim()
            .toLowerCase();
    if (coordinateImportMode != coordinateImportNone ||
        rereferenceMode != rereferenceNone) {
      return true;
    }
    for (final dynamic rawValue in edits.values) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        rawValue as Map? ?? const <String, dynamic>{},
      );
      final String rename = (edit['rename'] ?? '').toString().trim();
      final bool remove = edit['remove'] == true;
      final String legacyPoolName = (edit['poolName'] ?? '').toString().trim();
      if (rename.isNotEmpty || remove || legacyPoolName.isNotEmpty) {
        return true;
      }
    }
    final List<Map<String, dynamic>> newChannels = _normalizeNewChannels(
      config['newChannels'] as List<dynamic>? ?? const <dynamic>[],
    );
    for (final Map<String, dynamic> entry in newChannels) {
      final String name = entry['name']?.toString().trim() ?? '';
      final List<int> add = _intList(entry['addSourceIndices']);
      final List<int> subtract = _intList(entry['subtractSourceIndices']);
      if (name.isNotEmpty || add.isNotEmpty || subtract.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static ArtifactChangeSet changeSetForConfig({
    required String datasetId,
    required TimeSeriesData timeSeries,
    required Map<String, dynamic> config,
    String? sourceNodeId,
    List<String> artifactIds = const <String>[],
  }) {
    final List<String> sourceLabels = _channelLabelsForSeries(timeSeries);
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      config['edits'] as Map? ?? const <String, dynamic>{},
    );
    final Set<ArtifactChangeType> changeTypes = <ArtifactChangeType>{};
    final Set<int> affectedIndices = <int>{};
    final Set<String> affectedLabels = <String>{};
    final String coordinateImportMode =
        (config['coordinateImportMode'] ?? coordinateImportNone)
            .toString()
            .trim()
            .toLowerCase();
    final String rereferenceMode =
        (config['rereferenceMode'] ?? rereferenceNone)
            .toString()
            .trim()
            .toLowerCase();

    final Map<int, Map<String, dynamic>> resolvedEdits = _resolvedEditsByIndex(
      sourceLabels,
      edits,
    );
    for (final MapEntry<int, Map<String, dynamic>> entry
        in resolvedEdits.entries) {
      final int index = entry.key;
      final Map<String, dynamic> edit = entry.value;
      final String rename = (edit['rename'] ?? '').toString().trim();
      final bool remove = edit['remove'] == true;
      final String removeMode = (edit['removeMode'] ?? 'delete')
          .toString()
          .trim()
          .toLowerCase();
      final String legacyPoolName = (edit['poolName'] ?? '').toString().trim();

      if (rename.isNotEmpty) {
        changeTypes.add(ArtifactChangeType.channelLabels);
        affectedIndices.add(index);
        affectedLabels.add(sourceLabels[index]);
      }
      if (remove && removeMode == 'delete') {
        changeTypes
          ..add(ArtifactChangeType.channelTopology)
          ..add(ArtifactChangeType.signalSamples);
        affectedIndices.add(index);
        affectedLabels.add(sourceLabels[index]);
      } else if (remove && removeMode == 'interpolate') {
        changeTypes.add(ArtifactChangeType.signalSamples);
        affectedIndices.add(index);
        affectedLabels.add(sourceLabels[index]);
      }
      if (legacyPoolName.isNotEmpty) {
        changeTypes
          ..add(ArtifactChangeType.channelTopology)
          ..add(ArtifactChangeType.signalSamples);
        affectedIndices.add(index);
        affectedLabels.add(sourceLabels[index]);
      }
    }

    final List<Map<String, dynamic>> newChannels = _normalizeNewChannels(
      config['newChannels'] as List<dynamic>? ?? const <dynamic>[],
    );
    for (final Map<String, dynamic> newChannel in newChannels) {
      final String name = (newChannel['name'] ?? '').toString().trim();
      final List<int> add = _intList(newChannel['addSourceIndices']);
      final List<int> subtract = _intList(newChannel['subtractSourceIndices']);
      if (name.isEmpty && add.isEmpty && subtract.isEmpty) {
        continue;
      }
      changeTypes
        ..add(ArtifactChangeType.channelTopology)
        ..add(ArtifactChangeType.signalSamples);
      for (final int index in <int>{...add, ...subtract}) {
        if (index >= 0 && index < sourceLabels.length) {
          affectedIndices.add(index);
          affectedLabels.add(sourceLabels[index]);
        }
      }
    }

    if (coordinateImportMode != coordinateImportNone) {
      changeTypes.add(ArtifactChangeType.channelCoordinates);
      affectedLabels.addAll(sourceLabels);
      affectedIndices.addAll(
        List<int>.generate(sourceLabels.length, (int index) => index),
      );
    }
    if (rereferenceMode != rereferenceNone) {
      changeTypes.add(ArtifactChangeType.signalSamples);
      affectedLabels.addAll(sourceLabels);
      affectedIndices.addAll(
        List<int>.generate(sourceLabels.length, (int index) => index),
      );
    }

    return ArtifactChangeSet(
      datasetId: datasetId,
      sourceNodeId: sourceNodeId,
      changeTypes: changeTypes,
      artifactIds: artifactIds,
      affectedChannelLabels: affectedLabels.toList(growable: false),
      affectedChannelIndices: affectedIndices.toList(growable: false),
      description: 'Edit Channels',
    );
  }

  static TimeSeriesData applyChannelEdits(
    TimeSeriesData timeSeries,
    Map<String, dynamic> config, {
    ValueChanged<String>? warningSink,
  }) {
    final List<List<double>> sourceChannels = timeSeries.channels
        .map(
          (List<double> channel) => List<double>.from(channel, growable: false),
        )
        .toList(growable: false);
    final List<String> sourceLabels = _channelLabelsForSeries(timeSeries);
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      config['edits'] as Map? ?? const <String, dynamic>{},
    );
    final String rereferenceMode =
        (config['rereferenceMode'] ?? rereferenceNone)
            .toString()
            .trim()
            .toLowerCase();
    final List<Map<String, dynamic>> newChannels = _normalizeNewChannels(
      config['newChannels'] as List<dynamic>? ?? const <dynamic>[],
    );
    final Map<int, Map<String, dynamic>> resolvedEdits = _resolvedEditsByIndex(
      sourceLabels,
      edits,
    );

    final Map<String, List<int>> legacyPoolAssignments = <String, List<int>>{};
    for (int index = 0; index < sourceLabels.length; index++) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        resolvedEdits[index] ?? const <String, dynamic>{},
      );
      final String poolName = (edit['poolName'] ?? '').toString().trim();
      if (poolName.isNotEmpty) {
        legacyPoolAssignments.putIfAbsent(poolName, () => <int>[]).add(index);
      }
    }

    final List<List<double>> outputChannels = <List<double>>[];
    final List<String> outputLabels = <String>[];
    final Map<String, ChannelCoordinate> outputCoordinates =
        <String, ChannelCoordinate>{};
    bool interpolateRequested = false;

    for (int index = 0; index < sourceChannels.length; index++) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        resolvedEdits[index] ?? const <String, dynamic>{},
      );
      final bool remove = edit['remove'] == true;
      final String removeMode = (edit['removeMode'] ?? 'delete')
          .toString()
          .trim()
          .toLowerCase();
      final String renamedLabel = (edit['rename'] ?? '').toString().trim();
      final String label = renamedLabel.isEmpty
          ? sourceLabels[index]
          : renamedLabel;

      if (remove && removeMode == 'delete') {
        continue;
      }
      if (remove && removeMode == 'interpolate') {
        interpolateRequested = true;
      }

      outputChannels.add(sourceChannels[index]);
      outputLabels.add(label);
      final ChannelCoordinate? coordinate =
          timeSeries.channelCoordinates[sourceLabels[index]];
      if (coordinate != null) {
        outputCoordinates[label] = ChannelCoordinate(
          label: label,
          x: coordinate.x,
          y: coordinate.y,
          z: coordinate.z,
          coordinateSystem: coordinate.coordinateSystem,
          units: coordinate.units,
        );
      }
    }

    for (final Map<String, dynamic> newChannel in newChannels) {
      final String name = (newChannel['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }
      final List<int> addIndices = _intList(newChannel['addSourceIndices']);
      final List<int> subtractIndices = _intList(
        newChannel['subtractSourceIndices'],
      );
      final bool normalize = newChannel['normalize'] == true;

      final List<int> effectiveAdd =
          addIndices.isNotEmpty || subtractIndices.isNotEmpty
          ? addIndices
          : (legacyPoolAssignments[name] ?? const <int>[]);
      final List<int> effectiveSubtract =
          addIndices.isNotEmpty || subtractIndices.isNotEmpty
          ? subtractIndices
          : const <int>[];
      final int totalInputs = effectiveAdd.length + effectiveSubtract.length;
      if (effectiveAdd.isEmpty && effectiveSubtract.isEmpty) {
        continue;
      }

      final int sampleCount = sourceChannels.first.length;
      final List<double> values = List<double>.filled(sampleCount, 0.0);
      for (final int sourceIndex in effectiveAdd) {
        final List<double> source = sourceChannels[sourceIndex];
        for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
          values[sampleIndex] += source[sampleIndex];
        }
      }
      for (final int sourceIndex in effectiveSubtract) {
        final List<double> source = sourceChannels[sourceIndex];
        for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
          values[sampleIndex] -= source[sampleIndex];
        }
      }
      if (normalize && totalInputs > 0) {
        for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
          values[sampleIndex] /= totalInputs;
        }
      }
      outputChannels.add(values);
      outputLabels.add(name);
    }

    if (rereferenceMode == rereferenceAverage) {
      _applyAverageReferenceInPlace(outputChannels);
    }

    if (interpolateRequested) {
      warningSink?.call(
        'Interpolation is not implemented yet, so interpolated channels were left unchanged.',
      );
    }

    return timeSeries.copyWith(
      channelSamples: outputChannels,
      channelLabels: outputLabels,
      channelCoordinates: outputCoordinates,
      source: timeSeries.source.isEmpty
          ? 'Edit Channels'
          : '${timeSeries.source} -> Edit Channels',
    );
  }

  static Map<String, dynamic> _normalizeDatasetConfig(
    Map<String, dynamic>? raw,
  ) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(
      raw ?? const <String, dynamic>{},
    );
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      map['edits'] as Map? ?? const <String, dynamic>{},
    );
    final List<Map<String, dynamic>> newChannels = _normalizeNewChannels(
      map['newChannels'] as List<dynamic>? ?? const <dynamic>[],
    );
    final List<int> visibleChannelIndices = _intList(
      map['visibleChannelIndices'] as List<dynamic>? ?? const <dynamic>[],
    );
    final String coordinateImportMode =
        (map['coordinateImportMode'] ?? coordinateImportNone).toString();
    final String rereferenceMode = (map['rereferenceMode'] ?? rereferenceNone)
        .toString();

    return <String, dynamic>{
      'edits': edits.map<String, dynamic>(
        (String key, dynamic value) => MapEntry<String, dynamic>(key, () {
          final Map<String, dynamic> valueMap = Map<String, dynamic>.from(
            value is Map ? value : const <String, dynamic>{},
          );
          return <String, dynamic>{
            'rename': valueMap['rename']?.toString() ?? '',
            'remove': valueMap['remove'] == true,
            'removeMode': (valueMap['removeMode'] ?? 'delete').toString(),
            'poolName': valueMap['poolName']?.toString() ?? '',
            'sourceLabel': valueMap['sourceLabel']?.toString() ?? '',
          };
        }()),
      ),
      'newChannels': newChannels,
      'visibleChannelIndices': visibleChannelIndices,
      'coordinateImportMode': coordinateImportMode,
      'rereferenceMode': rereferenceMode,
    };
  }

  static List<Map<String, dynamic>> _normalizeNewChannels(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((Map entry) {
          final Map<String, dynamic> map = Map<String, dynamic>.from(entry);
          return <String, dynamic>{
            'id': map['id']?.toString() ?? UniqueKey().toString(),
            'name': map['name']?.toString() ?? '',
            'addSourceIndices': _intList(
              map['addSourceIndices'] as List<dynamic>? ?? const <dynamic>[],
            ),
            'subtractSourceIndices': _intList(
              map['subtractSourceIndices'] as List<dynamic>? ??
                  const <dynamic>[],
            ),
            'normalize': map['normalize'] == true,
          };
        })
        .toList(growable: true);
  }

  static List<String> _channelLabelsForSeries(TimeSeriesData timeSeries) {
    if (timeSeries.channelLabels.length == timeSeries.channelCount) {
      return timeSeries.channelLabels;
    }
    return List<String>.generate(
      timeSeries.channelCount,
      (int index) => index < timeSeries.channelLabels.length
          ? timeSeries.channelLabels[index]
          : 'Ch ${index + 1}',
      growable: false,
    );
  }

  static Map<int, Map<String, dynamic>> resolvedEditsForSeries(
    TimeSeriesData timeSeries,
    Map<String, dynamic> config,
  ) {
    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      config['edits'] as Map? ?? const <String, dynamic>{},
    );
    return _resolvedEditsByIndex(_channelLabelsForSeries(timeSeries), edits);
  }

  static Map<int, Map<String, dynamic>> _resolvedEditsByIndex(
    List<String> sourceLabels,
    Map<String, dynamic> edits,
  ) {
    final Map<int, Map<String, dynamic>> resolved =
        <int, Map<String, dynamic>>{};
    for (final MapEntry<String, dynamic> entry in edits.entries) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        entry.value as Map? ?? const <String, dynamic>{},
      );
      final String sourceLabel = (edit['sourceLabel'] ?? '').toString().trim();
      final int index = sourceLabel.isEmpty
          ? (int.tryParse(entry.key) ?? -1)
          : sourceLabels.indexOf(sourceLabel);
      if (index < 0 || index >= sourceLabels.length) {
        continue;
      }
      resolved[index] = edit;
    }
    return resolved;
  }

  static List<int> _intList(dynamic raw) {
    return (raw as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic value) => (value as num).toInt())
        .toList(growable: false);
  }

  static Future<TimeSeriesData> _applyConfiguredCoordinates(
    TimeSeriesData timeSeries,
  ) async {
    final Map<String, ChannelCoordinate> standardCoordinates =
        ChannelCoordinatesNodeType.parseChannelCoordinateCsv(
          await rootBundle.loadString(
            ChannelCoordinatesNodeType.standardCoordinatesAsset,
          ),
        );
    final List<String> labels = _channelLabelsForSeries(timeSeries);
    final Map<String, ChannelCoordinate> next = <String, ChannelCoordinate>{
      ...timeSeries.channelCoordinates,
    };
    for (final String label in labels) {
      final ChannelCoordinate? coordinate =
          ChannelCoordinatesNodeType.coordinateForChannelLabel(
            standardCoordinates,
            label,
          );
      if (coordinate == null) {
        continue;
      }
      next[label] = ChannelCoordinate(
        label: label,
        x: coordinate.x,
        y: coordinate.y,
        z: coordinate.z,
        coordinateSystem: coordinate.coordinateSystem,
        units: coordinate.units,
      );
    }
    next.removeWhere(
      (String key, ChannelCoordinate _) => !labels.contains(key),
    );
    return timeSeries.copyWith(channelCoordinates: next);
  }

  static void _applyAverageReferenceInPlace(List<List<double>> channels) {
    if (channels.length < 2 || channels.isEmpty) {
      return;
    }
    final int sampleCount = channels.first.length;
    for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      double mean = 0.0;
      for (final List<double> channel in channels) {
        mean += channel[sampleIndex];
      }
      mean /= channels.length;
      for (final List<double> channel in channels) {
        channel[sampleIndex] -= mean;
      }
    }
  }
}

class ChannelEditConfigEditor extends StatefulWidget {
  const ChannelEditConfigEditor({
    super.key,
    required this.channelLabels,
    required this.config,
    required this.onChanged,
    this.initialVisibleChannelIndices,
    this.currentCoordinateCount = 0,
  });

  final List<String> channelLabels;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final List<int>? initialVisibleChannelIndices;
  final int currentCoordinateCount;

  @override
  State<ChannelEditConfigEditor> createState() =>
      _ChannelEditConfigEditorState();
}

class _ChannelEditConfigEditorState extends State<ChannelEditConfigEditor> {
  late Map<String, dynamic> _config;
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;
  final Map<String, TextEditingController> _renameControllers =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _newChannelControllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
    _config = EditChannelsNodeType._normalizeDatasetConfig(widget.config);
    _ensureVisibleChannelIndices();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant ChannelEditConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _config = EditChannelsNodeType._normalizeDatasetConfig(widget.config);
    _ensureVisibleChannelIndices();
    _syncControllers();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    for (final TextEditingController controller in _renameControllers.values) {
      controller.dispose();
    }
    for (final TextEditingController controller
        in _newChannelControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _edits => Map<String, dynamic>.from(
    _config['edits'] as Map? ?? const <String, dynamic>{},
  );

  List<Map<String, dynamic>> get _newChannels =>
      EditChannelsNodeType._normalizeNewChannels(
        _config['newChannels'] as List<dynamic>? ?? const <dynamic>[],
      );

  String get _coordinateImportMode =>
      (_config['coordinateImportMode'] ??
              EditChannelsNodeType.coordinateImportNone)
          .toString();

  String get _rereferenceMode =>
      (_config['rereferenceMode'] ?? EditChannelsNodeType.rereferenceNone)
          .toString();

  List<int> get _visibleChannelIndices {
    final List<int> configured =
        EditChannelsNodeType._intList(
              _config['visibleChannelIndices'] as List<dynamic>? ??
                  const <dynamic>[],
            )
            .where(
              (int index) => index >= 0 && index < widget.channelLabels.length,
            )
            .toList(growable: false);
    if (configured.isNotEmpty) {
      return configured;
    }
    if (widget.initialVisibleChannelIndices != null &&
        widget.initialVisibleChannelIndices!.isNotEmpty) {
      return widget.initialVisibleChannelIndices!
          .where(
            (int index) => index >= 0 && index < widget.channelLabels.length,
          )
          .toList(growable: false);
    }
    return List<int>.generate(
      widget.channelLabels.length,
      (int index) => index,
    );
  }

  List<int> get _remainingChannelIndices =>
      List<int>.generate(widget.channelLabels.length, (int index) => index)
          .where((int index) => !_visibleChannelIndices.contains(index))
          .toList(growable: false);

  void _ensureVisibleChannelIndices() {
    final List<int> configured = EditChannelsNodeType._intList(
      _config['visibleChannelIndices'] as List<dynamic>? ?? const <dynamic>[],
    );
    if (configured.isNotEmpty) {
      _config['visibleChannelIndices'] = <int>{
        ...configured,
        ...?widget.initialVisibleChannelIndices,
      }.toList()..sort();
      return;
    }
    _config['visibleChannelIndices'] =
        widget.initialVisibleChannelIndices != null &&
            widget.initialVisibleChannelIndices!.isNotEmpty
        ? widget.initialVisibleChannelIndices!
        : List<int>.generate(widget.channelLabels.length, (int index) => index);
  }

  void _syncControllers() {
    final Set<String> activeRenameKeys = Set<String>.from(
      widget.channelLabels.asMap().keys.map((int i) => '$i'),
    );
    for (final String key in _renameControllers.keys.toList(growable: false)) {
      if (!activeRenameKeys.contains(key)) {
        _renameControllers.remove(key)?.dispose();
      }
    }
    for (final String key in activeRenameKeys) {
      final String rename =
          (Map<String, dynamic>.from(
                    _edits[key] as Map? ?? const <String, dynamic>{},
                  )['rename'] ??
                  '')
              .toString();
      final TextEditingController controller = _renameControllers.putIfAbsent(
        key,
        () => TextEditingController(text: rename),
      );
      if (controller.text != rename) {
        controller.value = TextEditingValue(
          text: rename,
          selection: TextSelection.collapsed(offset: rename.length),
        );
      }
    }

    final Set<String> activeNewIds = Set<String>.from(
      _newChannels.map((Map<String, dynamic> row) => row['id'].toString()),
    );
    for (final String key in _newChannelControllers.keys.toList(
      growable: false,
    )) {
      if (!activeNewIds.contains(key)) {
        _newChannelControllers.remove(key)?.dispose();
      }
    }
    for (final Map<String, dynamic> row in _newChannels) {
      final String id = row['id'].toString();
      final String name = row['name']?.toString() ?? '';
      final TextEditingController controller = _newChannelControllers
          .putIfAbsent(id, () => TextEditingController(text: name));
      if (controller.text != name) {
        controller.value = TextEditingValue(
          text: name,
          selection: TextSelection.collapsed(offset: name.length),
        );
      }
    }
  }

  void _emitConfig() {
    widget.onChanged(EditChannelsNodeType._normalizeDatasetConfig(_config));
  }

  void _setVisibleChannelIndices(List<int> indices) {
    _config['visibleChannelIndices'] = indices.toList(growable: false);
    _emitConfig();
  }

  void _setCoordinateImportMode(String value) {
    _config['coordinateImportMode'] = value;
    _emitConfig();
  }

  void _setRereferenceMode(String value) {
    _config['rereferenceMode'] = value;
    _emitConfig();
  }

  void _updateExistingEdit(
    int index, {
    String? rename,
    bool? remove,
    String? removeMode,
  }) {
    final Map<String, dynamic> edits = _edits;
    final String key = '$index';
    final Map<String, dynamic> existing = Map<String, dynamic>.from(
      edits[key] as Map? ?? const <String, dynamic>{},
    );
    existing['sourceLabel'] = widget.channelLabels[index];
    if (rename != null) {
      existing['rename'] = rename;
    }
    if (remove != null) {
      existing['remove'] = remove;
    }
    if (removeMode != null) {
      existing['removeMode'] = removeMode;
    }
    edits[key] = existing;
    _config['edits'] = edits;
    _emitConfig();
  }

  void _updateNewChannelName(String id, String name) {
    final List<Map<String, dynamic>> rows = _newChannels;
    for (final Map<String, dynamic> row in rows) {
      if (row['id'].toString() == id) {
        row['name'] = name;
      }
    }
    _config['newChannels'] = rows;
    _emitConfig();
  }

  void _promoteOriginalChannelRow(int index) {
    final List<int> updated = <int>[..._visibleChannelIndices, index]..sort();
    _setVisibleChannelIndices(updated);
  }

  void _hideOriginalChannelRow(int index) {
    final List<int> updated = _visibleChannelIndices
        .where((int value) => value != index)
        .toList(growable: false);
    setState(() {
      _setVisibleChannelIndices(updated);
    });
  }

  void _addNewChannelRow() {
    final List<Map<String, dynamic>> rows = _newChannels;
    final Map<String, dynamic> row = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': '',
      'addSourceIndices': <int>[],
      'subtractSourceIndices': <int>[],
      'normalize': false,
    };
    rows.add(row);
    setState(() {
      _config['newChannels'] = rows;
      _syncControllers();
    });
    _emitConfig();
    _editFormulaRow(row);
  }

  void _removeNewChannelRow(String id) {
    final List<Map<String, dynamic>> rows = _newChannels
        .where((Map<String, dynamic> row) => row['id'].toString() != id)
        .toList(growable: true);
    setState(() {
      _config['newChannels'] = rows;
      _syncControllers();
    });
    _emitConfig();
  }

  Future<void> _editFormulaRow(Map<String, dynamic> row) async {
    final Map<String, dynamic>? updated =
        await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (BuildContext context) {
            return _NewChannelFormulaDialog(
              channelLabels: widget.channelLabels,
              channelName: row['name']?.toString() ?? '',
              addIndices: EditChannelsNodeType._intList(
                row['addSourceIndices'] as List<dynamic>? ?? const <dynamic>[],
              ),
              subtractIndices: EditChannelsNodeType._intList(
                row['subtractSourceIndices'] as List<dynamic>? ??
                    const <dynamic>[],
              ),
              normalize: row['normalize'] == true,
            );
          },
        );
    if (updated == null) {
      return;
    }
    final List<Map<String, dynamic>> rows = _newChannels;
    for (final Map<String, dynamic> candidate in rows) {
      if (candidate['id'].toString() == row['id'].toString()) {
        candidate['addSourceIndices'] = EditChannelsNodeType._intList(
          updated['addSourceIndices'] as List<dynamic>? ?? const <dynamic>[],
        );
        candidate['subtractSourceIndices'] = EditChannelsNodeType._intList(
          updated['subtractSourceIndices'] as List<dynamic>? ??
              const <dynamic>[],
        );
        candidate['normalize'] = updated['normalize'] == true;
      }
    }
    setState(() {
      _config['newChannels'] = rows;
    });
    _emitConfig();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalController,
            child: Scrollbar(
              controller: _horizontalController,
              thumbVisibility: true,
              notificationPredicate: (ScrollNotification notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(860, constraints.maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildMetadataControls(context),
                      const SizedBox(height: 12),
                      _buildHeaderRow(),
                      const SizedBox(height: 8),
                      ..._visibleChannelIndices.map(_buildExistingRow),
                      if (_remainingChannelIndices.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Divider(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Other channels',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._remainingChannelIndices.map(
                          (int index) => _buildExistingRow(
                            index,
                            promoteOnEdit: true,
                            showHideButton: false,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          const Text(
                            'New Channels',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Create derived channels from add/subtract formulas.',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._newChannels.map(_buildNewChannelRow),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addNewChannelRow,
                          icon: const Icon(Icons.add),
                          label: const Text('Add new channel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetadataControls(BuildContext context) {
    final String coordinateSummary = widget.currentCoordinateCount == 0
        ? 'No coordinates currently attached.'
        : '${widget.currentCoordinateCount} coordinate${widget.currentCoordinateCount == 1 ? '' : 's'} currently attached.';
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<String>(
            initialValue: _coordinateImportMode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Import channel coordinates',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: EditChannelsNodeType.coordinateImportNone,
                child: Text('No change'),
              ),
              DropdownMenuItem<String>(
                value: EditChannelsNodeType.coordinateImportStandard,
                child: Text('Assign standard coordinates'),
              ),
            ],
            onChanged: (String? value) {
              if (value == null) {
                return;
              }
              setState(() {
                _setCoordinateImportMode(value);
              });
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: _rereferenceMode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Rereference',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: EditChannelsNodeType.rereferenceNone,
                child: Text('No change'),
              ),
              DropdownMenuItem<String>(
                value: EditChannelsNodeType.rereferenceAverage,
                child: Text('Average reference'),
              ),
            ],
            onChanged: (String? value) {
              if (value == null) {
                return;
              }
              setState(() {
                _setRereferenceMode(value);
              });
            },
          ),
        ),
        Text(
          coordinateSummary,
          style: TextStyle(color: Colors.black.withValues(alpha: 0.62)),
        ),
      ],
    );
  }

  Widget _buildHeaderRow() {
    return const Row(
      children: <Widget>[
        _HeaderCell(width: 180, text: 'Original channel'),
        SizedBox(width: 10),
        _HeaderCell(width: 180, text: 'Rename'),
        SizedBox(width: 10),
        _HeaderCell(width: 400, text: 'Remove'),
        SizedBox(width: 10),
        _HeaderCell(width: 40, text: ''),
      ],
    );
  }

  Widget _buildExistingRow(
    int index, {
    bool promoteOnEdit = false,
    bool showHideButton = true,
  }) {
    final Map<String, dynamic> edit = Map<String, dynamic>.from(
      _edits['$index'] as Map? ?? const <String, dynamic>{},
    );
    final bool remove = edit['remove'] == true;
    final String removeMode = (edit['removeMode'] ?? 'delete')
        .toString()
        .trim()
        .toLowerCase();
    final TextEditingController controller =
        _renameControllers['$index'] ?? TextEditingController();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 180,
            child: Text(
              widget.channelLabels[index],
              style: const TextStyle(fontWeight: FontWeight.w500),
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
                  if (promoteOnEdit) {
                    _promoteOriginalChannelRow(index);
                  }
                  _updateExistingEdit(index, rename: value);
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 400,
            child: Row(
              children: <Widget>[
                Checkbox(
                  value: remove,
                  onChanged: (bool? value) {
                    setState(() {
                      if (promoteOnEdit) {
                        _promoteOriginalChannelRow(index);
                      }
                      _updateExistingEdit(index, remove: value == true);
                    });
                  },
                ),
                const Text('remove'),
                const SizedBox(width: 10),
                IgnorePointer(
                  ignoring: !remove,
                  child: Opacity(
                    opacity: remove ? 1.0 : 0.45,
                    child: RadioGroup<String>(
                      groupValue: removeMode,
                      onChanged: (String? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          if (promoteOnEdit) {
                            _promoteOriginalChannelRow(index);
                          }
                          _updateExistingEdit(index, removeMode: value);
                        });
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const <Widget>[
                          Radio<String>(
                            value: 'delete',
                            visualDensity: VisualDensity.compact,
                          ),
                          Text('delete'),
                          SizedBox(width: 8),
                          Radio<String>(
                            value: 'interpolate',
                            visualDensity: VisualDensity.compact,
                          ),
                          SizedBox(
                            width: 74,
                            child: Text(
                              'interpolate',
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: showHideButton
                ? Tooltip(
                    message: 'Move to other channels',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _visibleChannelIndices.length > 1
                          ? () => _hideOriginalChannelRow(index)
                          : null,
                      icon: const Icon(Icons.close),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNewChannelRow(Map<String, dynamic> row) {
    final String id = row['id'].toString();
    final TextEditingController controller =
        _newChannelControllers[id] ?? TextEditingController();
    final String formula = _formulaTextForChannel(row);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 180,
            child: _GlowTextField(
              controller: controller,
              hintText: 'New channel name',
              onChanged: (String value) {
                setState(() {
                  _updateNewChannelName(id, value);
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              formula,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.72),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => _editFormulaRow(row),
            child: const Text('Edit formula'),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Remove new channel',
            child: IconButton(
              onPressed: () => _removeNewChannelRow(id),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }

  String _formulaTextForChannel(Map<String, dynamic> row) {
    final List<int> add = EditChannelsNodeType._intList(
      row['addSourceIndices'] as List<dynamic>? ?? const <dynamic>[],
    );
    final List<int> subtract = EditChannelsNodeType._intList(
      row['subtractSourceIndices'] as List<dynamic>? ?? const <dynamic>[],
    );
    final bool normalize = row['normalize'] == true;
    if (add.isEmpty && subtract.isEmpty) {
      return 'No inputs selected';
    }
    final List<String> pieces = <String>[
      ...add.map((int index) => widget.channelLabels[index]),
      ...subtract.map((int index) => '-${widget.channelLabels[index]}'),
    ];
    final String formula = pieces.join(' + ').replaceAll('+ -', '- ');
    final int divisor = add.length + subtract.length;
    if (normalize && divisor > 0) {
      return '($formula) / $divisor';
    }
    return formula;
  }
}

class _NewChannelFormulaDialog extends StatefulWidget {
  const _NewChannelFormulaDialog({
    required this.channelLabels,
    required this.channelName,
    required this.addIndices,
    required this.subtractIndices,
    required this.normalize,
  });

  final List<String> channelLabels;
  final String channelName;
  final List<int> addIndices;
  final List<int> subtractIndices;
  final bool normalize;

  @override
  State<_NewChannelFormulaDialog> createState() =>
      _NewChannelFormulaDialogState();
}

class _NewChannelFormulaDialogState extends State<_NewChannelFormulaDialog> {
  late List<int> _addIndices;
  late List<int> _subtractIndices;
  late bool _normalize;
  final Set<int> _selectedMiddleIndices = <int>{};

  @override
  void initState() {
    super.initState();
    _addIndices = List<int>.from(widget.addIndices);
    _subtractIndices = List<int>.from(widget.subtractIndices);
    _normalize = widget.normalize;
  }

  List<int> get _availableIndices =>
      List<int>.generate(widget.channelLabels.length, (int index) => index)
          .where(
            (int index) =>
                !_addIndices.contains(index) &&
                !_subtractIndices.contains(index),
          )
          .toList(growable: false);

  void _moveSelectedTo(List<int> destination) {
    if (_selectedMiddleIndices.isEmpty) {
      return;
    }
    setState(() {
      destination.addAll(_selectedMiddleIndices);
      destination.sort();
      _selectedMiddleIndices.clear();
    });
  }

  void _removeFrom(List<int> source, int index) {
    setState(() {
      source.remove(index);
      _selectedMiddleIndices.remove(index);
    });
  }

  String get _formulaText {
    final List<String> pieces = <String>[
      ..._addIndices.map((int index) => widget.channelLabels[index]),
      ..._subtractIndices.map((int index) => '-${widget.channelLabels[index]}'),
    ];
    if (pieces.isEmpty) {
      return 'No inputs selected';
    }
    final String formula = pieces.join(' + ').replaceAll('+ -', '- ');
    final int divisor = _addIndices.length + _subtractIndices.length;
    if (_normalize && divisor > 0) {
      return '($formula) / $divisor';
    }
    return formula;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Center(
                child: Text(
                  widget.channelName.trim().isEmpty
                      ? 'Configure New Channel'
                      : 'Configure ${widget.channelName}',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _FormulaColumn(
                        title: 'Subtract',
                        color: Colors.red.shade100,
                        indices: _subtractIndices,
                        labels: widget.channelLabels,
                        onRemove: (int index) =>
                            _removeFrom(_subtractIndices, index),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Center(
                            child: Text(
                              'Available channels',
                              style: TextStyle(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                itemCount: _availableIndices.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final int channelIndex =
                                      _availableIndices[index];
                                  final bool selected = _selectedMiddleIndices
                                      .contains(channelIndex);
                                  return ListTile(
                                    dense: true,
                                    tileColor: selected
                                        ? Theme.of(context).colorScheme.primary
                                              .withValues(alpha: 0.22)
                                        : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: selected
                                          ? BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              width: 1.4,
                                            )
                                          : BorderSide.none,
                                    ),
                                    selected: selected,
                                    selectedTileColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.22),
                                    title: Text(
                                      widget.channelLabels[channelIndex],
                                      style: TextStyle(
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        if (selected) {
                                          _selectedMiddleIndices.remove(
                                            channelIndex,
                                          );
                                        } else {
                                          _selectedMiddleIndices.add(
                                            channelIndex,
                                          );
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              OutlinedButton.icon(
                                onPressed: _selectedMiddleIndices.isEmpty
                                    ? null
                                    : () => _moveSelectedTo(_subtractIndices),
                                icon: const Icon(Icons.west),
                                label: const Text('To subtract'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _selectedMiddleIndices.isEmpty
                                    ? null
                                    : () => _moveSelectedTo(_addIndices),
                                icon: const Icon(Icons.east),
                                label: const Text('To add'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FormulaColumn(
                        title: 'Add',
                        color: Colors.green.shade100,
                        indices: _addIndices,
                        labels: widget.channelLabels,
                        onRemove: (int index) =>
                            _removeFrom(_addIndices, index),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _normalize,
                title: const Text('Normalize / average'),
                onChanged: (bool? value) {
                  setState(() {
                    _normalize = value == true;
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Formula: $_formulaText',
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(<String, dynamic>{
                        'addSourceIndices': _addIndices,
                        'subtractSourceIndices': _subtractIndices,
                        'normalize': _normalize,
                      });
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormulaColumn extends StatelessWidget {
  const _FormulaColumn({
    required this.title,
    required this.color,
    required this.indices,
    required this.labels,
    required this.onRemove,
  });

  final String title;
  final Color color;
  final List<int> indices;
  final List<String> labels;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: indices.isEmpty
                ? Center(
                    child: Text(
                      'None',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  )
                : ListView(
                    children: indices
                        .map(
                          (int index) => ListTile(
                            dense: true,
                            title: Text(labels[index]),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              onPressed: () => onRemove(index),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ),
      ],
    );
  }
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
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.22),
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
  const _HeaderCell({required this.width, required this.text});

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
