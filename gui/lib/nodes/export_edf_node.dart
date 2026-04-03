import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/file_save.dart';
import '../platform/file_save_resolve.dart';
import 'node_type.dart';

class ExportNodeType extends NodeType {
  @override
  String get title => 'Export';

  @override
  NodeCategory get category => NodeCategory.export;

  @override
  Map<String, dynamic> get defaultParams => {
    'selectedDatasetIds': <String>[],
    'fileType': 'edf',
    'outputDirectory': '',
    'filenameSuffix': '_brainstory',
  };

  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'table', type: PortType.metadata),
  ];

  @override
  List<PortSpec> get outputs => const [];

  @override
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      }) {
    params.putIfAbsent('fileType', () => 'edf');
    final _ExportCapabilities capabilities = _visibleExportCapabilities(
      datasets: datasets,
      selectedDatasetIds:
          params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[],
    );
    final List<NodeDropdownOption<String>> fileTypeOptions =
        <NodeDropdownOption<String>>[
      NodeDropdownOption<String>(
        value: 'edf',
        label: capabilities.hasSignal ? 'EDF' : 'EDF (needs signal input)',
        enabled: capabilities.hasSignal,
      ),
      NodeDropdownOption<String>(
        value: 'csv',
        label: capabilities.hasFeatureTable
            ? 'CSV'
            : 'CSV (needs table output)',
        enabled: capabilities.hasFeatureTable,
      ),
      const NodeDropdownOption<String>(
        value: 'json',
        label: 'JSON (coming soon)',
        enabled: false,
      ),
    ];
    final String currentFileType = params['fileType']?.toString() ?? 'edf';
    final bool currentEnabled = fileTypeOptions.any(
      (NodeDropdownOption<String> option) =>
          option.value == currentFileType && option.enabled,
    );
    if (!currentEnabled) {
      final NodeDropdownOption<String>? fallback = fileTypeOptions
          .cast<NodeDropdownOption<String>?>()
          .firstWhere(
            (NodeDropdownOption<String>? option) => option?.enabled == true,
            orElse: () => null,
          );
      if (fallback != null) {
        params['fileType'] = fallback.value;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'fileType',
          labelText: 'File type',
          helperText:
              'Formats are enabled when the currently available upstream artifact type supports them.',
          options: fileTypeOptions,
        ),
        const SizedBox(height: 8),
        NodeParamTextField(
          params: params,
          paramKey: 'outputDirectory',
          labelText: 'Output directory (optional)',
          helperText: kIsWeb
              ? 'Ignored on web. The EDF will download in the browser.'
              : 'Leave blank to export next to the source file.',
          parser: (String value, dynamic _) => value.trim(),
        ),
        NodeParamTextField(
          params: params,
          paramKey: 'filenameSuffix',
          labelText: 'Filename suffix',
          helperText: 'Appended before .edf',
          parser: (String value, dynamic _) => value.trim(),
        ),
        const SizedBox(height: 8),
        Text(
          switch ((params['fileType']?.toString() ?? 'edf')) {
            'edf' =>
              'Exports the incoming signal for each selected dataset as an EDF. Multi-channel signals are preserved.',
            'csv' =>
              'Exports the incoming table artifact for each selected dataset as a CSV file.',
            _ => 'This export type is not implemented yet.',
          },
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final String fileType = params['fileType']?.toString() ?? 'edf';
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    final String suffix = (params['filenameSuffix']?.toString().trim().isEmpty ?? true)
        ? '_brainstory'
        : params['filenameSuffix'].toString().trim();
    final String outputDirectory = params['outputDirectory']?.toString().trim() ?? '';
    late final SavedFileResult result;

    switch (fileType) {
      case 'edf':
        if (timeSeries == null || timeSeries.primaryChannel.isEmpty) {
          return;
        }
        final List<int> bytes = buildEdfBytes(
          channelSamples: timeSeries.channels,
          sampleRate: timeSeries.sampleRate,
          labels: timeSeries.channelLabels.isEmpty
              ? List<String>.generate(
                  timeSeries.channels.length,
                  (int index) => '${dataset.label.isEmpty ? 'Signal' : dataset.label} ${index + 1}',
                  growable: false,
                )
              : timeSeries.channelLabels,
        );
        result = await saveEdfBytes(
          bytes: Uint8List.fromList(bytes),
          suggestedBaseName: dataset.label,
          filenameSuffix: suffix,
          datasetPath: dataset.path,
          outputDirectory: outputDirectory,
        );
        dataset.ram['export.lastEdfPath'] = result.locationLabel;
        break;
      case 'csv':
        final FeatureTableData? featureTable = dataset.featureTable;
        if (featureTable == null) {
          return;
        }
        result = await saveTextFile(
          text: featureTable.toCsv(),
          suggestedBaseName: dataset.label.isEmpty ? 'brainstory_table' : dataset.label,
          filenameSuffix: suffix,
          fileExtension: 'csv',
          datasetPath: dataset.path,
          outputDirectory: outputDirectory,
        );
        dataset.ram['export.lastCsvPath'] = result.locationLabel;
        break;
      default:
        throw UnsupportedError(
          'Export type "$fileType" is not implemented yet.',
        );
    }

    dataset.ram['export.persistedToDisk'] = result.persistedToDisk;
  }
}

String resolveEdfExportFile({
  required Dataset dataset,
  required String outputDirectory,
  required String filenameSuffix,
}) {
  return resolveEdfExportFilePath(
    datasetPath: dataset.path,
    outputDirectory: outputDirectory,
    filenameSuffix: filenameSuffix,
    suggestedBaseName: dataset.label.isEmpty ? 'brainstory_signal' : dataset.label,
  );
}

String resolveTextExportFile({
  required Dataset dataset,
  required String outputDirectory,
  required String filenameSuffix,
  required String fileExtension,
}) {
  return resolveGenericExportFilePath(
    datasetPath: dataset.path,
    outputDirectory: outputDirectory,
    filenameSuffix: filenameSuffix,
    suggestedBaseName: dataset.label.isEmpty ? 'brainstory_export' : dataset.label,
    fileExtension: fileExtension,
  );
}

class _ExportCapabilities {
  const _ExportCapabilities({
    required this.hasSignal,
    required this.hasFeatureTable,
  });

  final bool hasSignal;
  final bool hasFeatureTable;
}

_ExportCapabilities _visibleExportCapabilities({
  required Map<String, Dataset> datasets,
  required List<dynamic> selectedDatasetIds,
}) {
  final Iterable<Dataset> visibleDatasets = datasets.values.where((Dataset dataset) {
    return selectedDatasetIds.isEmpty || selectedDatasetIds.contains(dataset.id);
  });
  bool hasSignal = false;
  bool hasFeatureTable = false;
  for (final Dataset dataset in visibleDatasets) {
    hasSignal = hasSignal ||
        (dataset.timeSeries != null && dataset.timeSeries!.primaryChannel.isNotEmpty);
    hasFeatureTable = hasFeatureTable || dataset.featureTable != null;
  }
  return _ExportCapabilities(
    hasSignal: hasSignal,
    hasFeatureTable: hasFeatureTable,
  );
}

List<int> buildSingleChannelEdfBytes({
  required List<double> samples,
  required double sampleRate,
  required String label,
}) {
  return buildEdfBytes(
    channelSamples: <List<double>>[samples],
    sampleRate: sampleRate,
    labels: <String>[label],
  );
}

List<int> buildEdfBytes({
  required List<List<double>> channelSamples,
  required double sampleRate,
  required List<String> labels,
}) {
  if (channelSamples.isEmpty) {
    throw ArgumentError('Cannot export an empty signal.');
  }
  if (channelSamples.any((List<double> samples) => samples.isEmpty)) {
    throw ArgumentError('Cannot export an empty signal.');
  }

  final int samplesPerRecord = sampleRate.round().clamp(1, 4096);
  final double recordDuration = samplesPerRecord / sampleRate;
  final int maxChannelLength = channelSamples
      .map((List<double> channel) => channel.length)
      .reduce((int left, int right) => left > right ? left : right);
  final int numDataRecords = (maxChannelLength / samplesPerRecord).ceil();
  final int channelCount = channelSamples.length;
  final List<List<double>> paddedChannels = channelSamples.map((List<double> samples) {
    final List<double> padded = List<double>.filled(
      numDataRecords * samplesPerRecord,
      0.0,
    );
    for (int i = 0; i < samples.length; i++) {
      padded[i] = samples[i];
    }
    return padded;
  }).toList(growable: false);

  final List<double> physicalMins = paddedChannels
      .map((List<double> samples) => samples.reduce((double a, double b) => a < b ? a : b))
      .toList(growable: false);
  final List<double> physicalMaxs = paddedChannels
      .map((List<double> samples) => samples.reduce((double a, double b) => a > b ? a : b))
      .toList(growable: false);

  const int digitalMin = -32768;
  const int digitalMax = 32767;

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
    ..write(field((256 + (channelCount * 256)).toString(), 8))
    ..write(field('EDF+C', 44))
    ..write(field(numDataRecords.toString(), 8))
    ..write(field(recordDuration.toStringAsFixed(6), 8))
    ..write(field(channelCount.toString(), 4));

  for (int index = 0; index < channelCount; index++) {
    final String label = index < labels.length ? labels[index] : 'Ch ${index + 1}';
    header.write(field(label, 16));
  }
  for (int index = 0; index < channelCount; index++) {
    header.write(field('', 80));
  }
  for (int index = 0; index < channelCount; index++) {
    header.write(field('uV', 8));
  }
  for (int index = 0; index < channelCount; index++) {
    final double physicalMin = physicalMins[index] == physicalMaxs[index]
        ? physicalMins[index] - 1.0
        : physicalMins[index];
    header.write(field(physicalMin.toStringAsFixed(6), 8));
    physicalMins[index] = physicalMin;
  }
  for (int index = 0; index < channelCount; index++) {
    final double physicalMax = physicalMins[index] == physicalMaxs[index]
        ? physicalMaxs[index] + 1.0
        : physicalMaxs[index];
    header.write(field(physicalMax.toStringAsFixed(6), 8));
    physicalMaxs[index] = physicalMax;
  }
  for (int index = 0; index < channelCount; index++) {
    header.write(field(digitalMin.toString(), 8));
  }
  for (int index = 0; index < channelCount; index++) {
    header.write(field(digitalMax.toString(), 8));
  }
  for (int index = 0; index < channelCount; index++) {
    header.write(field('', 80));
  }
  for (int index = 0; index < channelCount; index++) {
    header.write(field(samplesPerRecord.toString(), 8));
  }
  for (int index = 0; index < channelCount; index++) {
    header.write(field('', 32));
  }

  final BytesBuilder builder = BytesBuilder();
  builder.add(header.toString().codeUnits);

  final List<double> scales = List<double>.generate(channelCount, (int index) {
    return (digitalMax - digitalMin) / (physicalMaxs[index] - physicalMins[index]);
  }, growable: false);

  for (int record = 0; record < numDataRecords; record++) {
    for (int channelIndex = 0; channelIndex < channelCount; channelIndex++) {
      final List<double> channel = paddedChannels[channelIndex];
      for (int sampleIndex = 0; sampleIndex < samplesPerRecord; sampleIndex++) {
        final int absoluteIndex = (record * samplesPerRecord) + sampleIndex;
        final double clamped = channel[absoluteIndex].clamp(
          physicalMins[channelIndex],
          physicalMaxs[channelIndex],
        );
        final int digital = (digitalMin +
                ((clamped - physicalMins[channelIndex]) * scales[channelIndex]))
            .round()
            .clamp(digitalMin, digitalMax);
        final int unsigned = digital & 0xFFFF;
        builder.add(<int>[unsigned & 0xFF, (unsigned >> 8) & 0xFF]);
      }
    }
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
