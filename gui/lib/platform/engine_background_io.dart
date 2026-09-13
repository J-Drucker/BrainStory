import 'dart:isolate';
import 'dart:typed_data';

import 'brainstory_engine_io.dart' as native;

Future<dynamic> executeBrowserEngine(Map<String, dynamic> request) async {
  switch (request['operation']) {
    case 'ica':
      return _fitIca(request);
    case 'applyIca':
      return _applyIca(request);
    default:
      return null;
  }
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
