import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class AverageNodeType extends NodeType {
  @override
  String get title => 'Average';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Subcategory 1';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'sourceArtifact': 'auto',
        'averageChannels': true,
        'averageTimePoints': false,
        'averageSegments': true,
        'averageFrequencies': false,
        'averageMatrixRows': false,
        'averageMatrixColumns': false,
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
        PortSpec(name: 'segments', type: PortType.metadata),
        PortSpec(name: 'matrix', type: PortType.matrixTransformation),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
        PortSpec(name: 'spectrum', type: PortType.signal),
        PortSpec(name: 'segments', type: PortType.metadata),
        PortSpec(name: 'table', type: PortType.metadata),
        PortSpec(name: 'matrix', type: PortType.matrixTransformation),
      ];

  @override
  bool get supportsBackgroundRun => true;

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    for (final MapEntry<String, dynamic> entry in defaultParams.entries) {
      params.putIfAbsent(entry.key, () => entry.value);
    }

    final _AverageAvailability availability =
        _AverageAvailability.fromDatasets(datasets.values);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Choose the thing you want to collapse. If an axis collapse still leaves a signal-like object, BrainStory keeps it as signal data; if it collapses to scalars, it becomes a CSV-ready table.',
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'sourceArtifact',
          labelText: 'Average input',
          options: <NodeDropdownOption<String>>[
            const NodeDropdownOption<String>(
              value: 'auto',
              label: 'Auto: use the richest available input',
            ),
            NodeDropdownOption<String>(
              value: 'timeSeries',
              label: 'Time series',
              enabled: availability.hasTimeSeries,
            ),
            NodeDropdownOption<String>(
              value: 'segmentedTimeSeries',
              label: 'Segmented time series',
              enabled: availability.hasSegments,
            ),
            NodeDropdownOption<String>(
              value: 'spectrum',
              label: 'Spectrum / PSD',
              enabled: availability.hasSpectrum,
            ),
            NodeDropdownOption<String>(
              value: 'timeFrequency',
              label: 'Time-frequency',
              enabled: availability.hasTimeFrequency,
            ),
            NodeDropdownOption<String>(
              value: 'matrixTransformation',
              label: 'Matrix',
              enabled: availability.hasMatrix,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Average across what?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _AverageAxisTile(
          params: params,
          paramKey: 'averageChannels',
          title: 'Channels',
          subtitle: 'Collapse electrodes/channels into an average trace.',
          enabled: availability.hasChannels,
          setState: setState,
        ),
        _AverageAxisTile(
          params: params,
          paramKey: 'averageTimePoints',
          title: 'Time points',
          subtitle: 'Collapse time into scalar mean values.',
          enabled: availability.hasTimeAxis,
          setState: setState,
        ),
        _AverageAxisTile(
          params: params,
          paramKey: 'averageSegments',
          title: 'Segments',
          subtitle: 'Average matching segmented epochs by marker label.',
          enabled: availability.hasSegments,
          setState: setState,
        ),
        _AverageAxisTile(
          params: params,
          paramKey: 'averageFrequencies',
          title: 'Frequencies',
          subtitle: 'Collapse frequency bins into mean power.',
          enabled: availability.hasFrequencyAxis,
          setState: setState,
        ),
        _AverageAxisTile(
          params: params,
          paramKey: 'averageMatrixRows',
          title: 'Matrix rows / components',
          subtitle: 'Collapse matrix rows into one row.',
          enabled: availability.hasMatrix,
          setState: setState,
        ),
        _AverageAxisTile(
          params: params,
          paramKey: 'averageMatrixColumns',
          title: 'Matrix columns',
          subtitle: 'Collapse matrix columns into one column.',
          enabled: availability.hasMatrix,
          setState: setState,
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final String sourceArtifact = _resolveSourceArtifact(dataset, params);
    switch (sourceArtifact) {
      case 'segmentedTimeSeries':
        _averageSegmentedTimeSeries(dataset, params);
        return;
      case 'spectrum':
        _averageSpectrum(dataset, params);
        return;
      case 'timeFrequency':
        _averageTimeFrequency(dataset, params);
        return;
      case 'matrixTransformation':
        _averageMatrix(dataset, params);
        return;
      case 'timeSeries':
      default:
        _averageTimeSeries(dataset, params);
        return;
    }
  }
}

class _AverageAvailability {
  const _AverageAvailability({
    required this.hasTimeSeries,
    required this.hasSegments,
    required this.hasSpectrum,
    required this.hasTimeFrequency,
    required this.hasMatrix,
    required this.hasChannels,
    required this.hasTimeAxis,
    required this.hasFrequencyAxis,
  });

  final bool hasTimeSeries;
  final bool hasSegments;
  final bool hasSpectrum;
  final bool hasTimeFrequency;
  final bool hasMatrix;
  final bool hasChannels;
  final bool hasTimeAxis;
  final bool hasFrequencyAxis;

  static _AverageAvailability fromDatasets(Iterable<Dataset> datasets) {
    bool hasTimeSeries = false;
    bool hasSegments = false;
    bool hasSpectrum = false;
    bool hasTimeFrequency = false;
    bool hasMatrix = false;
    bool hasChannels = false;
    bool hasTimeAxis = false;
    bool hasFrequencyAxis = false;
    for (final Dataset dataset in datasets) {
      final TimeSeriesData? timeSeries = dataset.timeSeries;
      final SegmentedTimeSeriesData? segments = dataset.segmentedTimeSeries;
      final FrequencySpectrumData? spectrum = dataset.spectrum;
      final TimeFrequencyData? timeFrequency = dataset.timeFrequency;
      final MatrixTransformationData? matrix = dataset.matrixTransformation;
      hasTimeSeries = hasTimeSeries || timeSeries != null;
      hasSegments = hasSegments || segments != null;
      hasSpectrum = hasSpectrum || spectrum != null;
      hasTimeFrequency = hasTimeFrequency || timeFrequency != null;
      hasMatrix = hasMatrix || matrix != null;
      hasChannels = hasChannels ||
          (timeSeries?.channelCount ?? 0) > 1 ||
          (segments?.channelLabels.length ?? 0) > 1;
      hasTimeAxis = hasTimeAxis ||
          (timeSeries?.sampleCount ?? 0) > 1 ||
          (segments?.segments.isNotEmpty ?? false) ||
          (timeFrequency?.times.length ?? 0) > 1;
      hasFrequencyAxis = hasFrequencyAxis ||
          (spectrum?.frequencies.length ?? 0) > 1 ||
          (timeFrequency?.frequencies.length ?? 0) > 1;
    }
    return _AverageAvailability(
      hasTimeSeries: hasTimeSeries,
      hasSegments: hasSegments,
      hasSpectrum: hasSpectrum,
      hasTimeFrequency: hasTimeFrequency,
      hasMatrix: hasMatrix,
      hasChannels: hasChannels,
      hasTimeAxis: hasTimeAxis,
      hasFrequencyAxis: hasFrequencyAxis,
    );
  }
}

class _AverageAxisTile extends StatelessWidget {
  const _AverageAxisTile({
    required this.params,
    required this.paramKey,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.setState,
  });

  final Map<String, dynamic> params;
  final String paramKey;
  final String title;
  final String subtitle;
  final bool enabled;
  final void Function(void Function()) setState;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      value: params[paramKey] == true,
      title: Text(title),
      subtitle: Text(subtitle),
      onChanged: enabled
          ? (bool? value) {
              setState(() {
                params[paramKey] = value ?? false;
              });
            }
          : null,
    );
  }
}

String _resolveSourceArtifact(Dataset dataset, Map<String, dynamic> params) {
  final String requested = params['sourceArtifact']?.toString() ?? 'auto';
  if (requested != 'auto' && _datasetHasArtifact(dataset, requested)) {
    return requested;
  }
  if (dataset.segmentedTimeSeries != null) {
    return 'segmentedTimeSeries';
  }
  if (dataset.timeFrequency != null) {
    return 'timeFrequency';
  }
  if (dataset.spectrum != null) {
    return 'spectrum';
  }
  if (dataset.matrixTransformation != null) {
    return 'matrixTransformation';
  }
  return 'timeSeries';
}

bool _datasetHasArtifact(Dataset dataset, String artifact) {
  switch (artifact) {
    case 'segmentedTimeSeries':
      return dataset.segmentedTimeSeries != null;
    case 'spectrum':
      return dataset.spectrum != null;
    case 'timeFrequency':
      return dataset.timeFrequency != null;
    case 'matrixTransformation':
      return dataset.matrixTransformation != null;
    case 'timeSeries':
      return dataset.timeSeries != null;
  }
  return false;
}

void _averageTimeSeries(Dataset dataset, Map<String, dynamic> params) {
  final TimeSeriesData? timeSeries = dataset.timeSeries;
  if (timeSeries == null || timeSeries.channels.isEmpty) {
    return;
  }
  final bool channels = params['averageChannels'] == true;
  final bool timePoints = params['averageTimePoints'] == true;
  final List<List<double>> inputChannels = timeSeries.channels;
  final int sampleCount = _minLength(inputChannels);
  if (sampleCount == 0) {
    return;
  }

  if (timePoints) {
    final Map<String, String> row = <String, String>{'dataset': dataset.label};
    final List<String> columns = <String>['dataset'];
    if (channels) {
      columns.add('mean');
      row['mean'] = _mean(_flatten(inputChannels, sampleCount)).toStringAsFixed(6);
    } else {
      for (int channel = 0; channel < inputChannels.length; channel++) {
        final String label = _channelLabel(timeSeries.channelLabels, channel);
        final String column = '${label}_mean';
        columns.add(column);
        row[column] = _mean(inputChannels[channel].take(sampleCount)).toStringAsFixed(6);
      }
    }
    dataset.featureTable = FeatureTableData(
      columns: columns,
      rows: <Map<String, String>>[row],
      source: timeSeries.source,
    );
    return;
  }

  if (!channels) {
    dataset.timeSeries = TimeSeriesData.fromJson(timeSeries.toJson());
    return;
  }

  dataset.timeSeries = timeSeries.copyWith(
    samples: const <double>[],
    channelSamples: <List<double>>[_meanByIndex(inputChannels, sampleCount)],
    channelLabels: const <String>['Average'],
    source: _sourceLabel(timeSeries.source, 'averaged channels'),
  );
}

void _averageSegmentedTimeSeries(Dataset dataset, Map<String, dynamic> params) {
  final SegmentedTimeSeriesData? segmented = dataset.segmentedTimeSeries;
  if (segmented == null || segmented.segments.isEmpty) {
    return;
  }
  final bool channels = params['averageChannels'] == true;
  final bool timePoints = params['averageTimePoints'] == true;
  final bool segments = params['averageSegments'] == true;

  final List<SignalSegmentData> materialized =
      segmented.materializedSegments();
  final List<SignalSegmentData> channelCollapsed = channels
      ? materialized.map(_collapseSegmentChannels).toList(growable: false)
      : materialized;

  if (timePoints) {
    final List<Map<String, String>> rows = <Map<String, String>>[];
    final List<String> columns = channels
        ? const <String>['dataset', 'label', 'mean']
        : const <String>['dataset', 'label', 'channel', 'mean'];
    final Iterable<List<SignalSegmentData>> groups = segments
        ? _segmentsByLabel(channelCollapsed).values
        : channelCollapsed.map((SignalSegmentData segment) => <SignalSegmentData>[segment]);
      for (final List<SignalSegmentData> group in groups) {
        final List<SignalSegmentData> averagedGroup = segments
          ? <SignalSegmentData>[_averageSegmentGroup(group, segmented.sampleRate)]
          : group;
      for (final SignalSegmentData segment in averagedGroup) {
        for (int channel = 0; channel < segment.channelSamples.length; channel++) {
          final String label = _channelLabel(segmented.channelLabels, channel);
          final Map<String, String> row = <String, String>{
            'dataset': dataset.label,
            'label': segment.label,
            if (!channels) 'channel': label,
            'mean': _mean(segment.channelSamples[channel]).toStringAsFixed(6),
          };
          rows.add(row);
        }
      }
    }
    dataset.featureTable = FeatureTableData(
      columns: columns,
      rows: rows,
      source: segmented.source,
    );
    return;
  }

  final List<SignalSegmentData> outputSegments = segments
      ? _segmentsByLabel(channelCollapsed)
          .values
          .map(
            (List<SignalSegmentData> group) =>
                _averageSegmentGroup(group, segmented.sampleRate),
          )
          .toList(growable: false)
      : channelCollapsed;
  dataset.segmentedTimeSeries = segmented.copyWith(
    segments: outputSegments,
    channelLabels: channels ? const <String>['Average'] : segmented.channelLabels,
    source: _sourceLabel(segmented.source, 'averaged'),
  );
}

void _averageSpectrum(Dataset dataset, Map<String, dynamic> params) {
  final FrequencySpectrumData? spectrum = dataset.spectrum;
  if (spectrum == null || spectrum.power.isEmpty) {
    return;
  }
  if (params['averageFrequencies'] != true) {
    dataset.spectrum = FrequencySpectrumData.fromJson(spectrum.toJson());
    return;
  }
  dataset.featureTable = FeatureTableData(
    columns: const <String>['dataset', 'mean_power', 'frequency_bin_count'],
    rows: <Map<String, String>>[
      <String, String>{
        'dataset': dataset.label,
        'mean_power': _mean(spectrum.power).toStringAsFixed(6),
        'frequency_bin_count': spectrum.power.length.toString(),
      },
    ],
    source: spectrum.source,
  );
}

void _averageTimeFrequency(Dataset dataset, Map<String, dynamic> params) {
  final TimeFrequencyData? timeFrequency = dataset.timeFrequency;
  if (timeFrequency == null || timeFrequency.powerMatrix.isEmpty) {
    return;
  }
  final bool timePoints = params['averageTimePoints'] == true;
  final bool frequencies = params['averageFrequencies'] == true;
  if (timePoints && frequencies) {
    dataset.featureTable = FeatureTableData(
      columns: const <String>['dataset', 'mean_power'],
      rows: <Map<String, String>>[
        <String, String>{
          'dataset': dataset.label,
          'mean_power': _mean(timeFrequency.powerMatrix.expand((List<double> row) => row))
              .toStringAsFixed(6),
        },
      ],
      source: timeFrequency.source,
    );
    return;
  }
  if (timePoints) {
    final int frequencyCount = _minLength(timeFrequency.powerMatrix);
    dataset.spectrum = FrequencySpectrumData(
      frequencies: timeFrequency.frequencies.take(frequencyCount).toList(growable: false),
      power: List<double>.generate(frequencyCount, (int frequencyIndex) {
        double total = 0;
        for (final List<double> row in timeFrequency.powerMatrix) {
          total += row[frequencyIndex];
        }
        return total / timeFrequency.powerMatrix.length;
      }, growable: false),
      source: _sourceLabel(timeFrequency.source, 'averaged time'),
    );
    return;
  }
  if (frequencies) {
    final List<double> samples = timeFrequency.powerMatrix
        .map((List<double> row) => _mean(row))
        .toList(growable: false);
    dataset.timeSeries = TimeSeriesData(
      channelSamples: <List<double>>[samples],
      sampleRate: _sampleRateFromTimes(timeFrequency.times),
      channelLabels: const <String>['Mean power'],
      source: _sourceLabel(timeFrequency.source, 'averaged frequencies'),
    );
  }
}

void _averageMatrix(Dataset dataset, Map<String, dynamic> params) {
  final MatrixTransformationData? matrixData = dataset.matrixTransformation;
  if (matrixData == null || matrixData.matrix.isEmpty) {
    return;
  }
  final bool rows = params['averageMatrixRows'] == true;
  final bool columns = params['averageMatrixColumns'] == true;
  if (!rows && !columns) {
    dataset.matrixTransformation = MatrixTransformationData.fromJson(matrixData.toJson());
    return;
  }
  if (rows && columns) {
    dataset.featureTable = FeatureTableData(
      columns: const <String>['dataset', 'mean'],
      rows: <Map<String, String>>[
        <String, String>{
          'dataset': dataset.label,
          'mean': _mean(matrixData.matrix.expand((List<double> row) => row))
              .toStringAsFixed(6),
        },
      ],
      source: matrixData.source,
    );
    return;
  }
  if (rows) {
    final int columnCount = _minLength(matrixData.matrix);
    dataset.matrixTransformation = MatrixTransformationData(
      matrix: <List<double>>[
        List<double>.generate(columnCount, (int column) {
          double total = 0;
          for (final List<double> row in matrixData.matrix) {
            total += row[column];
          }
          return total / matrixData.matrix.length;
        }, growable: false),
      ],
      componentLabels: const <String>['Average row'],
      source: _sourceLabel(matrixData.source, 'averaged rows'),
    );
    return;
  }
  dataset.matrixTransformation = MatrixTransformationData(
    matrix: matrixData.matrix
        .map((List<double> row) => <double>[_mean(row)])
        .toList(growable: false),
    componentLabels: matrixData.componentLabels,
    source: _sourceLabel(matrixData.source, 'averaged columns'),
  );
}

SignalSegmentData _collapseSegmentChannels(SignalSegmentData segment) {
  final int sampleCount = _minLength(segment.channelSamples);
  if (sampleCount == 0) {
    return segment;
  }
  return segment.copyWith(
    channelSamples: <List<double>>[_meanByIndex(segment.channelSamples, sampleCount)],
  );
}

Map<String, List<SignalSegmentData>> _segmentsByLabel(
  List<SignalSegmentData> segments,
) {
  final Map<String, List<SignalSegmentData>> grouped =
      <String, List<SignalSegmentData>>{};
  for (final SignalSegmentData segment in segments) {
    grouped.putIfAbsent(segment.label, () => <SignalSegmentData>[]).add(segment);
  }
  return grouped;
}

SignalSegmentData _averageSegmentGroup(
  List<SignalSegmentData> segments,
  double sampleRate,
) {
  final SignalSegmentData first = segments.first;
  final int channelCount = segments
      .map((SignalSegmentData segment) => segment.channelSamples.length)
      .fold<int>(first.channelSamples.length, (int a, int b) => a < b ? a : b);
  final int sampleCount = segments
      .map((SignalSegmentData segment) => _minLength(segment.channelSamples))
      .fold<int>(_minLength(first.channelSamples), (int a, int b) => a < b ? a : b);
  final List<List<double>> averagedChannels = List<List<double>>.generate(
    channelCount,
    (int channel) => List<double>.generate(sampleCount, (int sample) {
      double total = 0;
      for (final SignalSegmentData segment in segments) {
        total += segment.channelSamples[channel][sample];
      }
      return total / segments.length;
    }, growable: false),
    growable: false,
  );
  return first.copyWith(
    channelSamples: averagedChannels,
    startSeconds: 0,
    stopSeconds: sampleRate > 0 ? sampleCount / sampleRate : first.stopSeconds,
    clearSourceWindow: true,
  );
}

List<double> _meanByIndex(List<List<double>> rows, int sampleCount) {
  return List<double>.generate(sampleCount, (int sample) {
    double total = 0;
    for (final List<double> row in rows) {
      total += row[sample];
    }
    return total / rows.length;
  }, growable: false);
}

Iterable<double> _flatten(List<List<double>> rows, int sampleCount) sync* {
  for (final List<double> row in rows) {
    for (int index = 0; index < sampleCount; index++) {
      yield row[index];
    }
  }
}

int _minLength(Iterable<List<double>> rows) {
  int? result;
  for (final List<double> row in rows) {
    result = result == null ? row.length : (row.length < result ? row.length : result);
  }
  return result ?? 0;
}

double _mean(Iterable<double> values) {
  double total = 0;
  int count = 0;
  for (final double value in values) {
    total += value;
    count++;
  }
  return count == 0 ? 0.0 : total / count;
}

String _channelLabel(List<String> labels, int index) {
  if (index >= 0 && index < labels.length && labels[index].trim().isNotEmpty) {
    return labels[index];
  }
  return 'channel_${index + 1}';
}

double _sampleRateFromTimes(List<double> times) {
  if (times.length < 2) {
    return 1.0;
  }
  final double dt = times[1] - times[0];
  if (dt <= 0) {
    return 1.0;
  }
  return 1.0 / dt;
}

String _sourceLabel(String source, String operation) {
  if (source.trim().isEmpty) {
    return operation;
  }
  return '$source ($operation)';
}
