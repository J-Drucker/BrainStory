import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class ParsedSignalData {
  const ParsedSignalData({
    required this.channelSamples,
    required this.sampleRate,
    required this.channelLabels,
    required this.sourceDescription,
  });

  final List<List<double>> channelSamples;
  final double sampleRate;
  final List<String> channelLabels;
  final String sourceDescription;

  List<double> get samples =>
      channelSamples.isEmpty ? const <double>[] : channelSamples.first;
}

class ImportNodeType extends NodeType {
  @override
  String get title => 'Import';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  Map<String, dynamic> get defaultParams => {
    'selectedDatasetIds': <String>[],
    'sampleRateHz': 256.0,
  };

  @override
  List<PortSpec> get inputs => const [];

  @override
  List<PortSpec> get outputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    final List<MapEntry<String, Dataset>> entries = datasets.entries.toList()
      ..sort((a, b) => a.value.label.compareTo(b.value.label));

    return SizedBox(
      height: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            entries.isEmpty
                ? 'Open datasets from the right panel, then choose which ones this import node should expose below.'
                : 'Choose which datasets this import node should expose using the table below.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: params['sampleRateHz']?.toString() ?? '256.0',
            decoration: const InputDecoration(
              labelText: 'Fallback sample rate (Hz)',
              helperText: 'Used when the file does not contain a clear time column.',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (String value) {
              setState(() {
                params['sampleRateHz'] =
                    double.tryParse(value) ?? params['sampleRateHz'];
              });
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'CSV, TSV, whitespace-delimited text, and EDF are supported. Multi-channel text tables and EDF channel sets are preserved.',
          ),
        ],
      ),
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final double fallbackSampleRate =
        (params['sampleRateHz'] as num?)?.toDouble() ?? 256.0;

    final ParsedSignalData parsed = await loadDatasetSignal(
      dataset.path,
      fallbackSampleRate: fallbackSampleRate,
    );

    dataset.loaded = true;
    dataset.timeSeries = TimeSeriesData(
      channelSamples: parsed.channelSamples,
      sampleRate: parsed.sampleRate,
      channelLabels: parsed.channelLabels,
      source: parsed.sourceDescription,
    );
  }
}

Future<ParsedSignalData> loadDatasetSignal(
  String path, {
  required double fallbackSampleRate,
}) async {
  if (path.isEmpty) {
    return _syntheticSignal(fallbackSampleRate);
  }

  final File file = File(path);
  if (!await file.exists()) {
    throw FileSystemException('Dataset file was not found.', path);
  }

  final String lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.edf')) {
    final Uint8List bytes = await file.readAsBytes();
    return parseEdfBytes(bytes, sourceDescription: path);
  }

  final String contents = await file.readAsString();
  return parseSignalText(
    contents,
    fallbackSampleRate: fallbackSampleRate,
    sourceDescription: path,
  );
}

ParsedSignalData parseSignalText(
  String contents, {
  required double fallbackSampleRate,
  required String sourceDescription,
}) {
  final List<List<double>> rows = <List<double>>[];
  List<String>? headerTokens;
  for (final String rawLine in contents.split(RegExp(r'\r?\n'))) {
    final String line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }

    final List<String> tokens = _splitRow(line);
    final List<double> numericValues = tokens
        .map((String token) => double.tryParse(token.trim()))
        .whereType<double>()
        .toList();
    if (numericValues.length == tokens.length && numericValues.isNotEmpty) {
      rows.add(numericValues);
    } else if (headerTokens == null && tokens.length > 1) {
      headerTokens = tokens.map((String token) => token.trim()).toList();
    }
  }

  if (rows.isEmpty) {
    throw const FormatException('No numeric rows were found in the dataset.');
  }

  final int columnCount = rows
      .map((List<double> row) => row.length)
      .reduce((int left, int right) => left < right ? left : right);

  if (_looksLikeTimeSeries(rows)) {
    final List<double> timeColumn = rows.map((List<double> row) => row[0]).toList();
    final int channelCount = math.max(1, columnCount - 1);
    final List<List<double>> channelSamples = List<List<double>>.generate(
      channelCount,
      (int channelIndex) => rows
          .map((List<double> row) => row[channelIndex + 1])
          .toList(growable: false),
    );
    return ParsedSignalData(
      channelSamples: channelSamples,
      sampleRate: _inferSampleRate(timeColumn, fallbackSampleRate),
      channelLabels: _resolveChannelLabels(
        headerTokens: headerTokens,
        count: channelCount,
        skipLeadingTimeColumn: true,
      ),
      sourceDescription: sourceDescription,
    );
  }

  final List<List<double>> channelSamples = List<List<double>>.generate(
    columnCount,
    (int channelIndex) => rows
        .map((List<double> row) => row[channelIndex])
        .toList(growable: false),
  );
  return ParsedSignalData(
    channelSamples: channelSamples,
    sampleRate: fallbackSampleRate,
    channelLabels: _resolveChannelLabels(
      headerTokens: headerTokens,
      count: columnCount,
      skipLeadingTimeColumn: false,
    ),
    sourceDescription: sourceDescription,
  );
}

ParsedSignalData parseEdfBytes(
  Uint8List bytes, {
  required String sourceDescription,
}) {
  if (bytes.length < 256) {
    throw const FormatException('EDF file is too small to contain a valid header.');
  }

  final ByteData data = ByteData.sublistView(bytes);
  final _EdfHeader header = _parseEdfHeader(bytes);
  final List<_EdfSignalHeader> signals = _parseEdfSignalHeaders(bytes, header);
  final List<_EdfSignalHeader> dataSignals = signals
      .where(
        (_EdfSignalHeader signal) =>
            !signal.label.toLowerCase().contains('annotation'),
      )
      .toList(growable: false);
  if (dataSignals.isEmpty) {
    throw const FormatException('No non-annotation EDF channels were found.');
  }

  final double targetSampleRate =
      dataSignals.first.sampleRate(header.recordDurationSeconds);
  final List<_EdfSignalHeader> selectedSignals = dataSignals
      .where(
        (_EdfSignalHeader signal) =>
            (signal.sampleRate(header.recordDurationSeconds) - targetSampleRate).abs() <
            0.001,
      )
      .toList(growable: false);
  final Set<int> selectedSignalIndexes = selectedSignals
      .map((_EdfSignalHeader signal) => signals.indexOf(signal))
      .toSet();
  final int recordByteSize =
      signals.fold<int>(0, (int sum, _EdfSignalHeader signal) => sum + signal.samplesPerRecord * 2);
  final int totalSamples =
      header.numDataRecords * selectedSignals.first.samplesPerRecord;
  final List<List<double>> channelSamples = List<List<double>>.generate(
    selectedSignals.length,
    (_) => List<double>.filled(totalSamples, 0.0),
  );

  final List<int> outputIndexes = List<int>.filled(selectedSignals.length, 0);
  for (int record = 0; record < header.numDataRecords; record++) {
    int signalByteOffset = header.headerBytes + (record * recordByteSize);

    for (int signalIndex = 0; signalIndex < signals.length; signalIndex++) {
      final _EdfSignalHeader signal = signals[signalIndex];
      final int signalStart = signalByteOffset;

      if (selectedSignalIndexes.contains(signalIndex)) {
        final int channelIndex = selectedSignals.indexOf(signal);
        for (int sampleIndex = 0; sampleIndex < signal.samplesPerRecord; sampleIndex++) {
          final int rawValue = data.getInt16(signalStart + (sampleIndex * 2), Endian.little);
          channelSamples[channelIndex][outputIndexes[channelIndex]++] =
              signal.toPhysicalValue(rawValue);
        }
      }

      signalByteOffset += signal.samplesPerRecord * 2;
    }
  }

  return ParsedSignalData(
    channelSamples: channelSamples,
    sampleRate: targetSampleRate,
    channelLabels: selectedSignals
        .map((_EdfSignalHeader signal) => signal.label)
        .toList(growable: false),
    sourceDescription: selectedSignals.length == 1
        ? '$sourceDescription [${selectedSignals.first.label}]'
        : '$sourceDescription [${selectedSignals.first.label} + ${selectedSignals.length - 1} more]',
  );
}

List<String> _splitRow(String line) {
  final String delimiter = _preferredDelimiter(line);
  return (delimiter.isEmpty
      ? line.split(RegExp(r'\s+'))
      : line.split(delimiter))
      .map((String token) => token.trim())
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}

String _preferredDelimiter(String line) {
  if (line.contains(',')) return ',';
  if (line.contains('\t')) return '\t';
  if (line.contains(';')) return ';';
  return '';
}

bool _looksLikeTimeSeries(List<List<double>> rows) {
  if (rows.any((List<double> row) => row.length < 2)) {
    return false;
  }

  double? previous;
  for (final List<double> row in rows) {
    final double current = row[0];
    if (previous != null && current <= previous) {
      return false;
    }
    previous = current;
  }

  return true;
}

double _inferSampleRate(List<double> timeColumn, double fallbackSampleRate) {
  if (timeColumn.length < 2) {
    return fallbackSampleRate;
  }

  double deltaSum = 0.0;
  int deltaCount = 0;
  for (int i = 1; i < timeColumn.length; i++) {
    final double delta = timeColumn[i] - timeColumn[i - 1];
    if (delta > 0) {
      deltaSum += delta;
      deltaCount++;
    }
  }

  if (deltaCount == 0) {
    return fallbackSampleRate;
  }

  final double meanDeltaMs = deltaSum / deltaCount;
  return meanDeltaMs <= 0 ? fallbackSampleRate : 1000.0 / meanDeltaMs;
}

ParsedSignalData _syntheticSignal(double sampleRate) {
  final int sampleCount = math.max(1, (sampleRate * 5).round());
  final List<double> samples = List<double>.generate(sampleCount, (int i) {
    final double t = i / sampleRate;
    return 0.8 * math.sin(2 * math.pi * 10 * t) +
        0.4 * math.sin(2 * math.pi * 20 * t);
  });

  return ParsedSignalData(
    channelSamples: <List<double>>[samples],
    sampleRate: sampleRate,
    channelLabels: const <String>['Synth 1'],
    sourceDescription: 'synthetic',
  );
}

List<String> _resolveChannelLabels({
  required List<String>? headerTokens,
  required int count,
  required bool skipLeadingTimeColumn,
}) {
  if (headerTokens != null) {
    final int startIndex = skipLeadingTimeColumn ? 1 : 0;
    if (headerTokens.length >= startIndex + count) {
      return headerTokens
          .sublist(startIndex, startIndex + count)
          .map((String token) => token.isEmpty ? 'Ch ${startIndex + 1}' : token)
          .toList(growable: false);
    }
  }

  return List<String>.generate(
    count,
    (int index) => 'Ch ${index + 1}',
    growable: false,
  );
}

_EdfHeader _parseEdfHeader(Uint8List bytes) {
  String readAscii(int start, int length) {
    return ascii.decode(bytes.sublist(start, start + length), allowInvalid: true).trim();
  }

  return _EdfHeader(
    headerBytes: int.parse(readAscii(184, 8)),
    numDataRecords: int.parse(readAscii(236, 8)),
    recordDurationSeconds: double.parse(readAscii(244, 8)),
    numSignals: int.parse(readAscii(252, 4)),
  );
}

List<_EdfSignalHeader> _parseEdfSignalHeaders(Uint8List bytes, _EdfHeader header) {
  String readAscii(int start, int length) {
    return ascii.decode(bytes.sublist(start, start + length), allowInvalid: true).trim();
  }

  int offset = 256;
  final List<String> labels = List<String>.generate(
    header.numSignals,
    (int i) => readAscii(offset + (i * 16), 16),
  );
  offset += header.numSignals * 16;

  offset += header.numSignals * 80; // transducer
  offset += header.numSignals * 8; // physical dimension

  final List<double> physicalMins = List<double>.generate(
    header.numSignals,
    (int i) => double.parse(readAscii(offset + (i * 8), 8)),
  );
  offset += header.numSignals * 8;

  final List<double> physicalMaxs = List<double>.generate(
    header.numSignals,
    (int i) => double.parse(readAscii(offset + (i * 8), 8)),
  );
  offset += header.numSignals * 8;

  final List<int> digitalMins = List<int>.generate(
    header.numSignals,
    (int i) => int.parse(readAscii(offset + (i * 8), 8)),
  );
  offset += header.numSignals * 8;

  final List<int> digitalMaxs = List<int>.generate(
    header.numSignals,
    (int i) => int.parse(readAscii(offset + (i * 8), 8)),
  );
  offset += header.numSignals * 8;

  offset += header.numSignals * 80; // prefiltering

  final List<int> samplesPerRecord = List<int>.generate(
    header.numSignals,
    (int i) => int.parse(readAscii(offset + (i * 8), 8)),
  );

  return List<_EdfSignalHeader>.generate(header.numSignals, (int i) {
    return _EdfSignalHeader(
      label: labels[i],
      physicalMin: physicalMins[i],
      physicalMax: physicalMaxs[i],
      digitalMin: digitalMins[i],
      digitalMax: digitalMaxs[i],
      samplesPerRecord: samplesPerRecord[i],
    );
  });
}

class _EdfHeader {
  const _EdfHeader({
    required this.headerBytes,
    required this.numDataRecords,
    required this.recordDurationSeconds,
    required this.numSignals,
  });

  final int headerBytes;
  final int numDataRecords;
  final double recordDurationSeconds;
  final int numSignals;
}

class _EdfSignalHeader {
  const _EdfSignalHeader({
    required this.label,
    required this.physicalMin,
    required this.physicalMax,
    required this.digitalMin,
    required this.digitalMax,
    required this.samplesPerRecord,
  });

  final String label;
  final double physicalMin;
  final double physicalMax;
  final int digitalMin;
  final int digitalMax;
  final int samplesPerRecord;

  double sampleRate(double recordDurationSeconds) {
    return samplesPerRecord / recordDurationSeconds;
  }

  double toPhysicalValue(int digitalValue) {
    if (digitalMax == digitalMin) {
      return digitalValue.toDouble();
    }
    final double scale =
        (physicalMax - physicalMin) / (digitalMax - digitalMin);
    return physicalMin + ((digitalValue - digitalMin) * scale);
  }
}
