import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class ExportEdfNodeType extends NodeType {
  @override
  String get title => 'Export EDF';

  @override
  NodeCategory get category => NodeCategory.export;

  @override
  Map<String, dynamic> get defaultParams => {
    'selectedDatasetIds': <String>[],
    'outputDirectory': '',
    'filenameSuffix': '_brainstory',
  };

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
  ];

  @override
  List<PortSpec> get outputs => const [];

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextFormField(
          initialValue: params['outputDirectory']?.toString() ?? '',
          decoration: const InputDecoration(
            labelText: 'Output directory (optional)',
            helperText: 'Leave blank to export next to the source file.',
          ),
          onChanged: (String value) {
            setState(() {
              params['outputDirectory'] = value.trim();
            });
          },
        ),
        TextFormField(
          initialValue: params['filenameSuffix']?.toString() ?? '_brainstory',
          decoration: const InputDecoration(
            labelText: 'Filename suffix',
            helperText: 'Appended before .edf',
          ),
          onChanged: (String value) {
            setState(() {
              params['filenameSuffix'] = value.trim();
            });
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Exports the incoming signal for each selected dataset as a single-channel EDF.',
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.samples.isEmpty) {
      return;
    }
    final List<double> samples = timeSeries.samples;
    final double sampleRate = timeSeries.sampleRate;

    final String suffix = (params['filenameSuffix']?.toString().trim().isEmpty ?? true)
        ? '_brainstory'
        : params['filenameSuffix'].toString().trim();
    final String outputDirectory = params['outputDirectory']?.toString().trim() ?? '';
    final File outputFile = resolveEdfExportFile(
      dataset: dataset,
      outputDirectory: outputDirectory,
      filenameSuffix: suffix,
    );

    await outputFile.parent.create(recursive: true);
    final List<int> bytes = buildSingleChannelEdfBytes(
      samples: samples,
      sampleRate: sampleRate,
      label: dataset.label.isEmpty ? 'Signal' : dataset.label,
    );
    await outputFile.writeAsBytes(bytes, flush: true);
    dataset.ram['export.lastEdfPath'] = outputFile.path;
  }
}

File resolveEdfExportFile({
  required Dataset dataset,
  required String outputDirectory,
  required String filenameSuffix,
}) {
  final String baseName = _sanitizeFilename(
    dataset.label.isEmpty ? 'brainstory_signal' : dataset.label,
  );

  if (outputDirectory.isNotEmpty) {
    return File(
      '${Directory(outputDirectory).path}${Platform.pathSeparator}$baseName$filenameSuffix.edf',
    );
  }

  if (dataset.path.isNotEmpty) {
    final File sourceFile = File(dataset.path);
    final String sourceDir = sourceFile.parent.path;
    final String sourceName = _sanitizeFilename(
      sourceFile.uri.pathSegments.isEmpty
          ? baseName
          : sourceFile.uri.pathSegments.last.split('.').first,
    );
    return File(
      '$sourceDir${Platform.pathSeparator}$sourceName$filenameSuffix.edf',
    );
  }

  final Directory fallbackDir = Directory('${Directory.current.path}${Platform.pathSeparator}exports');
  return File(
    '${fallbackDir.path}${Platform.pathSeparator}$baseName$filenameSuffix.edf',
  );
}

List<int> buildSingleChannelEdfBytes({
  required List<double> samples,
  required double sampleRate,
  required String label,
}) {
  if (samples.isEmpty) {
    throw ArgumentError('Cannot export an empty signal.');
  }

  final int samplesPerRecord = sampleRate.round().clamp(1, 4096);
  final double recordDuration = samplesPerRecord / sampleRate;
  final int numDataRecords = (samples.length / samplesPerRecord).ceil();
  final List<double> paddedSamples = List<double>.filled(
    numDataRecords * samplesPerRecord,
    0.0,
  );
  for (int i = 0; i < samples.length; i++) {
    paddedSamples[i] = samples[i];
  }

  final double minSample = samples.reduce((double a, double b) => a < b ? a : b);
  final double maxSample = samples.reduce((double a, double b) => a > b ? a : b);
  final double physicalMin = minSample == maxSample ? minSample - 1.0 : minSample;
  final double physicalMax = minSample == maxSample ? maxSample + 1.0 : maxSample;
  const int digitalMin = -32768;
  const int digitalMax = 32767;
  final double scale = (digitalMax - digitalMin) / (physicalMax - physicalMin);

  String field(String value, int length) {
    final String trimmed = value.length > length ? value.substring(0, length) : value;
    return trimmed.padRight(length);
  }

  final StringBuffer header = StringBuffer()
    ..write(field('0', 8))
    ..write(field('BrainStory', 80))
    ..write(field('Exported from BrainStory', 80))
    ..write(field(_formatEdfDate(DateTime.now()), 8))
    ..write(field(_formatEdfTime(DateTime.now()), 8))
    ..write(field('512', 8))
    ..write(field('EDF+C', 44))
    ..write(field(numDataRecords.toString(), 8))
    ..write(field(recordDuration.toStringAsFixed(6), 8))
    ..write(field('1', 4))
    ..write(field(label, 16))
    ..write(field('', 80))
    ..write(field('uV', 8))
    ..write(field(physicalMin.toStringAsFixed(6), 8))
    ..write(field(physicalMax.toStringAsFixed(6), 8))
    ..write(field(digitalMin.toString(), 8))
    ..write(field(digitalMax.toString(), 8))
    ..write(field('', 80))
    ..write(field(samplesPerRecord.toString(), 8))
    ..write(field('', 32));

  final BytesBuilder builder = BytesBuilder();
  builder.add(header.toString().codeUnits);

  for (int i = 0; i < paddedSamples.length; i++) {
    final double clamped = paddedSamples[i].clamp(physicalMin, physicalMax);
    final int digital = (digitalMin + ((clamped - physicalMin) * scale)).round()
        .clamp(digitalMin, digitalMax);
    final int unsigned = digital & 0xFFFF;
    builder.add(<int>[unsigned & 0xFF, (unsigned >> 8) & 0xFF]);
  }

  return builder.takeBytes();
}

String _formatEdfDate(DateTime dateTime) {
  final String day = dateTime.day.toString().padLeft(2, '0');
  final String month = dateTime.month.toString().padLeft(2, '0');
  final String year = (dateTime.year % 100).toString().padLeft(2, '0');
  return '$day.$month.$year';
}

String _formatEdfTime(DateTime dateTime) {
  final String hour = dateTime.hour.toString().padLeft(2, '0');
  final String minute = dateTime.minute.toString().padLeft(2, '0');
  final String second = dateTime.second.toString().padLeft(2, '0');
  return '$hour.$minute.$second';
}

String _sanitizeFilename(String input) {
  return input
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
}
