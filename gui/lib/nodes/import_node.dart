import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

class ParsedSignalData {
  const ParsedSignalData({
    required this.samples,
    required this.sampleRate,
    required this.sourceDescription,
  });

  final List<double> samples;
  final double sampleRate;
  final String sourceDescription;
}

class ImportNodeType extends NodeType {
  @override
  String get title => 'Import';

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
            'BrainStory can parse CSV, TSV, and whitespace-delimited numeric files. If the first numeric column looks like time, sample rate is inferred automatically.',
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
    dataset.ram['signal.fs'] = parsed.sampleRate;
    dataset.ram['signal.samples'] = parsed.samples;
    dataset.ram['signal.source'] = parsed.sourceDescription;
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
  for (final String rawLine in contents.split(RegExp(r'\r?\n'))) {
    final String line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }

    final List<double> numericValues = _parseNumericRow(line);
    if (numericValues.isNotEmpty) {
      rows.add(numericValues);
    }
  }

  if (rows.isEmpty) {
    throw const FormatException('No numeric rows were found in the dataset.');
  }

  if (_looksLikeTimeSeries(rows)) {
    final List<double> timeColumn = rows.map((List<double> row) => row[0]).toList();
    final List<double> samples = rows.map((List<double> row) => row[1]).toList();
    return ParsedSignalData(
      samples: samples,
      sampleRate: _inferSampleRate(timeColumn, fallbackSampleRate),
      sourceDescription: sourceDescription,
    );
  }

  final List<double> samples = rows.map((List<double> row) => row.first).toList();
  return ParsedSignalData(
    samples: samples,
    sampleRate: fallbackSampleRate,
    sourceDescription: sourceDescription,
  );
}

List<double> _parseNumericRow(String line) {
  final String delimiter = _preferredDelimiter(line);
  final Iterable<String> tokens = delimiter.isEmpty
      ? line.split(RegExp(r'\s+'))
      : line.split(delimiter);

  return tokens
      .map((String token) => double.tryParse(token.trim()))
      .whereType<double>()
      .toList();
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

  final double meanDelta = deltaSum / deltaCount;
  return meanDelta <= 0 ? fallbackSampleRate : 1.0 / meanDelta;
}

ParsedSignalData _syntheticSignal(double sampleRate) {
  final int sampleCount = math.max(1, (sampleRate * 5).round());
  final List<double> samples = List<double>.generate(sampleCount, (int i) {
    final double t = i / sampleRate;
    return 0.8 * math.sin(2 * math.pi * 10 * t) +
        0.4 * math.sin(2 * math.pi * 20 * t);
  });

  return ParsedSignalData(
    samples: samples,
    sampleRate: sampleRate,
    sourceDescription: 'synthetic',
  );
}
