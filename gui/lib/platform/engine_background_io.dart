import 'dart:isolate';
import 'dart:typed_data';

import 'brainstory_engine_io.dart' as native;

Future<dynamic> executeBrowserEngine(Map<String, dynamic> request) async {
  switch (request['operation']) {
    case 'gaussianMixture':
      return _gaussianMixture(request);
    case 'wavelet':
      return _wavelet(request);
    case 'ica':
      return _fitIca(request);
    case 'applyIca':
      return _applyIca(request);
    default:
      return null;
  }
}

Future<dynamic> _gaussianMixture(Map<String, dynamic> request) async {
  final List<List<double>> rows = _matrix(request['rows']);
  if (rows.isEmpty || rows.first.isEmpty) return null;
  final int featureCount = rows.first.length;
  final TransferableTypedData transferred = _transferMatrix(rows, featureCount);
  final int rowCount = rows.length;
  final int componentCount = (request['components'] as num).toInt();
  final double tolerance = (request['tolerance'] as num).toDouble();
  final int maxIterations = (request['iterations'] as num).toInt();
  final double regularization = (request['regularization'] as num).toDouble();
  final bool standardize = request['standardize'] == true;
  final int seed = (request['seed'] as num).toInt();
  return Isolate.run(() {
    final Float64List flat = _materializeDoubles(transferred);
    final List<List<double>> materialized = List<List<double>>.generate(
      rowCount,
      (int row) => flat
          .sublist(row * featureCount, (row + 1) * featureCount)
          .toList(growable: false),
      growable: false,
    );
    return native.computeGaussianMixtureNative(
      materialized,
      componentCount: componentCount,
      tolerance: tolerance,
      maxIterations: maxIterations,
      regularization: regularization,
      standardize: standardize,
      seed: seed,
    );
  });
}

Future<dynamic> _wavelet(Map<String, dynamic> request) async {
  final List<double> samples = _vector(request['samples']);
  if (samples.isEmpty) return null;
  final TransferableTypedData transferred = TransferableTypedData.fromList(
    <TypedData>[Float64List.fromList(samples)],
  );
  final double sampleRate = (request['rate'] as num).toDouble();
  final double lowHz = (request['low'] as num).toDouble();
  final double highHz = (request['high'] as num).toDouble();
  final int frequencyCount = (request['frequencies'] as num).toInt();
  final int timeCount = (request['times'] as num).toInt();
  final double cycles = (request['cycles'] as num).toDouble();
  return Isolate.run(() {
    return native.computeWaveletNative(
      _materializeDoubles(transferred),
      sampleRate: sampleRate,
      lowHz: lowHz,
      highHz: highHz,
      frequencyCount: frequencyCount,
      timeCount: timeCount,
      cycles: cycles,
    );
  });
}

Future<dynamic> _fitIca(Map<String, dynamic> request) async {
  final List<List<double>> channels = _matrix(request['channels']);
  if (channels.isEmpty || channels.first.isEmpty) {
    return null;
  }
  final int sampleCount = channels.first.length;
  final TransferableTypedData samples = _transferMatrix(channels, sampleCount);
  final int channelCount = channels.length;
  final int componentCount = (request['components'] as num?)?.toInt() ?? 0;
  final double tolerance = (request['tolerance'] as num?)?.toDouble() ?? 1.0e-4;
  final int maxIterations = (request['iterations'] as num?)?.toInt() ?? 200;
  final int seed = (request['seed'] as num?)?.toInt() ?? 42;
  return Isolate.run(() {
    final Float64List flatSamples = _materializeDoubles(samples);
    return native.computeIcaNativeFlat(
      flatSamples,
      channelCount: channelCount,
      sampleCount: sampleCount,
      componentCount: componentCount,
      tolerance: tolerance,
      maxIterations: maxIterations,
      seed: seed,
    );
  });
}

Future<dynamic> _applyIca(Map<String, dynamic> request) async {
  final List<List<double>> channels = _matrix(request['channels']);
  final List<List<double>> matrix = _matrix(request['matrix']);
  final List<double> means = _vector(request['means']);
  if (channels.isEmpty || channels.first.isEmpty || matrix.isEmpty) {
    return null;
  }
  final int sampleCount = channels.first.length;
  final int channelCount = channels.length;
  final int componentCount = matrix.length;
  final TransferableTypedData samples = _transferMatrix(channels, sampleCount);
  final TransferableTypedData unmixing = _transferMatrix(matrix, channelCount);
  final TransferableTypedData channelMeans = TransferableTypedData.fromList(
    <TypedData>[Float64List.fromList(means)],
  );
  return Isolate.run(() {
    return native.applyIcaNativeFlat(
      _materializeDoubles(samples),
      channelCount: channelCount,
      sampleCount: sampleCount,
      flatUnmixing: _materializeDoubles(unmixing),
      componentCount: componentCount,
      channelMeans: _materializeDoubles(channelMeans),
    );
  });
}

TransferableTypedData _transferMatrix(
  List<List<double>> matrix,
  int columnCount,
) {
  final Float64List flattened = Float64List(matrix.length * columnCount);
  int offset = 0;
  for (final List<double> row in matrix) {
    if (row.length != columnCount) {
      throw ArgumentError('Native engine matrix rows must have equal lengths.');
    }
    flattened.setRange(offset, offset + columnCount, row);
    offset += columnCount;
  }
  return TransferableTypedData.fromList(<TypedData>[flattened]);
}

Float64List _materializeDoubles(TransferableTypedData data) {
  final ByteBuffer bytes = data.materialize();
  return bytes.asFloat64List();
}

List<List<double>> _matrix(dynamic value) {
  if (value is List<List<double>>) {
    return value;
  }
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map(
        (dynamic row) => (row as List<dynamic>)
            .map((dynamic item) => (item as num).toDouble())
            .toList(),
      )
      .toList(growable: false);
}

List<double> _vector(dynamic value) {
  if (value is List<double>) {
    return value;
  }
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map((dynamic item) => (item as num).toDouble())
      .toList(growable: false);
}
