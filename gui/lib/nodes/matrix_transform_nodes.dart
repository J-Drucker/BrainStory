import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/brainstory_engine.dart';
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
        const SizedBox(height: 8),
        const Text(
          'Input is centered and whitened automatically. ICA runs on the full continuous recording.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) return;
    final List<List<double>> channels = timeSeries.channels;
    if (channels.length < 2) {
      throw ArgumentError('ICA requires at least two channels.');
    }
    final int sampleCount = channels.first.length;
    if (sampleCount < 32 || sampleCount < channels.length * 3) {
      throw ArgumentError(
        'ICA requires at least 32 samples and at least three samples per channel.',
      );
    }
    if (channels.any((List<double> channel) => channel.length != sampleCount)) {
      throw ArgumentError('All ICA input channels must have equal lengths.');
    }
    final int componentCount = (params['componentCount'] as num?)?.toInt() ?? 0;
    final double tolerance =
        (params['tolerance'] as num?)?.toDouble() ?? 1.0e-4;
    final int maxIterations = (params['maxIterations'] as num?)?.toInt() ?? 200;
    final int seed = (params['seed'] as num?)?.toInt() ?? 42;
    if (componentCount < 0 || componentCount > channels.length) {
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
      channels,
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
    final List<String> originalChannelLabels =
        timeSeries.channelLabels.length == channels.length
        ? List<String>.from(timeSeries.channelLabels)
        : List<String>.generate(
            channels.length,
            (int index) => 'Channel ${index + 1}',
            growable: false,
          );
    final String inputSource = timeSeries.source.isEmpty
        ? 'ICA'
        : '${timeSeries.source} -> ICA';
    dataset.timeSeries = TimeSeriesData(
      channelSamples: result.activations,
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
      originalChannelCoordinates: timeSeries.channelCoordinates,
      originalImpedanceData: timeSeries.impedanceData,
      componentLabels: componentLabels,
      componentEnergies: result.componentEnergies,
      algorithm: 'FastICA (symmetric, tanh)',
      converged: result.converged,
      iterationCount: result.iterationCount,
      numericalRank: result.numericalRank,
      tolerance: result.tolerance,
      maxIterations: result.maxIterations,
      seed: result.seed,
      source:
          '$inputSource; ${result.converged ? 'converged' : 'did not converge'} after ${result.iterationCount} iteration(s)',
    );
  }
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
