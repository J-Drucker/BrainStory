import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
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
        Text(
          description,
          style: const TextStyle(color: Colors.black87),
        ),
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

    final int inputChannels = timeSeries.channelCount == 0 ? 1 : timeSeries.channelCount;
    final int requestedComponents =
        (params['componentCount'] as num?)?.round() ?? inputChannels;
    final int componentCount = requestedComponents.clamp(1, inputChannels);

    dataset.timeSeries = timeSeries.copyWith(
      source: '${timeSeries.source.isEmpty ? methodName : '${timeSeries.source} -> $methodName'} (placeholder)',
      channelLabels: List<String>.generate(
        componentCount,
        (int index) => '$methodName ${index + 1}',
        growable: false,
      ),
      channelSamples: timeSeries.channels.take(componentCount).toList(growable: false),
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
      source: '$methodName placeholder transform; whiten=${(params['whiten'] as bool?) ?? true}',
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

class ICANodeType extends NodeType {
  @override
  String get title => 'ICA';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Matrix Transformation';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{};

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'ica matrices', type: PortType.matrixTransformation),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Fits deterministic FastICA using all channels. BrainStory automatically centers and whitens the signal, then stores only the learned matrices.',
          style: TextStyle(color: Colors.black87),
        ),
        SizedBox(height: 8),
        Text(
          'Outputs: unmixing matrix, mixing matrix, whitening/dewhitening matrices, and channel means. No component signal copy is created.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.length < 2) {
      return;
    }
    final _IcaFit fit = _fitDeterministicFastIca(timeSeries.channels);
    dataset.matrixTransformation = MatrixTransformationData(
      matrix: fit.unmixing,
      namedMatrices: <String, List<List<double>>>{
        'unmixing': fit.unmixing,
        'mixing': fit.mixing,
        'whitening': fit.whitening,
        'dewhitening': fit.dewhitening,
        'channelMeans': <List<double>>[fit.channelMeans],
      },
      metadata: <String, dynamic>{
        'algorithm': 'FastICA',
        'whitening': 'automatic eigenvalue whitening',
        'componentCount': fit.unmixing.length,
        'inputChannelCount': timeSeries.channelCount,
        'iterations': fit.iterations,
        'converged': fit.converged,
        'tolerance': _icaTolerance,
      },
      componentLabels: List<String>.generate(
        fit.unmixing.length,
        (int index) => 'IC ${index + 1}',
        growable: false,
      ),
      source: timeSeries.source.isEmpty
          ? 'ICA matrices'
          : '${timeSeries.source} -> ICA matrices',
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

    final int stateCount = ((params['stateCount'] as num?)?.round() ?? 4).clamp(2, 32);
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

const int _icaMaxIterations = 600;
const double _icaTolerance = 1e-6;
const double _icaEpsilon = 1e-12;

class _IcaFit {
  const _IcaFit({
    required this.unmixing,
    required this.mixing,
    required this.whitening,
    required this.dewhitening,
    required this.channelMeans,
    required this.iterations,
    required this.converged,
  });

  final List<List<double>> unmixing;
  final List<List<double>> mixing;
  final List<List<double>> whitening;
  final List<List<double>> dewhitening;
  final List<double> channelMeans;
  final int iterations;
  final bool converged;
}

_IcaFit _fitDeterministicFastIca(List<List<double>> channels) {
  final int channelCount = channels.length;
  final int sampleCount = channels.map((List<double> row) => row.length).reduce(math.min);
  if (channelCount < 2 || sampleCount < channelCount + 1) {
    throw ArgumentError('ICA needs at least two channels and enough samples.');
  }

  final List<double> means = List<double>.generate(channelCount, (int row) {
    double sum = 0.0;
    for (int sample = 0; sample < sampleCount; sample++) {
      sum += channels[row][sample];
    }
    return sum / sampleCount;
  }, growable: false);

  final List<List<double>> centered = List<List<double>>.generate(
    channelCount,
    (int row) => List<double>.generate(
      sampleCount,
      (int sample) => channels[row][sample] - means[row],
      growable: false,
    ),
    growable: false,
  );

  final List<List<double>> covariance = _covariance(centered);
  final _SymmetricEigen covarianceEigen = _jacobiEigen(covariance);
  final List<int> order = List<int>.generate(channelCount, (int index) => index)
    ..sort(
      (int a, int b) => covarianceEigen.values[b].compareTo(covarianceEigen.values[a]),
    );
  final List<double> eigenvalues = order
      .map((int index) => math.max(covarianceEigen.values[index], _icaEpsilon))
      .toList(growable: false);
  final List<List<double>> eigenvectors = List<List<double>>.generate(
    channelCount,
    (int row) => List<double>.generate(
      channelCount,
      (int column) => covarianceEigen.vectors[row][order[column]],
      growable: false,
    ),
    growable: false,
  );

  final List<List<double>> whitening = List<List<double>>.generate(
    channelCount,
    (int component) => List<double>.generate(
      channelCount,
      (int channel) => eigenvectors[channel][component] / math.sqrt(eigenvalues[component]),
      growable: false,
    ),
    growable: false,
  );
  final List<List<double>> dewhitening = List<List<double>>.generate(
    channelCount,
    (int channel) => List<double>.generate(
      channelCount,
      (int component) => eigenvectors[channel][component] * math.sqrt(eigenvalues[component]),
      growable: false,
    ),
    growable: false,
  );
  final List<List<double>> whitened = _multiply(whitening, centered);

  List<List<double>> weights = _symmetricDecorrelate(
    _deterministicInitialWeights(channelCount),
  );
  int iterations = 0;
  bool converged = false;
  for (int iteration = 0; iteration < _icaMaxIterations; iteration++) {
    iterations = iteration + 1;
    final List<List<double>> weighted = _multiply(weights, whitened);
    final List<List<double>> updated = List<List<double>>.generate(
      channelCount,
      (int component) => List<double>.filled(channelCount, 0.0, growable: false),
      growable: false,
    );

    for (int component = 0; component < channelCount; component++) {
      double derivativeMean = 0.0;
      for (int sample = 0; sample < sampleCount; sample++) {
        final double activation = weighted[component][sample];
        final double g = _tanh(activation);
        final double derivative = 1.0 - g * g;
        derivativeMean += derivative;
        for (int channel = 0; channel < channelCount; channel++) {
          updated[component][channel] += whitened[channel][sample] * g;
        }
      }
      derivativeMean /= sampleCount;
      for (int channel = 0; channel < channelCount; channel++) {
        updated[component][channel] =
            (updated[component][channel] / sampleCount) -
                derivativeMean * weights[component][channel];
      }
    }

    final List<List<double>> nextWeights = _symmetricDecorrelate(updated);
    double maxDelta = 0.0;
    for (int component = 0; component < channelCount; component++) {
      final double alignment = _dot(nextWeights[component], weights[component]).abs();
      maxDelta = math.max(maxDelta, (1.0 - alignment).abs());
    }
    weights = nextWeights;
    if (maxDelta < _icaTolerance) {
      converged = true;
      break;
    }
  }

  final List<List<double>> unmixing = _multiply(weights, whitening);
  final List<List<double>> mixing = _multiply(dewhitening, _transpose(weights));
  return _IcaFit(
    unmixing: unmixing,
    mixing: mixing,
    whitening: whitening,
    dewhitening: dewhitening,
    channelMeans: means,
    iterations: iterations,
    converged: converged,
  );
}

List<List<double>> _covariance(List<List<double>> centered) {
  final int rows = centered.length;
  final int samples = centered.first.length;
  return List<List<double>>.generate(
    rows,
    (int i) => List<double>.generate(rows, (int j) {
      double sum = 0.0;
      for (int sample = 0; sample < samples; sample++) {
        sum += centered[i][sample] * centered[j][sample];
      }
      return sum / samples;
    }, growable: false),
    growable: false,
  );
}

List<List<double>> _deterministicInitialWeights(int size) {
  final List<List<double>> rows = List<List<double>>.generate(
    size,
    (int row) => List<double>.generate(
      size,
      (int column) {
        final double angle = math.pi * (row + 0.5) * column / size;
        return math.cos(angle) + (row == column ? 0.17 : 0.0);
      },
      growable: false,
    ),
    growable: false,
  );
  return _gramSchmidtRows(rows);
}

List<List<double>> _gramSchmidtRows(List<List<double>> rows) {
  final List<List<double>> orthogonal = <List<double>>[];
  for (final List<double> sourceRow in rows) {
    final List<double> row = List<double>.from(sourceRow);
    for (final List<double> previous in orthogonal) {
      final double projection = _dot(row, previous);
      for (int index = 0; index < row.length; index++) {
        row[index] -= projection * previous[index];
      }
    }
    final double norm = math.sqrt(_dot(row, row));
    if (norm <= _icaEpsilon) {
      continue;
    }
    orthogonal.add(
      row.map((double value) => value / norm).toList(growable: false),
    );
  }
  return orthogonal;
}

List<List<double>> _symmetricDecorrelate(List<List<double>> matrix) {
  final List<List<double>> product = _multiply(matrix, _transpose(matrix));
  final _SymmetricEigen eigen = _jacobiEigen(product);
  final int size = matrix.length;
  final List<List<double>> inverseRoot = List<List<double>>.generate(
    size,
    (int row) => List<double>.generate(size, (int column) {
      double sum = 0.0;
      for (int component = 0; component < size; component++) {
        final double value = math.max(eigen.values[component], _icaEpsilon);
        sum += eigen.vectors[row][component] *
            (1.0 / math.sqrt(value)) *
            eigen.vectors[column][component];
      }
      return sum;
    }, growable: false),
    growable: false,
  );
  return _multiply(inverseRoot, matrix);
}

class _SymmetricEigen {
  const _SymmetricEigen({
    required this.values,
    required this.vectors,
  });

  final List<double> values;
  final List<List<double>> vectors;
}

_SymmetricEigen _jacobiEigen(List<List<double>> input) {
  final int size = input.length;
  final List<List<double>> a = input
      .map((List<double> row) => List<double>.from(row, growable: false))
      .toList(growable: false);
  final List<List<double>> v = _identity(size);
  final int maxSweeps = math.max(20, size * size * 12);
  for (int sweep = 0; sweep < maxSweeps; sweep++) {
    int p = 0;
    int q = 1;
    double maxOffDiagonal = 0.0;
    for (int row = 0; row < size - 1; row++) {
      for (int column = row + 1; column < size; column++) {
        final double value = a[row][column].abs();
        if (value > maxOffDiagonal) {
          maxOffDiagonal = value;
          p = row;
          q = column;
        }
      }
    }
    if (maxOffDiagonal < 1e-10) {
      break;
    }

    final double app = a[p][p];
    final double aqq = a[q][q];
    final double apq = a[p][q];
    final double tau = (aqq - app) / (2.0 * apq);
    final double t = tau >= 0
        ? 1.0 / (tau + math.sqrt(1.0 + tau * tau))
        : -1.0 / (-tau + math.sqrt(1.0 + tau * tau));
    final double c = 1.0 / math.sqrt(1.0 + t * t);
    final double s = t * c;

    for (int index = 0; index < size; index++) {
      if (index != p && index != q) {
        final double aip = a[index][p];
        final double aiq = a[index][q];
        a[index][p] = c * aip - s * aiq;
        a[p][index] = a[index][p];
        a[index][q] = c * aiq + s * aip;
        a[q][index] = a[index][q];
      }
    }
    a[p][p] = c * c * app - 2.0 * s * c * apq + s * s * aqq;
    a[q][q] = s * s * app + 2.0 * s * c * apq + c * c * aqq;
    a[p][q] = 0.0;
    a[q][p] = 0.0;

    for (int index = 0; index < size; index++) {
      final double vip = v[index][p];
      final double viq = v[index][q];
      v[index][p] = c * vip - s * viq;
      v[index][q] = s * vip + c * viq;
    }
  }
  return _SymmetricEigen(
    values: List<double>.generate(size, (int index) => a[index][index], growable: false),
    vectors: v,
  );
}

List<List<double>> _multiply(List<List<double>> a, List<List<double>> b) {
  final int rows = a.length;
  final int inner = a.first.length;
  final int columns = b.first.length;
  return List<List<double>>.generate(
    rows,
    (int row) => List<double>.generate(columns, (int column) {
      double sum = 0.0;
      for (int index = 0; index < inner; index++) {
        sum += a[row][index] * b[index][column];
      }
      return sum;
    }, growable: false),
    growable: false,
  );
}

List<List<double>> _transpose(List<List<double>> matrix) {
  final int rows = matrix.length;
  final int columns = matrix.first.length;
  return List<List<double>>.generate(
    columns,
    (int column) => List<double>.generate(
      rows,
      (int row) => matrix[row][column],
      growable: false,
    ),
    growable: false,
  );
}

List<List<double>> _identity(int size) {
  return List<List<double>>.generate(
    size,
    (int row) => List<double>.generate(
      size,
      (int column) => row == column ? 1.0 : 0.0,
      growable: false,
    ),
    growable: false,
  );
}

double _dot(List<double> a, List<double> b) {
  double sum = 0.0;
  for (int index = 0; index < a.length; index++) {
    sum += a[index] * b[index];
  }
  return sum;
}

double _tanh(double value) {
  if (value > 20.0) {
    return 1.0;
  }
  if (value < -20.0) {
    return -1.0;
  }
  final double exponent = math.exp(2.0 * value);
  return (exponent - 1.0) / (exponent + 1.0);
}
