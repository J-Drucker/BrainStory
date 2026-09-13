import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

const int _backgroundEncodingThreshold = 16384;

Future<String> encodeNodeSnapshotJson(Map<String, dynamic> snapshot) async {
  final Map<String, dynamic>? sourceTimeSeries =
      snapshot['timeSeries'] is Map<String, dynamic>
      ? snapshot['timeSeries'] as Map<String, dynamic>
      : snapshot['timeSeries'] is Map
      ? Map<String, dynamic>.from(snapshot['timeSeries'] as Map)
      : null;
  if (sourceTimeSeries == null) {
    return jsonEncode(snapshot);
  }
  final List<List<double>> channels = _matrix(
    sourceTimeSeries['channelSamples'],
  );
  final List<double> samples = _vector(sourceTimeSeries['samples']);
  final int valueCount =
      channels.fold<int>(
        0,
        (int total, List<double> channel) => total + channel.length,
      ) +
      samples.length;
  if (valueCount < _backgroundEncodingThreshold) {
    return jsonEncode(snapshot);
  }

  final Float64List values = Float64List(valueCount);
  final List<int> channelLengths = <int>[];
  int offset = 0;
  for (final List<double> channel in channels) {
    values.setRange(offset, offset + channel.length, channel);
    offset += channel.length;
    channelLengths.add(channel.length);
  }
  values.setRange(offset, offset + samples.length, samples);
  final int sampleVectorLength = samples.length;
  final TransferableTypedData transferred = TransferableTypedData.fromList(
    <TypedData>[values],
  );
  final Map<String, dynamic> detachedSnapshot = Map<String, dynamic>.from(
    snapshot,
  );
  final Map<String, dynamic> detachedTimeSeries =
      Map<String, dynamic>.from(sourceTimeSeries)..addAll(<String, dynamic>{
        'samples': const <double>[],
        'channelSamples': const <List<double>>[],
      });
  detachedSnapshot['timeSeries'] = detachedTimeSeries;

  return Isolate.run(() {
    final Float64List materialized = transferred.materialize().asFloat64List();
    int inputOffset = 0;
    final List<Float64List> restoredChannels = channelLengths
        .map((int length) {
          final Float64List channel = Float64List.sublistView(
            materialized,
            inputOffset,
            inputOffset + length,
          );
          inputOffset += length;
          return channel;
        })
        .toList(growable: false);
    detachedTimeSeries['channelSamples'] = restoredChannels;
    detachedTimeSeries['samples'] = Float64List.sublistView(
      materialized,
      inputOffset,
      inputOffset + sampleVectorLength,
    );
    return jsonEncode(detachedSnapshot);
  });
}

List<List<double>> _matrix(dynamic value) {
  if (value is List<List<double>>) {
    return value;
  }
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map(
        (dynamic row) => (row as List<dynamic>)
            .map((dynamic item) => (item as num).toDouble())
            .toList(growable: false),
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
