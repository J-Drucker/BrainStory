import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/file_readers.dart';
import 'node_type.dart';

class ParsedSignalData {
  const ParsedSignalData({
    required this.channelSamples,
    required this.sampleRate,
    required this.channelLabels,
    required this.sourceDescription,
    this.markers = const <TimeMarker>[],
  });

  final List<List<double>> channelSamples;
  final double sampleRate;
  final List<String> channelLabels;
  final String sourceDescription;
  final List<TimeMarker> markers;

  List<double> get samples =>
      channelSamples.isEmpty ? const <double>[] : channelSamples.first;
}

class ImportNodeType extends NodeType {
  @override
  String get title => 'Import';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  String get subcategory => 'Subcategory 1';

  @override
  Map<String, dynamic> get defaultParams => {
    'selectedDatasetIds': <String>[],
    'sampleRateHz': 256.0,
    'datasetAliases': <String, dynamic>{},
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
    params.putIfAbsent('datasetAliases', () => <String, dynamic>{});
    final Map<String, dynamic> aliases =
        Map<String, dynamic>.from(params['datasetAliases'] as Map? ?? <String, dynamic>{});

    return SizedBox(
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            entries.isEmpty
                ? 'Open datasets from the right panel, then choose which ones this import node should expose below.'
                : 'Choose which datasets this import node should expose using the table below.',
          ),
          const SizedBox(height: 12),
          const Text(
            'CSV, TSV, whitespace-delimited text, EDF, and EEGLAB .set/.fdt pairs are supported. For EEGLAB imports, you can select either file from the pair; BrainStory will normalize to the .set metadata file and use the sibling .fdt automatically. BrainStory will infer timing when it can and quietly fall back to its internal default when it cannot. Multi-channel text tables and EDF channel sets are preserved.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Dataset names in BrainStory',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries.isEmpty
                ? const Text(
                    'Add files first, then map each filename to the name BrainStory should use.',
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final Dataset dataset = entries[index].value;
                      final String sourceName = datasetSourceName(dataset);
                      final String currentValue =
                          aliases[dataset.id]?.toString() ?? dataset.label;
                      return _DatasetAliasField(
                        key: ValueKey<String>(dataset.id),
                        sourceName: sourceName,
                        currentValue: currentValue,
                        onChanged: (String value) {
                          final Map<String, dynamic> nextAliases =
                              Map<String, dynamic>.from(
                            params['datasetAliases'] as Map? ?? <String, dynamic>{},
                          );
                          nextAliases[dataset.id] = value;
                          params['datasetAliases'] = nextAliases;
                        },
                      );
                    },
                  ),
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
      fileBytes: dataset.sourceBytes,
      sourceDescription:
          dataset.path.isNotEmpty ? dataset.path : dataset.label,
    );

    dataset.loaded = true;
    dataset.timeSeries = TimeSeriesData(
      channelSamples: parsed.channelSamples,
      sampleRate: parsed.sampleRate,
      channelLabels: parsed.channelLabels,
      markers: parsed.markers,
      source: parsed.sourceDescription,
    );
  }

  static void applyDatasetAliases(
    Map<String, dynamic> params,
    Iterable<Dataset> datasets,
  ) {
    final Map<String, dynamic> aliases =
        Map<String, dynamic>.from(params['datasetAliases'] as Map? ?? <String, dynamic>{});
    for (final Dataset dataset in datasets) {
      final String sourceName = datasetSourceName(dataset);
      final String alias = aliases[dataset.id]?.toString().trim() ?? '';
      dataset.label = alias.isEmpty ? sourceName : alias;
    }
  }
}

String datasetSourceName(Dataset dataset) {
  final String stored = dataset.ram['source.filename']?.toString().trim() ?? '';
  if (stored.isNotEmpty) {
    return stored;
  }

  final String path = dataset.path.trim();
  if (path.isNotEmpty) {
    final String normalized = path.replaceAll('\\', '/');
    final int slashIndex = normalized.lastIndexOf('/');
    return slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized;
  }

  return dataset.label.trim().isEmpty ? 'Dataset' : dataset.label.trim();
}

String eeglabMetadataPathForSelection(String path) {
  final String trimmed = path.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final String normalized = trimmed.replaceAll('/', '\\');
  final String lower = normalized.toLowerCase();
  if (!lower.endsWith('.fdt')) {
    return trimmed;
  }
  return '${normalized.substring(0, normalized.length - 4)}.set';
}

Future<ParsedSignalData> loadDatasetSignal(
  String path, {
  required double fallbackSampleRate,
  Uint8List? fileBytes,
  String? sourceDescription,
}) async {
  final String normalizedPath = eeglabMetadataPathForSelection(path);
  final String resolvedSourceDescription =
      sourceDescription ?? (normalizedPath.isEmpty ? 'synthetic' : normalizedPath);
  final String normalizedSourceDescription =
      eeglabMetadataPathForSelection(resolvedSourceDescription);

  if ((normalizedPath.isEmpty && fileBytes == null) ||
      normalizedSourceDescription == 'synthetic') {
    return _syntheticSignal(fallbackSampleRate);
  }

  final String lowerPath = normalizedSourceDescription.toLowerCase();
  if (lowerPath.endsWith('.edf')) {
    final Uint8List bytes = fileBytes ?? await readBytesFromPath(normalizedPath);
    return parseEdfBytes(bytes, sourceDescription: normalizedSourceDescription);
  }
  if (lowerPath.endsWith('.set')) {
    final Uint8List bytes = fileBytes ?? await readBytesFromPath(normalizedPath);
    final ParsedEeglabSetData parsedSet = parseEeglabSetBytes(
      bytes,
      sourceDescription: normalizedSourceDescription,
    );
    final String dataPath = _resolveSiblingPath(
      basePath: normalizedPath,
      siblingName: parsedSet.dataFileName,
    );
    if (dataPath.isEmpty) {
      throw const FormatException(
        'EEGLAB .set import requires a sibling .fdt data file.',
      );
    }
    final Uint8List dataBytes = await readBytesFromPath(dataPath);
    return parseEeglabFdtBytes(
      dataBytes,
      metadata: parsedSet,
      sourceDescription: normalizedSourceDescription,
    );
  }
  if (lowerPath.endsWith('.fdt')) {
    throw const FormatException(
      'Select the EEGLAB .set file, not the .fdt sidecar.',
    );
  }

  final String contents = fileBytes != null
      ? utf8.decode(fileBytes, allowMalformed: true)
      : await readTextFromPath(normalizedPath);
  return parseSignalText(
    contents,
    fallbackSampleRate: fallbackSampleRate,
    sourceDescription: normalizedSourceDescription,
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
  final Map<int, int> selectedChannelIndexBySignalIndex = <int, int>{};
  for (int signalIndex = 0; signalIndex < signals.length; signalIndex++) {
    final _EdfSignalHeader signal = signals[signalIndex];
    for (int channelIndex = 0; channelIndex < selectedSignals.length; channelIndex++) {
      if (identical(selectedSignals[channelIndex], signal)) {
        selectedChannelIndexBySignalIndex[signalIndex] = channelIndex;
        break;
      }
    }
  }
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
      final int? channelIndex = selectedChannelIndexBySignalIndex[signalIndex];

      if (channelIndex != null) {
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

class ParsedEeglabSetData {
  const ParsedEeglabSetData({
    required this.channelCount,
    required this.pointsPerTrial,
    required this.trialCount,
    required this.sampleRate,
    required this.dataFileName,
    required this.channelLabels,
    required this.markers,
  });

  final int channelCount;
  final int pointsPerTrial;
  final int trialCount;
  final double sampleRate;
  final String dataFileName;
  final List<String> channelLabels;
  final List<TimeMarker> markers;
}

ParsedEeglabSetData parseEeglabSetBytes(
  Uint8List bytes, {
  required String sourceDescription,
}) {
  final _MatFileReader reader = _MatFileReader(bytes);
  final Map<String, _MatValue> fields = reader.readTopLevelFields();

  final int channelCount = _matInt(fields['nbchan']);
  final int pointsPerTrial = _matInt(fields['pnts']);
  final int trialCount = math.max(1, _matInt(fields['trials']));
  final double sampleRate = _matDouble(fields['srate']);
  if (channelCount <= 0 || pointsPerTrial <= 0 || sampleRate <= 0) {
    throw FormatException('EEGLAB metadata in $sourceDescription is incomplete.');
  }

  final String dataFileName = _matString(fields['datfile']).isNotEmpty
      ? _matString(fields['datfile'])
      : _matString(fields['data']);
  if (dataFileName.isEmpty) {
    throw FormatException('EEGLAB dataset $sourceDescription does not point to a .fdt file.');
  }

  final List<String> channelLabels = _extractEeglabChannelLabels(
    fields['chanlocs'],
    expectedCount: channelCount,
  );
  final List<TimeMarker> markers = _extractEeglabMarkers(
    fields['event'],
    sampleRate: sampleRate,
  );

  return ParsedEeglabSetData(
    channelCount: channelCount,
    pointsPerTrial: pointsPerTrial,
    trialCount: trialCount,
    sampleRate: sampleRate,
    dataFileName: dataFileName,
    channelLabels: channelLabels,
    markers: markers,
  );
}

ParsedSignalData parseEeglabFdtBytes(
  Uint8List bytes, {
  required ParsedEeglabSetData metadata,
  required String sourceDescription,
}) {
  final int totalSamples = metadata.pointsPerTrial * metadata.trialCount;
  final int expectedValueCount = metadata.channelCount * totalSamples;
  if (bytes.lengthInBytes < expectedValueCount * 4) {
    throw const FormatException('EEGLAB .fdt file is smaller than expected.');
  }

  final ByteData data = ByteData.sublistView(bytes);
  final List<List<double>> channelSamples = List<List<double>>.generate(
    metadata.channelCount,
    (_) => List<double>.filled(totalSamples, 0.0),
    growable: false,
  );

  // EEGLAB stores .fdt payloads as float32 in column-major order with samples
  // interleaved by channel for each timepoint.
  int offset = 0;
  for (int sampleIndex = 0; sampleIndex < totalSamples; sampleIndex++) {
    for (int channelIndex = 0; channelIndex < metadata.channelCount; channelIndex++) {
      channelSamples[channelIndex][sampleIndex] = data.getFloat32(offset, Endian.little);
      offset += 4;
    }
  }

  return ParsedSignalData(
    channelSamples: channelSamples,
    sampleRate: metadata.sampleRate,
    channelLabels: metadata.channelLabels,
    sourceDescription: sourceDescription,
    markers: metadata.markers,
  );
}

String _resolveSiblingPath({
  required String basePath,
  required String siblingName,
}) {
  if (basePath.trim().isEmpty || siblingName.trim().isEmpty) {
    return '';
  }
  final String normalizedBase = basePath.replaceAll('/', '\\');
  final int separatorIndex = normalizedBase.lastIndexOf('\\');
  if (separatorIndex < 0) {
    return siblingName;
  }
  return '${normalizedBase.substring(0, separatorIndex + 1)}$siblingName';
}

List<String> _extractEeglabChannelLabels(_MatValue? value, {
  required int expectedCount,
}) {
  if (value is _MatStructArrayValue) {
    final List<String> labels = value.elements
        .map(
          (Map<String, _MatValue> element) =>
              _matString(element['labels']).trim(),
        )
        .where((String label) => label.isNotEmpty)
        .toList(growable: false);
    if (labels.length == expectedCount) {
      return labels;
    }
  }
  return List<String>.generate(
    expectedCount,
    (int index) => 'Ch ${index + 1}',
    growable: false,
  );
}

List<TimeMarker> _extractEeglabMarkers(
  _MatValue? value, {
  required double sampleRate,
}) {
  if (value is! _MatStructArrayValue) {
    return const <TimeMarker>[];
  }

  final List<TimeMarker> markers = <TimeMarker>[];
  for (final Map<String, _MatValue> element in value.elements) {
    final String label = _matString(element['type']).trim();
    final double latency = _matDouble(element['latency']);
    if (label.isEmpty || latency.isNaN) {
      continue;
    }
    final String lowerLabel = label.toLowerCase();
    final String kind = lowerLabel.contains('artifact')
        ? 'artifact'
        : lowerLabel.contains('boundary')
            ? 'boundary'
            : 'event';
    markers.add(
      TimeMarker(
        onsetMicros: (((latency - 1.0) / sampleRate) * 1000000.0).round(),
        durationMicros: kind == MarkerType.event ? 0 : 0,
        label: label,
        markerType: kind,
      ),
    );
  }
  return markers;
}

double _matDouble(_MatValue? value) {
  if (value is _MatNumericValue && value.values.isNotEmpty) {
    return value.values.first;
  }
  return double.nan;
}

int _matInt(_MatValue? value) {
  final double numeric = _matDouble(value);
  return numeric.isNaN ? 0 : numeric.round();
}

String _matString(_MatValue? value) {
  if (value is _MatCharValue) {
    return value.text;
  }
  if (value is _MatNumericValue && value.values.length == 1) {
    return value.values.first.toString();
  }
  return '';
}

abstract class _MatValue {
  const _MatValue();
}

class _MatNumericValue extends _MatValue {
  const _MatNumericValue(this.values);

  final List<double> values;
}

class _MatCharValue extends _MatValue {
  const _MatCharValue(this.text);

  final String text;
}

class _MatStructArrayValue extends _MatValue {
  const _MatStructArrayValue(this.elements);

  final List<Map<String, _MatValue>> elements;
}

class _MatFileReader {
  _MatFileReader(this.bytes)
      : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;

  static const int _miInt8 = 1;
  static const int _miUint8 = 2;
  static const int _miInt16 = 3;
  static const int _miUint16 = 4;
  static const int _miInt32 = 5;
  static const int _miUint32 = 6;
  static const int _miSingle = 7;
  static const int _miDouble = 9;
  static const int _miMatrix = 14;
  static const int _mxCharClass = 4;
  static const int _mxStructClass = 2;

  Map<String, _MatValue> readTopLevelFields() {
    int offset = 128;
    final Map<String, _MatValue> result = <String, _MatValue>{};
    while (offset + 8 <= bytes.lengthInBytes) {
      final _MatElementHeader header = _readElementHeader(offset);
      if (header.numBytes <= 0 || header.type != _miMatrix) {
        offset = header.nextOffset;
        continue;
      }
      try {
        final _ParsedMatrix matrix = _parseMatrix(header.dataOffset, header.numBytes);
        if (matrix.name.isNotEmpty) {
          result[matrix.name] = matrix.value;
        }
      } catch (_) {
        // First-pass EEGLAB support only needs scalar/string top-level fields
        // such as nbchan, pnts, srate, and datfile. If a complex nested field
        // like chanlocs or event fails to parse, skip it instead of failing the
        // whole import.
      }
      offset = header.nextOffset;
    }
    return result;
  }

  _ParsedMatrix _parseMatrix(int offset, int numBytes) {
    final _MatElementHeader flagsHeader = _readElementHeader(offset);
    final Uint8List flagsBytes = bytes.sublist(
      flagsHeader.dataOffset,
      flagsHeader.dataOffset + flagsHeader.numBytes,
    );
    final ByteData flagsData = ByteData.sublistView(flagsBytes);
    final int arrayClass = flagsData.getUint8(0);

    final _MatElementHeader dimensionsHeader = _readElementHeader(flagsHeader.nextOffset);
    final List<int> dimensions = _readIntValues(dimensionsHeader);

    final _MatElementHeader nameHeader = _readElementHeader(dimensionsHeader.nextOffset);
    final String name = _readCharBytes(nameHeader);

    int contentOffset = nameHeader.nextOffset;
    late final _MatValue value;
    if (arrayClass == _mxCharClass) {
      final _MatElementHeader realHeader = _readElementHeader(contentOffset);
      value = _MatCharValue(_readCharacterData(realHeader, dimensions));
    } else if (arrayClass == _mxStructClass) {
      final _MatElementHeader fieldNameLengthHeader = _readElementHeader(contentOffset);
      final int fieldNameLength = _readIntValues(fieldNameLengthHeader).firstOrNull ?? 0;
      final _MatElementHeader fieldNamesHeader = _readElementHeader(fieldNameLengthHeader.nextOffset);
      final List<String> fieldNames = _readFieldNames(fieldNamesHeader, fieldNameLength);
      contentOffset = fieldNamesHeader.nextOffset;
      final int elementCount = dimensions.isEmpty
          ? 1
          : dimensions.fold<int>(1, (int left, int right) => left * right);
      final Set<String>? selectedFields = switch (name) {
        'chanlocs' => const <String>{'labels'},
        'event' => const <String>{'type', 'latency'},
        _ => null,
      };
      final List<Map<String, _MatValue>> elements = _parseStructElements(
        contentOffset: contentOffset,
        fieldNames: fieldNames,
        elementCount: elementCount,
        selectedFields: selectedFields,
      );
      value = _MatStructArrayValue(elements);
    } else {
      final _MatElementHeader realHeader = _readElementHeader(contentOffset);
      value = _MatNumericValue(_readNumericValues(realHeader));
    }

    return _ParsedMatrix(name: name, value: value);
  }

  List<Map<String, _MatValue>> _parseStructElements({
    required int contentOffset,
    required List<String> fieldNames,
    required int elementCount,
    Set<String>? selectedFields,
  }) {
    final List<Map<String, _MatValue>> elements = List<Map<String, _MatValue>>.generate(
      elementCount,
      (_) => <String, _MatValue>{},
      growable: false,
    );
    int offset = contentOffset;
    for (int elementIndex = 0; elementIndex < elementCount; elementIndex++) {
      for (final String fieldName in fieldNames) {
        final _MatElementHeader fieldHeader = _readElementHeader(offset);
        if (selectedFields == null || selectedFields.contains(fieldName)) {
          final _MatValue? value = _tryParsePrimitiveMatrix(
            fieldHeader.dataOffset,
            fieldHeader.numBytes,
          );
          if (value != null) {
            elements[elementIndex][fieldName] = value;
          }
        }
        offset = fieldHeader.nextOffset;
      }
    }
    return elements;
  }

  _MatValue? _tryParsePrimitiveMatrix(int offset, int numBytes) {
    final _MatElementHeader flagsHeader = _readElementHeader(offset);
    if (flagsHeader.numBytes <= 0) {
      return null;
    }
    final Uint8List flagsBytes = bytes.sublist(
      flagsHeader.dataOffset,
      flagsHeader.dataOffset + flagsHeader.numBytes,
    );
    if (flagsBytes.isEmpty) {
      return null;
    }
    final ByteData flagsData = ByteData.sublistView(flagsBytes);
    final int arrayClass = flagsData.getUint8(0);
    final _MatElementHeader dimensionsHeader = _readElementHeader(flagsHeader.nextOffset);
    final List<int> dimensions = _readIntValues(dimensionsHeader);
    final _MatElementHeader nameHeader = _readElementHeader(dimensionsHeader.nextOffset);
    final int contentOffset = nameHeader.nextOffset;
    if (arrayClass == _mxCharClass) {
      final _MatElementHeader realHeader = _readElementHeader(contentOffset);
      return _MatCharValue(_readCharacterData(realHeader, dimensions));
    }
    final _MatElementHeader realHeader = _readElementHeader(contentOffset);
    return _MatNumericValue(_readNumericValues(realHeader));
  }

  _MatElementHeader _readElementHeader(int offset) {
    final int packedTag = data.getUint32(offset, Endian.little);
    final int smallDataBytes = packedTag >> 16;
    if (smallDataBytes > 0) {
      final int type = packedTag & 0xFFFF;
      return _MatElementHeader(
        type: type,
        numBytes: smallDataBytes,
        dataOffset: offset + 4,
        nextOffset: offset + 8,
      );
    }

    final int type = packedTag;
    final int numBytes = data.getUint32(offset + 4, Endian.little);
    final int paddedBytes = ((numBytes + 7) ~/ 8) * 8;
    return _MatElementHeader(
      type: type,
      numBytes: numBytes,
      dataOffset: offset + 8,
      nextOffset: offset + 8 + paddedBytes,
    );
  }

  List<int> _readIntValues(_MatElementHeader header) {
    final List<double> values = _readNumericValues(header);
    return values.map((double value) => value.round()).toList(growable: false);
  }

  List<double> _readNumericValues(_MatElementHeader header) {
    final int count = switch (header.type) {
      _miDouble => header.numBytes ~/ 8,
      _miSingle => header.numBytes ~/ 4,
      _miInt32 || _miUint32 => header.numBytes ~/ 4,
      _miInt16 || _miUint16 => header.numBytes ~/ 2,
      _miInt8 || _miUint8 => header.numBytes,
      _ => 0,
    };
    final List<double> values = List<double>.filled(count, 0.0, growable: false);
    for (int i = 0; i < count; i++) {
      final int itemOffset = header.dataOffset +
          (switch (header.type) {
            _miDouble => i * 8,
            _miSingle || _miInt32 || _miUint32 => i * 4,
            _miInt16 || _miUint16 => i * 2,
            _ => i,
          });
      values[i] = switch (header.type) {
        _miDouble => data.getFloat64(itemOffset, Endian.little),
        _miSingle => data.getFloat32(itemOffset, Endian.little),
        _miInt32 => data.getInt32(itemOffset, Endian.little).toDouble(),
        _miUint32 => data.getUint32(itemOffset, Endian.little).toDouble(),
        _miInt16 => data.getInt16(itemOffset, Endian.little).toDouble(),
        _miUint16 => data.getUint16(itemOffset, Endian.little).toDouble(),
        _miInt8 => data.getInt8(itemOffset).toDouble(),
        _miUint8 => data.getUint8(itemOffset).toDouble(),
        _ => double.nan,
      };
    }
    return values;
  }

  String _readCharBytes(_MatElementHeader header) {
    return ascii
        .decode(
          bytes.sublist(header.dataOffset, header.dataOffset + header.numBytes),
          allowInvalid: true,
        )
        .replaceAll('\u0000', '')
        .trim();
  }

  String _readCharacterData(_MatElementHeader header, List<int> dimensions) {
    if (header.type == _miUint16) {
      final int count = header.numBytes ~/ 2;
      final List<int> codeUnits = List<int>.generate(
        count,
        (int index) => data.getUint16(header.dataOffset + (index * 2), Endian.little),
        growable: false,
      );
      return String.fromCharCodes(codeUnits).replaceAll('\u0000', '').trim();
    }
    return _readCharBytes(header);
  }

  List<String> _readFieldNames(_MatElementHeader header, int fieldNameLength) {
    final Uint8List raw = bytes.sublist(
      header.dataOffset,
      header.dataOffset + header.numBytes,
    );
    final List<String> fieldNames = <String>[];
    for (int offset = 0; offset + fieldNameLength <= raw.length; offset += fieldNameLength) {
      final String fieldName = ascii
          .decode(raw.sublist(offset, offset + fieldNameLength), allowInvalid: true)
          .replaceAll('\u0000', '')
          .trim();
      if (fieldName.isNotEmpty) {
        fieldNames.add(fieldName);
      }
    }
    return fieldNames;
  }
}

class _MatElementHeader {
  const _MatElementHeader({
    required this.type,
    required this.numBytes,
    required this.dataOffset,
    required this.nextOffset,
  });

  final int type;
  final int numBytes;
  final int dataOffset;
  final int nextOffset;
}

class _ParsedMatrix {
  const _ParsedMatrix({
    required this.name,
    required this.value,
  });

  final String name;
  final _MatValue value;
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

class _DatasetAliasField extends StatefulWidget {
  const _DatasetAliasField({
    super.key,
    required this.sourceName,
    required this.currentValue,
    required this.onChanged,
  });

  final String sourceName;
  final String currentValue;
  final ValueChanged<String> onChanged;

  @override
  State<_DatasetAliasField> createState() => _DatasetAliasFieldState();
}

class _DatasetAliasFieldState extends State<_DatasetAliasField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void didUpdateWidget(covariant _DatasetAliasField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentValue != widget.currentValue &&
        _controller.text != widget.currentValue) {
      _controller.value = TextEditingValue(
        text: widget.currentValue,
        selection: TextSelection.collapsed(offset: widget.currentValue.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.sourceName,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'BrainStory name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
