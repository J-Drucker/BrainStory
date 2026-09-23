import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
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
  static const String coordinateImportCustom = 'custom';
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
      return Builder(
        builder: (BuildContext context) => Text(
          'Select a dataset with time-domain signal to edit channels.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final TimeSeriesData timeSeries = visibleDataset.timeSeries!;
    params.putIfAbsent('channelEditSourceDatasetId', () => visibleDataset.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          visibleDataset.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ChannelEditConfigEditor(
          channelLabels: channelLabelsForEditor(
            configForDataset(params, visibleDataset.id),
            _channelLabelsForSeries(timeSeries),
          ),
          config: configForDataset(params, visibleDataset.id),
          currentCoordinates: timeSeries.channelCoordinates,
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
    final List<Map<String, dynamic>>? stages = combinedExecutionStages(params);
    if (stages != null) {
      for (final Map<String, dynamic> stage in stages) {
        await run(dataset, stage);
      }
      return;
    }
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    final SegmentedTimeSeriesData? segmented = dataset.segmentedTimeSeries;
    final TimeSeriesData? configSeries =
        timeSeries ??
        (segmented == null || segmented.segments.isEmpty
            ? null
            : TimeSeriesData(
                channelSamples: segmented.channelSamplesForSegment(
                  segmented.segments.first,
                ),
                sampleRate: segmented.sampleRate,
                channelLabels: segmented.channelLabels,
                source: segmented.source,
              ));
    if (configSeries == null || configSeries.channels.isEmpty) {
      return;
    }

    final List<String> inputLabels = _channelLabelsForSeries(configSeries);
    final Map<String, dynamic> ownConfig = bindConfigToChannelLabels(
      configForDataset(params, dataset.id),
      inputLabels,
    );
    final String sourceDatasetId =
        params['channelEditSourceDatasetId']?.toString() ?? dataset.id;
    if (dataset.id == sourceDatasetId || hasMeaningfulChanges(ownConfig)) {
      setConfigForDataset(params, dataset.id, ownConfig);
    }
    final Map<String, dynamic> config = bindConfigToChannelLabels(
      executionConfigForDataset(params, dataset.id),
      inputLabels,
    );
    if (!hasMeaningfulChanges(config)) {
      return;
    }

    final ArtifactChangeSet changeSet = changeSetForConfig(
      datasetId: dataset.id,
      timeSeries: configSeries,
      config: config,
    );
    final String coordinateImportMode =
        (config['coordinateImportMode'] ?? coordinateImportNone)
            .toString()
            .trim()
            .toLowerCase();
    final TimeSeriesData? editableSeries =
        timeSeries != null && coordinateImportMode == coordinateImportCustom
        ? applyCustomCoordinates(timeSeries, config)
        : timeSeries;
    TimeSeriesData? nextSeries = editableSeries == null
        ? null
        : applyChannelEdits(
            editableSeries,
            config,
            warningSink: (String warning) {
              dataset.ram['editChannels.lastWarning'] = warning;
            },
          );
    if (nextSeries != null) {
      if (coordinateImportMode == coordinateImportStandard) {
        nextSeries = await applyConfiguredCoordinates(nextSeries);
      }
    }
    if (nextSeries != null) {
      dataset.timeSeries = nextSeries;
    }
    if (segmented != null) {
      dataset.segmentedTimeSeries = applyChannelEditsToSegmented(
        segmented,
        config,
        sourceTimeSeries: nextSeries,
      );
    }
    dataset.ram['artifact.lastChangeSet'] = changeSet;
  }

  static SegmentedTimeSeriesData applyChannelEditsToSegmented(
    SegmentedTimeSeriesData segmented,
    Map<String, dynamic> config, {
    TimeSeriesData? sourceTimeSeries,
  }) {
    final List<SignalSegmentData> segments = segmented.segments
        .map((SignalSegmentData segment) {
          final TimeSeriesData edited = applyChannelEdits(
            TimeSeriesData(
              channelSamples: segmented.channelSamplesForSegment(segment),
              sampleRate: segmented.sampleRate,
              channelLabels: segmented.channelLabels,
              source: segmented.source,
            ),
            config,
          );
          return segment.copyWith(channelSamples: edited.channels);
        })
        .toList(growable: false);
    final TimeSeriesData labelSource =
        sourceTimeSeries ??
        applyChannelEdits(
          TimeSeriesData(
            channelSamples: segmented.channelSamplesForSegment(
              segmented.segments.first,
            ),
            sampleRate: segmented.sampleRate,
            channelLabels: segmented.channelLabels,
            source: segmented.source,
          ),
          config,
        );
    return segmented.copyWith(
      segments: segments,
      channelLabels: labelSource.channelLabels,
      sourceTimeSeries: sourceTimeSeries,
      clearSourceTimeSeries: sourceTimeSeries == null,
      source: segmented.source.isEmpty
          ? 'Edit Channels'
          : '${segmented.source} -> Edit Channels',
    );
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
    params.putIfAbsent('channelEditSourceDatasetId', () => datasetId);
  }

  static Map<String, dynamic> executionConfigForDataset(
    Map<String, dynamic> params,
    String datasetId,
  ) {
    final Map<String, dynamic> own = configForDataset(params, datasetId);
    final String sourceDatasetId =
        params['channelEditSourceDatasetId']?.toString() ??
        (Map<String, dynamic>.from(
              params['channelEditsByDataset'] as Map? ??
                  const <String, dynamic>{},
            ).keys.firstOrNull ??
            datasetId);
    final Map<String, dynamic> source = configForDataset(
      params,
      sourceDatasetId,
    );
    final Map<String, dynamic> mergedEdits = <String, dynamic>{};

    void mergeScopedEdits(
      Map<String, dynamic> config, {
      required bool includeDatasetSpecific,
    }) {
      final Map<String, dynamic> edits = Map<String, dynamic>.from(
        config['edits'] as Map? ?? const <String, dynamic>{},
      );
      for (final MapEntry<String, dynamic> entry in edits.entries) {
        final Map<String, dynamic> edit = Map<String, dynamic>.from(
          entry.value as Map? ?? const <String, dynamic>{},
        );
        final String rename = (edit['rename'] ?? '').toString().trim();
        final bool remove = edit['remove'] == true;
        final String removeMode = (edit['removeMode'] ?? 'delete')
            .toString()
            .trim()
            .toLowerCase();
        final String rowScope =
            (edit['datasetScope'] ??
                    (removeMode == 'interpolate' ? 'dataset' : 'all'))
                .toString();
        final bool rowApplies =
            rowScope == 'all' || datasetId == sourceDatasetId;
        final bool includeRename = rename.isNotEmpty && rowApplies;
        final bool includeRemoval = remove && rowApplies;
        final String poolName = includeDatasetSpecific
            ? (edit['poolName'] ?? '').toString()
            : '';
        if (!includeRename && !includeRemoval && poolName.trim().isEmpty) {
          continue;
        }
        final String sourceLabel = (edit['sourceLabel'] ?? '')
            .toString()
            .trim();
        final String identity = sourceLabel.isEmpty
            ? entry.key
            : 'label:$sourceLabel';
        final Map<String, dynamic> existing = Map<String, dynamic>.from(
          mergedEdits[identity] as Map? ?? const <String, dynamic>{},
        );
        mergedEdits[identity] = <String, dynamic>{
          ...existing,
          ...edit,
          'rename': includeRename
              ? rename
              : (existing['rename'] ?? '').toString(),
          'remove': includeRemoval || existing['remove'] == true,
          'removeMode': includeRemoval
              ? removeMode
              : (existing['removeMode'] ?? removeMode).toString(),
          'poolName': poolName.trim().isNotEmpty
              ? poolName
              : (existing['poolName'] ?? '').toString(),
        };
      }
    }

    if (datasetId != sourceDatasetId) {
      mergeScopedEdits(source, includeDatasetSpecific: false);
    }
    mergeScopedEdits(own, includeDatasetSpecific: true);
    final String sourceCoordinateImportMode =
        (source['coordinateImportMode'] ?? coordinateImportNone).toString();
    return <String, dynamic>{
      ...own,
      if (datasetId != sourceDatasetId &&
          sourceCoordinateImportMode != coordinateImportNone)
        'coordinateImportMode': sourceCoordinateImportMode,
      if (datasetId != sourceDatasetId &&
          sourceCoordinateImportMode == coordinateImportCustom)
        'customCoordinates': source['customCoordinates'],
      'edits': mergedEdits,
    };
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
    final List<String> sourceChannelLabels =
        (normalized['sourceChannelLabels'] as List<dynamic>? ??
                const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toList(growable: false);
    if (sourceChannelLabels.isEmpty) {
      normalized['sourceChannelLabels'] = List<String>.from(channelLabels);
    }
    return normalized;
  }

  static List<String> channelLabelsForEditor(
    Map<String, dynamic> config,
    List<String> currentLabels,
  ) {
    final Map<String, dynamic> normalized = _normalizeDatasetConfig(config);
    final List<String> stored =
        (normalized['sourceChannelLabels'] as List<dynamic>? ??
                const <dynamic>[])
            .map((dynamic value) => value.toString())
            .where((String value) => value.trim().isNotEmpty)
            .toList(growable: false);
    if (stored.isNotEmpty) {
      return stored;
    }

    final Map<String, dynamic> edits = Map<String, dynamic>.from(
      normalized['edits'] as Map? ?? const <String, dynamic>{},
    );
    final Map<int, String> fixedLabels = <int, String>{};
    final Set<String> editedOutputLabels = <String>{};
    for (final MapEntry<String, dynamic> entry in edits.entries) {
      final int? index = int.tryParse(entry.key);
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        entry.value as Map? ?? const <String, dynamic>{},
      );
      final String sourceLabel = (edit['sourceLabel'] ?? '').toString().trim();
      if (index != null && index >= 0 && sourceLabel.isNotEmpty) {
        fixedLabels[index] = sourceLabel;
      }
      final String rename = (edit['rename'] ?? '').toString().trim();
      if (rename.isNotEmpty) editedOutputLabels.add(rename);
    }
    if (fixedLabels.isEmpty) {
      return List<String>.from(currentLabels);
    }

    final Set<String> derivedLabels = _normalizeNewChannels(
      normalized['newChannels'] as List<dynamic>? ?? const <dynamic>[],
    ).map((Map<String, dynamic> row) => (row['name'] ?? '').toString()).toSet();
    final Set<String> fixedNames = fixedLabels.values.toSet();
    final List<String> remaining = currentLabels
        .where(
          (String label) =>
              !fixedNames.contains(label) &&
              !editedOutputLabels.contains(label) &&
              !derivedLabels.contains(label),
        )
        .toList(growable: true);
    final int missingDeletedLabels = edits.values.where((dynamic rawEdit) {
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        rawEdit as Map? ?? const <String, dynamic>{},
      );
      final String sourceLabel = (edit['sourceLabel'] ?? '').toString().trim();
      return edit['remove'] == true &&
          (edit['removeMode'] ?? 'delete').toString() == 'delete' &&
          sourceLabel.isNotEmpty &&
          !currentLabels.contains(sourceLabel);
    }).length;
    final int length = math.max(
      currentLabels.length + missingDeletedLabels,
      fixedLabels.keys.reduce(math.max) + 1,
    );
    return List<String>.generate(length, (int index) {
      final String? fixed = fixedLabels[index];
      if (fixed != null) return fixed;
      return remaining.isNotEmpty ? remaining.removeAt(0) : 'Ch ${index + 1}';
    });
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
    final List<String> outputSourceLabels = <String>[];
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
      outputSourceLabels.add(sourceLabels[index]);
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
      outputSourceLabels.add(name);
    }

    if (rereferenceMode == rereferenceAverage) {
      final Set<String> selectedReferenceLabels =
          (config['rereferenceChannelLabels'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((dynamic value) => value.toString())
              .toSet();
      final List<int> referenceIndices = <int>[
        for (int index = 0; index < outputLabels.length; index++)
          if (selectedReferenceLabels.isEmpty ||
              selectedReferenceLabels.contains(outputLabels[index]) ||
              selectedReferenceLabels.contains(outputSourceLabels[index]))
            index,
      ];
      _applyAverageReferenceInPlace(
        outputChannels,
        referenceIndices: referenceIndices,
      );
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
    final List<String> rereferenceChannelLabels =
        (map['rereferenceChannelLabels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toList(growable: false);
    final Map<String, dynamic> customCoordinates = Map<String, dynamic>.from(
      map['customCoordinates'] as Map? ?? const <String, dynamic>{},
    );
    final List<String> sourceChannelLabels =
        (map['sourceChannelLabels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toList(growable: false);

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
            'datasetScope':
                valueMap['datasetScope']?.toString() ??
                ((valueMap['removeMode'] ?? 'delete').toString() ==
                        'interpolate'
                    ? 'dataset'
                    : 'all'),
            'datasetScopeExplicit': valueMap['datasetScopeExplicit'] == true,
          };
        }()),
      ),
      'newChannels': newChannels,
      'visibleChannelIndices': visibleChannelIndices,
      'sourceChannelLabels': sourceChannelLabels,
      'coordinateImportMode': coordinateImportMode,
      'rereferenceMode': rereferenceMode,
      'rereferenceChannelLabels': rereferenceChannelLabels,
      'customCoordinates': customCoordinates,
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

  static Future<TimeSeriesData> applyConfiguredCoordinates(
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

  static TimeSeriesData applyCustomCoordinates(
    TimeSeriesData timeSeries,
    Map<String, dynamic> config,
  ) {
    final Map<String, dynamic> configured = Map<String, dynamic>.from(
      config['customCoordinates'] as Map? ?? const <String, dynamic>{},
    );
    final Map<String, ChannelCoordinate> next = <String, ChannelCoordinate>{
      ...timeSeries.channelCoordinates,
    };
    for (final String label in _channelLabelsForSeries(timeSeries)) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(
        configured[label] as Map? ?? const <String, dynamic>{},
      );
      final double? x = _coordinateNumber(row['x']);
      final double? y = _coordinateNumber(row['y']);
      final double? z = _coordinateNumber(row['z']);
      if (x == null || y == null || z == null) continue;
      final ChannelCoordinate? current = timeSeries.channelCoordinates[label];
      next[label] = ChannelCoordinate(
        label: label,
        x: x,
        y: y,
        z: z,
        coordinateSystem:
            row['coordinateSystem']?.toString() ??
            current?.coordinateSystem ??
            'custom',
        units: row['units']?.toString() ?? current?.units ?? 'mm',
      );
    }
    return timeSeries.copyWith(channelCoordinates: next);
  }

  static double? _coordinateNumber(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static void _applyAverageReferenceInPlace(
    List<List<double>> channels, {
    List<int>? referenceIndices,
  }) {
    final List<int> references =
        referenceIndices ??
        List<int>.generate(channels.length, (int index) => index);
    if (channels.isEmpty || references.isEmpty) {
      return;
    }
    final int sampleCount = channels.first.length;
    for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      double mean = 0.0;
      for (final int index in references) {
        mean += channels[index][sampleIndex];
      }
      mean /= references.length;
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
    this.currentCoordinates = const <String, ChannelCoordinate>{},
  });

  final List<String> channelLabels;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final List<int>? initialVisibleChannelIndices;
  final Map<String, ChannelCoordinate> currentCoordinates;

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
  final Map<String, List<TextEditingController>> _coordinateControllers =
      <String, List<TextEditingController>>{};
  int _channelSectionIndex = 0;
  String _sortMode = 'channelNumber';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
    _config = EditChannelsNodeType._normalizeDatasetConfig(widget.config);
    _ensureSourceChannelLabels();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant ChannelEditConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _config = EditChannelsNodeType._normalizeDatasetConfig(widget.config);
    _ensureSourceChannelLabels();
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
    for (final List<TextEditingController> controllers
        in _coordinateControllers.values) {
      for (final TextEditingController controller in controllers) {
        controller.dispose();
      }
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

  Set<String> get _rereferenceChannelLabels =>
      (_config['rereferenceChannelLabels'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toSet();

  Map<String, dynamic> get _customCoordinates => Map<String, dynamic>.from(
    _config['customCoordinates'] as Map? ?? const <String, dynamic>{},
  );

  List<int> get _alteredChannelIndices {
    final Set<int> altered = <int>{...?widget.initialVisibleChannelIndices};
    for (final MapEntry<String, dynamic> entry in _edits.entries) {
      final int? index = int.tryParse(entry.key);
      if (index == null || index < 0 || index >= widget.channelLabels.length) {
        continue;
      }
      final Map<String, dynamic> edit = Map<String, dynamic>.from(
        entry.value as Map? ?? const <String, dynamic>{},
      );
      if ((edit['rename'] ?? '').toString().trim().isNotEmpty ||
          edit['remove'] == true ||
          (edit['poolName'] ?? '').toString().trim().isNotEmpty) {
        altered.add(index);
      }
    }
    return _sortedChannelIndices
        .where((int index) => altered.contains(index))
        .toList(growable: false);
  }

  List<int> get _remainingChannelIndices {
    final Set<int> altered = _alteredChannelIndices.toSet();
    return _sortedChannelIndices
        .where((int index) => !altered.contains(index))
        .toList(growable: false);
  }

  void _ensureSourceChannelLabels() {
    final List<dynamic> stored =
        _config['sourceChannelLabels'] as List<dynamic>? ?? const <dynamic>[];
    if (stored.isEmpty) {
      _config['sourceChannelLabels'] = List<String>.from(widget.channelLabels);
    }
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
    final Set<String> activeLabels = widget.channelLabels.toSet();
    for (final String label in _coordinateControllers.keys.toList()) {
      if (!activeLabels.contains(label)) {
        for (final TextEditingController controller
            in _coordinateControllers.remove(label)!) {
          controller.dispose();
        }
      }
    }
    for (final String label in widget.channelLabels) {
      final Map<String, dynamic> configured = Map<String, dynamic>.from(
        _customCoordinates[label] as Map? ?? const <String, dynamic>{},
      );
      final List<String> values = <String>[
        (configured['x'] ?? '').toString(),
        (configured['y'] ?? '').toString(),
        (configured['z'] ?? '').toString(),
      ];
      final List<TextEditingController> controllers = _coordinateControllers
          .putIfAbsent(
            label,
            () => values
                .map((String value) => TextEditingController(text: value))
                .toList(growable: false),
          );
      for (int axis = 0; axis < 3; axis++) {
        if (controllers[axis].text != values[axis]) {
          controllers[axis].text = values[axis];
        }
      }
    }
  }

  void _emitConfig() {
    widget.onChanged(EditChannelsNodeType._normalizeDatasetConfig(_config));
  }

  void _updateExistingEdit(
    int index, {
    String? rename,
    bool? remove,
    String? removeMode,
    String? datasetScope,
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
      if (existing['datasetScopeExplicit'] != true) {
        existing['datasetScope'] = removeMode == 'interpolate'
            ? 'dataset'
            : 'all';
      }
    }
    if (datasetScope != null) {
      existing['datasetScope'] = datasetScope;
      existing['datasetScopeExplicit'] = true;
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

  List<int> get _sortedChannelIndices {
    final List<int> indices = List<int>.generate(
      widget.channelLabels.length,
      (int index) => index,
    );
    double? axisValue(int index) {
      final String label = widget.channelLabels[index];
      final Map<String, dynamic> custom = Map<String, dynamic>.from(
        _customCoordinates[label] as Map? ?? const <String, dynamic>{},
      );
      final ChannelCoordinate? current =
          ChannelCoordinatesNodeType.coordinateForChannelLabel(
            widget.currentCoordinates,
            label,
          );
      return switch (_sortMode) {
        'x' => EditChannelsNodeType._coordinateNumber(
          custom['x'] ?? current?.x,
        ),
        'y' => EditChannelsNodeType._coordinateNumber(
          custom['y'] ?? current?.y,
        ),
        'z' => EditChannelsNodeType._coordinateNumber(
          custom['z'] ?? current?.z,
        ),
        _ => null,
      };
    }

    indices.sort((int a, int b) {
      if (_sortMode == 'channelNumber') {
        return _sortAscending ? a.compareTo(b) : b.compareTo(a);
      }
      if (_sortMode == 'name') {
        final int comparison = widget.channelLabels[a].toLowerCase().compareTo(
          widget.channelLabels[b].toLowerCase(),
        );
        return _sortAscending ? comparison : -comparison;
      }
      final double? av = axisValue(a);
      final double? bv = axisValue(b);
      if (av == null && bv == null) return a.compareTo(b);
      if (av == null) return 1;
      if (bv == null) return -1;
      final int comparison = av.compareTo(bv);
      if (comparison == 0) return a.compareTo(b);
      return _sortAscending ? comparison : -comparison;
    });
    return indices;
  }

  void _sortBy(String column) {
    setState(() {
      if (_sortMode == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortMode = column;
        _sortAscending = true;
      }
    });
  }

  void _setReferenceChannel(String label, bool selected) {
    final Set<String> labels = _rereferenceChannelLabels;
    selected ? labels.add(label) : labels.remove(label);
    _config['rereferenceChannelLabels'] = labels.toList(growable: false);
    _config['rereferenceMode'] = labels.isEmpty
        ? EditChannelsNodeType.rereferenceNone
        : EditChannelsNodeType.rereferenceAverage;
    _emitConfig();
  }

  void _setAllReferenceChannels(bool selected) {
    _config['rereferenceChannelLabels'] = selected
        ? List<String>.from(widget.channelLabels)
        : <String>[];
    _config['rereferenceMode'] = selected
        ? EditChannelsNodeType.rereferenceAverage
        : EditChannelsNodeType.rereferenceNone;
    _emitConfig();
  }

  void _updateCoordinate(String label, int axis, String value) {
    final Map<String, dynamic> coordinates = _customCoordinates;
    final List<TextEditingController> controllers =
        _coordinateControllers[label]!;
    final ChannelCoordinate? current =
        ChannelCoordinatesNodeType.coordinateForChannelLabel(
          widget.currentCoordinates,
          label,
        );
    coordinates[label] = <String, dynamic>{
      'x': axis == 0 ? value : controllers[0].text,
      'y': axis == 1 ? value : controllers[1].text,
      'z': axis == 2 ? value : controllers[2].text,
      'coordinateSystem': current?.coordinateSystem ?? 'custom',
      'units': current?.units ?? 'mm',
    };
    _config['customCoordinates'] = coordinates;
    _config['coordinateImportMode'] =
        EditChannelsNodeType.coordinateImportCustom;
    _emitConfig();
  }

  Future<void> _assignStandardCoordinates() async {
    final Map<String, ChannelCoordinate> standard =
        ChannelCoordinatesNodeType.parseChannelCoordinateCsv(
          await rootBundle.loadString(
            ChannelCoordinatesNodeType.standardCoordinatesAsset,
          ),
        );
    _applyCoordinateMap(standard);
  }

  Future<void> _loadCoordinatesFromFile() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'Channel coordinates',
          extensions: <String>['csv', 'tsv', 'txt'],
        ),
      ],
    );
    if (file == null) return;
    final String payload = await file.readAsString();
    final Map<String, ChannelCoordinate> parsed =
        ChannelCoordinatesNodeType.parseChannelCoordinateCsv(
          payload.replaceAll('\t', ','),
        );
    if (parsed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid channel coordinates found.')),
        );
      }
      return;
    }
    _applyCoordinateMap(parsed);
  }

  void _applyCoordinateMap(Map<String, ChannelCoordinate> coordinates) {
    final Map<String, dynamic> configured = _customCoordinates;
    for (final String label in widget.channelLabels) {
      final ChannelCoordinate? coordinate =
          ChannelCoordinatesNodeType.coordinateForChannelLabel(
            coordinates,
            label,
          );
      if (coordinate == null) continue;
      configured[label] = <String, dynamic>{
        'x': coordinate.x,
        'y': coordinate.y,
        'z': coordinate.z,
        'coordinateSystem': coordinate.coordinateSystem,
        'units': coordinate.units,
      };
    }
    setState(() {
      _config['customCoordinates'] = configured;
      _config['coordinateImportMode'] =
          EditChannelsNodeType.coordinateImportCustom;
      _syncControllers();
    });
    _emitConfig();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TabBar(
            onTap: (int index) => setState(() {
              _channelSectionIndex = index;
            }),
            tabs: const <Tab>[
              Tab(text: 'Edit channels'),
              Tab(text: 'Rereference'),
              Tab(text: 'Coordinates'),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: IndexedStack(
              index: _channelSectionIndex,
              children: <Widget>[
                _buildEditChannelsPanel(),
                _buildRereferencePanel(),
                _buildCoordinatesPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditChannelsPanel() {
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
                  width: math.max(1320, constraints.maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildHeaderRow(),
                      const SizedBox(height: 8),
                      Text(
                        'Altered channels',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_alteredChannelIndices.isEmpty)
                        Text(
                          'No altered channels.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        )
                      else
                        ..._alteredChannelIndices.map(_buildExistingRow),
                      if (_remainingChannelIndices.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Other channels',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._remainingChannelIndices.map(
                          (int index) => _buildExistingRow(index),
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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

  Widget _buildRereferencePanel() {
    final Set<String> selected = _rereferenceChannelLabels;
    final bool allSelected =
        selected.length == widget.channelLabels.length && selected.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ..._channelHeaderCells(),
            const SizedBox(width: 12),
            const _HeaderCell(width: 90, text: 'Reference'),
          ],
        ),
        const SizedBox(height: 6),
        const Divider(height: 1),
        SizedBox(
          height: 38,
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: 406,
                child: Text(
                  'All channels',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Checkbox(
                value: allSelected,
                tristate: selected.isNotEmpty && !allSelected,
                onChanged: (bool? value) {
                  setState(() => _setAllReferenceChannels(value == true));
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _sortedChannelIndices.length,
            itemExtent: 40,
            itemBuilder: (BuildContext context, int row) {
              final int index = _sortedChannelIndices[row];
              final String label = widget.channelLabels[index];
              return Row(
                children: <Widget>[
                  ..._channelIdentityCells(index),
                  const SizedBox(width: 12),
                  Checkbox(
                    value: selected.contains(label),
                    onChanged: (bool? value) {
                      setState(
                        () => _setReferenceChannel(label, value == true),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCoordinatesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _assignStandardCoordinates,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Assign standard'),
            ),
            OutlinedButton.icon(
              onPressed: _loadCoordinatesFromFile,
              icon: const Icon(Icons.file_open, size: 18),
              label: const Text('Load coordinates from file'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            ..._channelHeaderCells(),
            const SizedBox(width: 12),
            const _HeaderCell(width: 96, text: 'New X'),
            const SizedBox(width: 8),
            const _HeaderCell(width: 96, text: 'New Y'),
            const SizedBox(width: 8),
            const _HeaderCell(width: 96, text: 'New Z'),
          ],
        ),
        const SizedBox(height: 6),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _sortedChannelIndices.length,
            itemExtent: 48,
            itemBuilder: (BuildContext context, int row) {
              return _buildCoordinateRow(_sortedChannelIndices[row]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCoordinateRow(int index) {
    final String label = widget.channelLabels[index];
    final List<TextEditingController> controllers =
        _coordinateControllers[label]!;
    return Row(
      children: <Widget>[
        ..._channelIdentityCells(index),
        const SizedBox(width: 12),
        for (int axis = 0; axis < 3; axis++) ...<Widget>[
          SizedBox(
            width: 96,
            child: TextField(
              controller: controllers[axis],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[-+0-9.eE]')),
              ],
              decoration: InputDecoration(
                labelText: const <String>['X', 'Y', 'Z'][axis],
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (String value) =>
                  _updateCoordinate(label, axis, value),
            ),
          ),
          if (axis < 2) const SizedBox(width: 8),
        ],
      ],
    );
  }

  String _coordinateText(double value) {
    final String fixed = value.toStringAsFixed(3);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  double? _channelCoordinateValue(int index, String axis) {
    final String label = widget.channelLabels[index];
    final Map<String, dynamic> custom = Map<String, dynamic>.from(
      _customCoordinates[label] as Map? ?? const <String, dynamic>{},
    );
    final ChannelCoordinate? current =
        ChannelCoordinatesNodeType.coordinateForChannelLabel(
          widget.currentCoordinates,
          label,
        );
    return EditChannelsNodeType._coordinateNumber(
      custom[axis] ??
          switch (axis) {
            'x' => current?.x,
            'y' => current?.y,
            'z' => current?.z,
            _ => null,
          },
    );
  }

  String _channelCoordinateText(int index, String axis) {
    final double? value = _channelCoordinateValue(index, axis);
    return value == null ? '-' : _coordinateText(value);
  }

  List<Widget> _channelHeaderCells() => <Widget>[
    _SortableHeaderCell(
      width: 58,
      text: 'Ch#',
      selected: _sortMode == 'channelNumber',
      ascending: _sortAscending,
      onTap: () => _sortBy('channelNumber'),
    ),
    const SizedBox(width: 8),
    _SortableHeaderCell(
      width: 120,
      text: 'Name',
      selected: _sortMode == 'name',
      ascending: _sortAscending,
      onTap: () => _sortBy('name'),
    ),
    for (final String axis in const <String>['x', 'y', 'z']) ...<Widget>[
      const SizedBox(width: 8),
      _SortableHeaderCell(
        width: 68,
        text: axis.toUpperCase(),
        selected: _sortMode == axis,
        ascending: _sortAscending,
        onTap: () => _sortBy(axis),
      ),
    ],
  ];

  List<Widget> _channelIdentityCells(int index) => <Widget>[
    SizedBox(width: 58, child: Text('${index + 1}')),
    const SizedBox(width: 8),
    SizedBox(
      width: 120,
      child: Text(
        widget.channelLabels[index],
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    for (final String axis in const <String>['x', 'y', 'z']) ...<Widget>[
      const SizedBox(width: 8),
      SizedBox(width: 68, child: Text(_channelCoordinateText(index, axis))),
    ],
  ];

  Widget _buildHeaderRow() {
    return Row(
      children: <Widget>[
        ..._channelHeaderCells(),
        const SizedBox(width: 10),
        const _HeaderCell(width: 180, text: 'Rename'),
        const SizedBox(width: 10),
        const _HeaderCell(width: 310, text: 'Remove'),
        const SizedBox(width: 10),
        const _HeaderCell(width: 210, text: 'Apply to'),
        const SizedBox(width: 10),
        const _HeaderCell(width: 40, text: ''),
      ],
    );
  }

  Widget _buildExistingRow(int index) {
    final Map<String, dynamic> edit = Map<String, dynamic>.from(
      _edits['$index'] as Map? ?? const <String, dynamic>{},
    );
    final bool remove = edit['remove'] == true;
    final String removeMode = (edit['removeMode'] ?? 'delete')
        .toString()
        .trim()
        .toLowerCase();
    final String datasetScope =
        (edit['datasetScope'] ??
                (removeMode == 'interpolate' ? 'dataset' : 'all'))
            .toString();
    final TextEditingController controller =
        _renameControllers['$index'] ?? TextEditingController();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ..._channelIdentityCells(index),
          const SizedBox(width: 10),
          SizedBox(
            width: 180,
            child: _GlowTextField(
              controller: controller,
              hintText: 'Rename',
              onChanged: (String value) {
                setState(() {
                  _updateExistingEdit(index, rename: value);
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 310,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Checkbox(
                    value: remove,
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (bool? value) {
                      setState(() {
                        _updateExistingEdit(index, remove: value == true);
                      });
                    },
                  ),
                ),
                const Text('remove'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: removeMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'delete', child: Text('Delete')),
                      DropdownMenuItem(
                        value: 'interpolate',
                        child: Text('Interpolate'),
                      ),
                    ],
                    onChanged: remove
                        ? (String? value) {
                            if (value == null) return;
                            setState(() {
                              _updateExistingEdit(index, removeMode: value);
                            });
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: datasetScope,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'dataset',
                  child: Text('This dataset'),
                ),
                DropdownMenuItem<String>(
                  value: 'all',
                  child: Text('All datasets'),
                ),
              ],
              onChanged: (String? value) {
                if (value == null) return;
                setState(() {
                  _updateExistingEdit(index, datasetScope: value);
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 40, child: const SizedBox.shrink()),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _SortableHeaderCell extends StatelessWidget {
  const _SortableHeaderCell({
    required this.width,
    required this.text,
    required this.selected,
    required this.ascending,
    required this.onTap,
  });

  final double width;
  final String text;
  final bool selected;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: 2),
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
