import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/brainstory_engine.dart';
import 'channel_coordinates_node.dart';
import 'node_type.dart';

abstract class _MatrixTransformNodeType extends NodeType {
  String get methodName;
  String get description;

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Matrix Transformation';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'componentCount': 8,
    'whiten': true,
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'transformed', type: PortType.signal),
    PortSpec(name: 'transform', type: PortType.matrixTransformation),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('componentCount', () => 8);
    params.putIfAbsent('whiten', () => true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(description, style: const TextStyle(color: Colors.black87)),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'componentCount',
          labelText: 'Components',
          keyboardType: TextInputType.number,
          parser: (String value, dynamic previous) =>
              int.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Whiten input'),
          value: (params['whiten'] as bool?) ?? true,
          onChanged: (bool value) {
            setState(() {
              params['whiten'] = value;
            });
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Placeholder only for now. This node reserves both a transformed-signal output and a transformation-object output.',
          style: TextStyle(color: Colors.black54),
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

    final int inputChannels = timeSeries.channelCount == 0
        ? 1
        : timeSeries.channelCount;
    final int requestedComponents =
        (params['componentCount'] as num?)?.round() ?? inputChannels;
    final int componentCount = requestedComponents.clamp(1, inputChannels);

    dataset.timeSeries = timeSeries.copyWith(
      source:
          '${timeSeries.source.isEmpty ? methodName : '${timeSeries.source} -> $methodName'} (placeholder)',
      channelLabels: List<String>.generate(
        componentCount,
        (int index) => '$methodName ${index + 1}',
        growable: false,
      ),
      channelSamples: timeSeries.channels
          .take(componentCount)
          .toList(growable: false),
    );

    dataset.matrixTransformation = MatrixTransformationData(
      matrix: List<List<double>>.generate(
        componentCount,
        (int row) => List<double>.generate(
          inputChannels,
          (int column) => row == column ? 1.0 : 0.0,
          growable: false,
        ),
        growable: false,
      ),
      componentLabels: List<String>.generate(
        componentCount,
        (int index) => '$methodName ${index + 1}',
        growable: false,
      ),
      source:
          '$methodName placeholder transform; whiten=${(params['whiten'] as bool?) ?? true}',
    );
  }
}

class PCANodeType extends _MatrixTransformNodeType {
  @override
  String get title => 'PCA';

  @override
  String get methodName => 'PC';

  @override
  String get description =>
      'Principal Component Analysis placeholder. This will eventually emit projected data plus the learned PCA transform.';
}

class ICANodeType extends _MatrixTransformNodeType {
  @override
  String get title => 'ICA';

  @override
  String get methodName => 'IC';

  @override
  String get description =>
      'FastICA separates a continuous multichannel recording into statistically independent component activations.';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'componentCount': 0,
    'tolerance': 1.0e-4,
    'maxIterations': 200,
    'seed': 42,
    'fitScope': 'whole',
    'portionAnchor': 'middle',
    'portionDurationSeconds': 30.0,
    'portionStartSeconds': 0.0,
    'markerLabels': <String>[],
    'markerPreSeconds': 0.25,
    'markerPostSeconds': 0.75,
    'channelMode': 'all',
    'selectedChannelLabels': <String>[],
  };

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('componentCount', () => 0);
    params.putIfAbsent('tolerance', () => 1.0e-4);
    params.putIfAbsent('maxIterations', () => 200);
    params.putIfAbsent('seed', () => 42);
    params.putIfAbsent('fitScope', () => 'whole');
    params.putIfAbsent('portionAnchor', () => 'middle');
    params.putIfAbsent('portionDurationSeconds', () => 30.0);
    params.putIfAbsent('portionStartSeconds', () => 0.0);
    params.putIfAbsent('markerLabels', () => <String>[]);
    params.putIfAbsent('markerPreSeconds', () => 0.25);
    params.putIfAbsent('markerPostSeconds', () => 0.75);
    params.putIfAbsent('channelMode', () => 'all');
    params.putIfAbsent('selectedChannelLabels', () => <String>[]);
    final Set<String> channelLabels = <String>{};
    final Set<String> markerLabels = <String>{};
    channelLabels.addAll(
      (params['_icaChannelLabels'] as List<dynamic>? ?? const <dynamic>[]).map(
        (dynamic value) => value.toString(),
      ),
    );
    markerLabels.addAll(
      (params['_icaMarkerLabels'] as List<dynamic>? ?? const <dynamic>[]).map(
        (dynamic value) => value.toString(),
      ),
    );
    final Set<String> selectedDatasetIds =
        (params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toSet();
    for (final Dataset dataset in datasets.values) {
      if (selectedDatasetIds.isNotEmpty &&
          !selectedDatasetIds.contains(dataset.id)) {
        continue;
      }
      final TimeSeriesData? timeSeries = dataset.timeSeries;
      if (timeSeries == null) {
        continue;
      }
      channelLabels.addAll(timeSeries.channelLabels);
      markerLabels.addAll(
        timeSeries.markers.map((TimeMarker marker) => marker.label),
      );
    }
    final List<String> orderedChannelLabels = channelLabels.toList()..sort();
    final List<String> orderedMarkerLabels = markerLabels.toList()..sort();
    final String fitScope = params['fitScope']?.toString() ?? 'whole';
    final String portionAnchor =
        params['portionAnchor']?.toString() ?? 'middle';
    final String channelMode = params['channelMode']?.toString() ?? 'all';
    final Set<String> selectedChannels =
        (params['selectedChannelLabels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toSet();
    final Set<String> selectedMarkers =
        (params['markerLabels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(description, style: const TextStyle(color: Colors.black87)),
        const SizedBox(height: 12),
        const Text('Fit data', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'whole', label: Text('Whole')),
            ButtonSegment<String>(value: 'portion', label: Text('Portion')),
            ButtonSegment<String>(value: 'markers', label: Text('Markers')),
          ],
          selected: <String>{fitScope},
          onSelectionChanged: (Set<String> selection) {
            setState(() {
              params['fitScope'] = selection.first;
            });
          },
        ),
        if (fitScope == 'portion') ...<Widget>[
          const SizedBox(height: 8),
          NodeParamDropdownField<String>(
            params: params,
            paramKey: 'portionAnchor',
            labelText: 'Position',
            options: const <NodeDropdownOption<String>>[
              NodeDropdownOption<String>(value: 'start', label: 'Start'),
              NodeDropdownOption<String>(value: 'middle', label: 'Middle'),
              NodeDropdownOption<String>(value: 'end', label: 'End'),
              NodeDropdownOption<String>(value: 'custom', label: 'Custom'),
            ],
            onChanged: (String value) => setState(() {}),
          ),
          const SizedBox(height: 8),
          NodeParamTextField(
            params: params,
            paramKey: 'portionDurationSeconds',
            labelText: 'Duration (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            parser: (String value, dynamic previous) =>
                double.tryParse(value) ?? previous,
          ),
          if (portionAnchor == 'custom') ...<Widget>[
            const SizedBox(height: 8),
            NodeParamTextField(
              params: params,
              paramKey: 'portionStartSeconds',
              labelText: 'Start time (seconds)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              parser: (String value, dynamic previous) =>
                  double.tryParse(value) ?? previous,
            ),
          ],
        ],
        if (fitScope == 'markers') ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: orderedMarkerLabels
                .map(
                  (String label) => FilterChip(
                    label: Text(label),
                    selected: selectedMarkers.contains(label),
                    onSelected: (bool selected) {
                      setState(() {
                        selected
                            ? selectedMarkers.add(label)
                            : selectedMarkers.remove(label);
                        params['markerLabels'] = selectedMarkers.toList()
                          ..sort();
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: NodeParamTextField(
                  params: params,
                  paramKey: 'markerPreSeconds',
                  labelText: 'Before (seconds)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  parser: (String value, dynamic previous) =>
                      double.tryParse(value) ?? previous,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NodeParamTextField(
                  params: params,
                  paramKey: 'markerPostSeconds',
                  labelText: 'After (seconds)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  parser: (String value, dynamic previous) =>
                      double.tryParse(value) ?? previous,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const Text('Channels', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'all', label: Text('All')),
            ButtonSegment<String>(value: 'selected', label: Text('Selected')),
          ],
          selected: <String>{channelMode},
          onSelectionChanged: (Set<String> selection) {
            setState(() {
              params['channelMode'] = selection.first;
            });
          },
        ),
        if (channelMode == 'selected') ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: orderedChannelLabels
                .map(
                  (String label) => FilterChip(
                    label: Text(label),
                    selected: selectedChannels.contains(label),
                    onSelected: (bool selected) {
                      setState(() {
                        selected
                            ? selectedChannels.add(label)
                            : selectedChannels.remove(label);
                        params['selectedChannelLabels'] =
                            selectedChannels.toList()..sort();
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'componentCount',
          labelText: 'Components',
          helperText: 'Use 0 to select the numerical rank automatically.',
          keyboardType: TextInputType.number,
          parser: (String value, dynamic previous) =>
              int.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 8),
        NodeParamTextField(
          params: params,
          paramKey: 'tolerance',
          labelText: 'Convergence tolerance',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          parser: (String value, dynamic previous) =>
              double.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 8),
        NodeParamTextField(
          params: params,
          paramKey: 'maxIterations',
          labelText: 'Maximum iterations',
          keyboardType: TextInputType.number,
          parser: (String value, dynamic previous) =>
              int.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 8),
        NodeParamTextField(
          params: params,
          paramKey: 'seed',
          labelText: 'Deterministic seed',
          keyboardType: TextInputType.number,
          parser: (String value, dynamic previous) =>
              int.tryParse(value) ?? previous,
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) return;
    final List<List<double>> sourceChannels = timeSeries.channels;
    final int sourceSampleCount = sourceChannels.first.length;
    if (sourceChannels.any(
      (List<double> channel) => channel.length != sourceSampleCount,
    )) {
      throw ArgumentError('All ICA input channels must have equal lengths.');
    }
    if (sourceSampleCount == 0) {
      throw ArgumentError('ICA requires signal samples.');
    }
    final List<String> sourceChannelLabels =
        timeSeries.channelLabels.length == sourceChannels.length
        ? List<String>.from(timeSeries.channelLabels)
        : List<String>.generate(
            sourceChannels.length,
            (int index) => 'Channel ${index + 1}',
            growable: false,
          );
    final List<int> selectedChannelIndices = _icaSelectedChannelIndices(
      params,
      sourceChannelLabels,
    );
    if (selectedChannelIndices.length < 2) {
      throw ArgumentError('ICA requires at least two channels.');
    }
    final List<List<double>> selectedSourceChannels = selectedChannelIndices
        .map((int channel) => sourceChannels[channel])
        .toList(growable: false);
    final String fitScope = params['fitScope']?.toString() ?? 'whole';
    final List<int> fitSampleIndices = fitScope == 'whole'
        ? const <int>[]
        : _icaFitSampleIndices(params, timeSeries);
    final int fitSampleCount = fitScope == 'whole'
        ? sourceSampleCount
        : fitSampleIndices.length;
    if (fitSampleCount < 32 ||
        fitSampleCount < selectedChannelIndices.length * 3) {
      throw ArgumentError(
        'ICA fitting requires at least 32 samples and at least three samples per selected channel.',
      );
    }
    final List<List<double>> fitChannels = fitScope == 'whole'
        ? selectedSourceChannels
        : selectedSourceChannels
              .map(
                (List<double> channel) => fitSampleIndices
                    .map((int sample) => channel[sample])
                    .toList(growable: false),
              )
              .toList(growable: false);
    final int componentCount = (params['componentCount'] as num?)?.toInt() ?? 0;
    final double tolerance =
        (params['tolerance'] as num?)?.toDouble() ?? 1.0e-4;
    final int maxIterations = (params['maxIterations'] as num?)?.toInt() ?? 200;
    final int seed = (params['seed'] as num?)?.toInt() ?? 42;
    if (componentCount < 0 || componentCount > selectedChannelIndices.length) {
      throw ArgumentError(
        'ICA components must be 0 (automatic) or no greater than the channel count.',
      );
    }
    if (!tolerance.isFinite || tolerance <= 0 || tolerance >= 1) {
      throw ArgumentError('ICA tolerance must be between 0 and 1.');
    }
    if (maxIterations <= 0 || maxIterations > 100000) {
      throw ArgumentError('ICA maximum iterations must be from 1 to 100000.');
    }
    if (seed < 0) {
      throw ArgumentError('ICA seed must be non-negative.');
    }

    final NativeIcaResult? result = computeIcaNative(
      fitChannels,
      componentCount: componentCount,
      tolerance: tolerance,
      maxIterations: maxIterations,
      seed: seed,
    );
    if (result == null) {
      throw UnsupportedError(
        'ICA requires the BrainStory Rust engine on this platform.',
      );
    }
    final List<String> componentLabels = List<String>.generate(
      result.activations.length,
      (int index) => 'IC ${index + 1}',
      growable: false,
    );
    final List<String> originalChannelLabels = selectedChannelIndices
        .map((int index) => sourceChannelLabels[index])
        .toList(growable: false);
    final List<List<double>> fullActivations = _applyIcaUnmixing(
      selectedSourceChannels,
      result.unmixingMatrix,
      result.channelMeans,
    );
    final List<String> fitMarkerLabels = fitScope == 'markers'
        ? (params['markerLabels'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .toList(growable: false)
        : const <String>[];
    final String fitDescription = _icaFitDescription(
      params,
      fitSampleCount,
      timeSeries.sampleRate,
    );
    final String inputSource = timeSeries.source.isEmpty
        ? 'ICA'
        : '${timeSeries.source} -> ICA';
    final Map<String, ChannelCoordinate> originalChannelCoordinates =
        <String, ChannelCoordinate>{};
    for (final String label in originalChannelLabels) {
      final ChannelCoordinate? coordinate =
          ChannelCoordinatesNodeType.coordinateForChannelLabel(
            timeSeries.channelCoordinates,
            label,
          );
      if (coordinate != null) {
        originalChannelCoordinates[label] = coordinate;
      }
    }
    dataset.timeSeries = TimeSeriesData(
      channelSamples: fullActivations,
      sampleRate: timeSeries.sampleRate,
      channelLabels: componentLabels,
      markers: timeSeries.markers,
      factors: timeSeries.factors,
      source: inputSource,
    );
    dataset.segmentedTimeSeries = null;
    dataset.matrixTransformation = MatrixTransformationData(
      matrix: result.unmixingMatrix,
      unmixingMatrix: result.unmixingMatrix,
      mixingMatrix: result.mixingMatrix,
      whiteningMatrix: result.whiteningMatrix,
      dewhiteningMatrix: result.dewhiteningMatrix,
      channelMeans: result.channelMeans,
      originalChannelLabels: originalChannelLabels,
      sourceChannelLabels: sourceChannelLabels,
      selectedChannelIndices: selectedChannelIndices,
      originalSampleRate: timeSeries.sampleRate,
      originalChannelCoordinates: originalChannelCoordinates,
      originalImpedanceData: _subsetImpedanceData(
        timeSeries.impedanceData,
        originalChannelLabels,
      ),
      componentLabels: componentLabels,
      componentEnergies: result.componentEnergies,
      algorithm: 'FastICA (symmetric, tanh)',
      converged: result.converged,
      iterationCount: result.iterationCount,
      numericalRank: result.numericalRank,
      tolerance: result.tolerance,
      maxIterations: result.maxIterations,
      seed: result.seed,
      fitScope: fitScope,
      fitSampleCount: fitSampleCount,
      fitMarkerLabels: fitMarkerLabels,
      source:
          '$inputSource; $fitDescription; ${result.converged ? 'converged' : 'did not converge'} after ${result.iterationCount} iteration(s)',
    );
  }
}

List<int> _icaSelectedChannelIndices(
  Map<String, dynamic> params,
  List<String> channelLabels,
) {
  if (params['channelMode']?.toString() != 'selected') {
    return List<int>.generate(channelLabels.length, (int index) => index);
  }
  final Set<String> selectedLabels =
      (params['selectedChannelLabels'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toSet();
  return List<int>.generate(channelLabels.length, (int index) => index)
      .where((int index) => selectedLabels.contains(channelLabels[index]))
      .toList(growable: false);
}

List<int> _icaFitSampleIndices(
  Map<String, dynamic> params,
  TimeSeriesData timeSeries,
) {
  final int sampleCount = timeSeries.sampleCount;
  final String scope = params['fitScope']?.toString() ?? 'whole';
  if (scope == 'whole') {
    return List<int>.generate(sampleCount, (int index) => index);
  }
  if (scope == 'portion') {
    final double durationSeconds =
        (params['portionDurationSeconds'] as num?)?.toDouble() ?? 30.0;
    if (!durationSeconds.isFinite || durationSeconds <= 0) {
      throw ArgumentError('ICA portion duration must be greater than zero.');
    }
    final int durationSamples = (durationSeconds * timeSeries.sampleRate)
        .round()
        .clamp(1, sampleCount);
    final String anchor = params['portionAnchor']?.toString() ?? 'middle';
    final int start;
    switch (anchor) {
      case 'start':
        start = 0;
        break;
      case 'end':
        start = sampleCount - durationSamples;
        break;
      case 'custom':
        final double startSeconds =
            (params['portionStartSeconds'] as num?)?.toDouble() ?? 0.0;
        if (!startSeconds.isFinite || startSeconds < 0) {
          throw ArgumentError('ICA portion start time cannot be negative.');
        }
        start = (startSeconds * timeSeries.sampleRate).round().clamp(
          0,
          sampleCount - durationSamples,
        );
        break;
      case 'middle':
      default:
        start = (sampleCount - durationSamples) ~/ 2;
        break;
    }
    return List<int>.generate(
      durationSamples,
      (int index) => start + index,
      growable: false,
    );
  }
  if (scope == 'markers') {
    final Set<String> markerLabels =
        (params['markerLabels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .toSet();
    if (markerLabels.isEmpty) {
      throw ArgumentError('Select at least one marker label for ICA fitting.');
    }
    final double preSeconds =
        (params['markerPreSeconds'] as num?)?.toDouble() ?? 0.25;
    final double postSeconds =
        (params['markerPostSeconds'] as num?)?.toDouble() ?? 0.75;
    if (!preSeconds.isFinite ||
        !postSeconds.isFinite ||
        preSeconds < 0 ||
        postSeconds < 0) {
      throw ArgumentError('ICA marker windows cannot be negative.');
    }
    final List<bool> included = List<bool>.filled(sampleCount, false);
    int matchedMarkers = 0;
    for (final TimeMarker marker in timeSeries.markers) {
      if (!markerLabels.contains(marker.label)) {
        continue;
      }
      matchedMarkers++;
      final int onset = marker.onsetSamples(timeSeries.sampleRate);
      final int duration = marker.durationSamples(timeSeries.sampleRate);
      final int start = (onset - preSeconds * timeSeries.sampleRate)
          .floor()
          .clamp(0, sampleCount);
      final int stop = (onset + duration + postSeconds * timeSeries.sampleRate)
          .ceil()
          .clamp(0, sampleCount);
      final int safeStop = stop <= start
          ? (start + 1).clamp(0, sampleCount)
          : stop;
      for (int sample = start; sample < safeStop; sample++) {
        included[sample] = true;
      }
    }
    if (matchedMarkers == 0) {
      throw ArgumentError('No markers matched the selected ICA labels.');
    }
    return List<int>.generate(
      sampleCount,
      (int index) => index,
    ).where((int index) => included[index]).toList(growable: false);
  }
  throw ArgumentError('Unknown ICA fit scope: $scope.');
}

List<List<double>> _applyIcaUnmixing(
  List<List<double>> channels,
  List<List<double>> unmixingMatrix,
  List<double> channelMeans,
) {
  final int sampleCount = channels.first.length;
  return List<List<double>>.generate(unmixingMatrix.length, (int component) {
    return List<double>.generate(sampleCount, (int sample) {
      double activation = 0.0;
      for (int channel = 0; channel < channels.length; channel++) {
        activation +=
            unmixingMatrix[component][channel] *
            (channels[channel][sample] - channelMeans[channel]);
      }
      return activation;
    }, growable: false);
  }, growable: false);
}

String _icaFitDescription(
  Map<String, dynamic> params,
  int sampleCount,
  double sampleRate,
) {
  final String scope = params['fitScope']?.toString() ?? 'whole';
  final String duration = (sampleCount / sampleRate).toStringAsFixed(2);
  if (scope == 'markers') {
    final String labels =
        (params['markerLabels'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString())
            .join(', ');
    return 'fit on $duration s around markers ($labels)';
  }
  if (scope == 'portion') {
    return 'fit on a $duration s ${params['portionAnchor'] ?? 'middle'} portion';
  }
  return 'fit on the whole recording ($duration s)';
}

ImpedanceData? _subsetImpedanceData(
  ImpedanceData? impedanceData,
  List<String> selectedLabels,
) {
  if (impedanceData == null) {
    return null;
  }
  final List<int> indices = selectedLabels
      .map(impedanceData.channelLabels.indexOf)
      .toList(growable: false);
  if (indices.any((int index) => index < 0)) {
    return null;
  }
  return ImpedanceData(
    channelLabels: selectedLabels,
    measurementTimesMicros: impedanceData.measurementTimesMicros,
    ohmsByChannel: indices
        .map((int index) => impedanceData.ohmsByChannel[index])
        .toList(growable: false),
  );
}

class EigenvalueDecompositionNodeType extends _MatrixTransformNodeType {
  @override
  String get title => 'Eigenvalue Decomposition';

  @override
  String get methodName => 'EV';

  @override
  String get description =>
      'Eigenvalue decomposition placeholder. This will eventually emit transformed data plus eigenvectors/eigenvalues and related scaling metadata.';
}

class MicrostatesNodeType extends NodeType {
  @override
  String get title => 'Microstates';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Matrix Transformation';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'stateCount': 4,
    'clusteringAlgorithm': 'Modified K-Means',
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'microstate signal', type: PortType.signal),
    PortSpec(name: 'microstate transform', type: PortType.matrixTransformation),
  ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('stateCount', () => 4);
    params.putIfAbsent('clusteringAlgorithm', () => 'Modified K-Means');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Microstate segmentation placeholder. This will eventually emit labeled microstate dynamics plus the fitted template/topography model.',
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'stateCount',
          labelText: '# States',
          keyboardType: TextInputType.number,
          parser: (String value, dynamic previous) =>
              int.tryParse(value) ?? previous,
        ),
        const SizedBox(height: 8),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'clusteringAlgorithm',
          labelText: 'Clustering Algorithm',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'Modified K-Means',
              label: 'Modified K-Means',
            ),
            NodeDropdownOption<String>(value: 'K-Means', label: 'K-Means'),
            NodeDropdownOption<String>(value: 'AAHC', label: 'AAHC'),
            NodeDropdownOption<String>(value: 'TAAHC', label: 'TAAHC'),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Placeholder only for now. The final implementation will expose both the microstate-assigned signal representation and the fitted state templates/metadata.',
          style: TextStyle(color: Colors.black54),
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

    final int stateCount = ((params['stateCount'] as num?)?.round() ?? 4).clamp(
      2,
      32,
    );
    final String algorithm =
        params['clusteringAlgorithm']?.toString() ?? 'Modified K-Means';

    dataset.timeSeries = timeSeries.copyWith(
      source:
          '${timeSeries.source.isEmpty ? 'Microstates' : '${timeSeries.source} -> Microstates'} (placeholder)',
    );

    dataset.matrixTransformation = MatrixTransformationData(
      matrix: List<List<double>>.generate(
        stateCount,
        (int row) => List<double>.generate(
          timeSeries.channelCount == 0 ? 1 : timeSeries.channelCount,
          (int column) => row == (column % stateCount) ? 1.0 : 0.0,
          growable: false,
        ),
        growable: false,
      ),
      componentLabels: List<String>.generate(
        stateCount,
        (int index) => 'State ${index + 1}',
        growable: false,
      ),
      source: 'Microstates placeholder transform; algorithm=$algorithm',
    );
  }
}

class SourceReconstructionNodeType extends _MatrixTransformNodeType {
  @override
  String get title => 'Source Reconstruction';

  @override
  String get methodName => 'SRC';

  @override
  String get description =>
      'Source reconstruction placeholder. This will eventually emit reconstructed source-space data plus the forward/inverse transformation objects.';
}
