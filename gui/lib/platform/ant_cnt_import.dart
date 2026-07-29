import 'dart:convert';
import 'dart:typed_data';

import '../model/data_artifacts.dart';
import 'ant_cnt_import_stub.dart'
    if (dart.library.io) 'ant_cnt_import_io.dart'
    as impl;

class AntCntImportData {
  const AntCntImportData({
    required this.channelSamples,
    required this.sampleRate,
    required this.channelLabels,
    required this.sourceDescription,
    this.markers = const <TimeMarker>[],
    this.impedanceData,
  });

  final List<List<double>> channelSamples;
  final double sampleRate;
  final List<String> channelLabels;
  final String sourceDescription;
  final List<TimeMarker> markers;
  final ImpedanceData? impedanceData;
}

Future<AntCntImportData> readAntCntFromPath(String path) {
  return impl.readAntCntFromPath(path);
}

AntCntImportData parseAntCntPayload(
  Map<String, dynamic> payload,
  Uint8List sampleBytes,
) {
  final int channelCount = (payload['channelCount'] as num?)?.toInt() ?? 0;
  final int sampleCount = (payload['sampleCount'] as num?)?.toInt() ?? 0;
  if (channelCount <= 0 || sampleCount <= 0) {
    throw const FormatException(
      'ANT CNT payload did not include a valid data shape.',
    );
  }

  final int expectedByteCount = channelCount * sampleCount * 4;
  if (sampleBytes.lengthInBytes < expectedByteCount) {
    throw FormatException(
      'ANT CNT sample payload is too short: expected $expectedByteCount bytes, '
      'found ${sampleBytes.lengthInBytes}.',
    );
  }

  final ByteData data = ByteData.sublistView(sampleBytes);
  int offset = 0;
  final List<List<double>> channelSamples = List<List<double>>.generate(
    channelCount,
    (_) => List<double>.filled(sampleCount, 0.0),
  );
  for (int channelIndex = 0; channelIndex < channelCount; channelIndex++) {
    for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      channelSamples[channelIndex][sampleIndex] = data.getFloat32(
        offset,
        Endian.little,
      );
      offset += 4;
    }
  }

  final List<String> channelLabels =
      (payload['channelLabels'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic label) => label.toString())
          .toList(growable: false);
  final List<String> resolvedLabels = channelLabels.length == channelCount
      ? channelLabels
      : List<String>.generate(channelCount, (int index) => 'Ch ${index + 1}');

  final List<TimeMarker> decodedMarkers =
      (payload['markers'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TimeMarker.fromJson)
          .toList(growable: false);
  final ImpedanceData? impedanceData =
      ImpedanceData.fromJsonOrNull(payload['impedance']) ??
      _impedanceFromLegacyMarkers(decodedMarkers, resolvedLabels);

  return AntCntImportData(
    channelSamples: channelSamples,
    sampleRate: (payload['sampleRate'] as num?)?.toDouble() ?? 1.0,
    channelLabels: resolvedLabels,
    sourceDescription: payload['sourceDescription']?.toString() ?? 'ANT CNT',
    markers: decodedMarkers
        .where(
          (TimeMarker marker) =>
              marker.attributes['ant.impedancesOhms'] is! Map,
        )
        .toList(growable: false),
    impedanceData: impedanceData,
  );
}

ImpedanceData? _impedanceFromLegacyMarkers(
  List<TimeMarker> markers,
  List<String> channelLabels,
) {
  final List<TimeMarker> impedanceMarkers = markers
      .where(
        (TimeMarker marker) => marker.attributes['ant.impedancesOhms'] is Map,
      )
      .toList(growable: false);
  if (impedanceMarkers.isEmpty) {
    return null;
  }
  return ImpedanceData(
    channelLabels: channelLabels,
    measurementTimesMicros: impedanceMarkers
        .map((TimeMarker marker) => marker.onsetMicros)
        .toList(growable: false),
    ohmsByChannel: List<List<double?>>.generate(
      channelLabels.length,
      (int channelIndex) => impedanceMarkers
          .map((TimeMarker marker) {
            final Map readings = marker.attributes['ant.impedancesOhms'] as Map;
            final Object? value = readings[channelLabels[channelIndex]];
            return value is num ? value.toDouble() : null;
          })
          .toList(growable: false),
      growable: false,
    ),
  );
}

Map<String, dynamic> decodeAntCntPayload(String stdout) {
  final List<String> lines = const LineSplitter()
      .convert(stdout)
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    throw const FormatException('ANT CNT importer did not return metadata.');
  }
  final dynamic decoded = jsonDecode(lines.last);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'ANT CNT importer returned malformed metadata.',
    );
  }
  return decoded;
}
