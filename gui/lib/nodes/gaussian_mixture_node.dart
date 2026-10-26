import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../platform/brainstory_engine.dart';
import 'node_type.dart';

class GaussianMixtureNodeType extends NodeType {
  @override
  String get title => 'Gaussian Mixture';

  @override
  NodeCategory get category => NodeCategory.machineLearning;

  @override
  String get subcategory => 'Clustering';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
    'componentCount': 3,
    'sweepComponents': false,
    'minimumComponentCount': 2,
    'maximumComponentCount': 6,
    'observationSource': 'raw_segments',
    'featureColumns': '',
    'assessmentVariables': 'label',
    'standardize': true,
    'maxIterations': 200,
    'tolerance': 0.0001,
    'regularization': 0.000001,
    'seed': 42,
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'segments', type: PortType.metadata),
    PortSpec(name: 'psd (optional)', type: PortType.signal),
    PortSpec(name: 'feature_table (optional)', type: PortType.metadata),
  ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
    PortSpec(name: 'table', type: PortType.metadata),
    PortSpec(name: 'gaussian_mixture', type: PortType.metadata),
  ];

  @override
  String get executionChunkingStrategy => 'background EM iterations';

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    for (final MapEntry<String, dynamic> entry in defaultParams.entries) {
      params.putIfAbsent(entry.key, () => entry.value);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Fits a diagonal-covariance Gaussian mixture to segments. Raw mode uses every supplied channel and time point exactly as received; dimensionality reduction belongs in upstream preprocessing.',
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'observationSource',
          labelText: 'Observations',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(
              value: 'raw_segments',
              label: 'Raw segment time series',
            ),
            NodeDropdownOption<String>(
              value: 'feature_table',
              label: 'Upstream feature table',
            ),
            NodeDropdownOption<String>(
              value: 'psd_segments',
              label: 'PSD segments',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _numberField(params, 'componentCount', 'Components'),
            _numberField(params, 'maxIterations', 'Maximum iterations'),
            _numberField(
              params,
              'tolerance',
              'Convergence tolerance',
              decimal: true,
            ),
            _numberField(
              params,
              'regularization',
              'Variance regularization',
              decimal: true,
            ),
            _numberField(params, 'seed', 'Random seed'),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: params['sweepComponents'] == true,
          title: const Text('Compare a range of component counts'),
          subtitle: const Text(
            'Fits and retains every k in the requested inclusive range.',
          ),
          onChanged: (bool? value) {
            setState(() => params['sweepComponents'] = value == true);
          },
        ),
        if (params['sweepComponents'] == true)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _numberField(
                params,
                'minimumComponentCount',
                'Minimum components',
              ),
              _numberField(
                params,
                'maximumComponentCount',
                'Maximum components',
              ),
            ],
          ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'featureColumns',
          labelText: 'Feature columns (comma-separated; blank = all numeric)',
        ),
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'assessmentVariables',
          labelText:
              'Assessment variables (comma-separated; never used for fitting)',
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: params['standardize'] != false,
          title: const Text('Standardize features before fitting'),
          subtitle: const Text(
            'Recommended when feature columns use different units or scales.',
          ),
          onChanged: (bool? value) {
            setState(() => params['standardize'] = value ?? true);
          },
        ),
      ],
    );
  }

  Widget _numberField(
    Map<String, dynamic> params,
    String key,
    String label, {
    bool decimal = false,
  }) {
    return SizedBox(
      width: 170,
      child: NodeParamTextField(
        params: params,
        paramKey: key,
        labelText: label,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        parser: (String value, dynamic previous) => decimal
            ? double.tryParse(value) ?? previous
            : int.tryParse(value) ?? previous,
      ),
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    await _run(dataset, params, null);
  }

  @override
  Future<void> runChunked(
    Dataset dataset,
    Map<String, dynamic> params,
    NodeExecutionContext context,
  ) => _run(dataset, params, context);

  Future<void> _run(
    Dataset dataset,
    Map<String, dynamic> params,
    NodeExecutionContext? context,
  ) async {
    final String observationSource =
        params['observationSource']?.toString() ?? 'raw_segments';
    final FeatureTableData table = switch (observationSource) {
      'feature_table' => _featureTableObservations(dataset),
      'psd_segments' => _psdSegmentObservations(dataset),
      _ => _rawSegmentObservations(dataset),
    };
    final List<String> assessmentVariables = _requestedColumns(
      params['assessmentVariables'],
    );
    final List<String> missingAssessmentVariables = assessmentVariables
        .where((String variable) => !table.columns.contains(variable))
        .toList(growable: false);
    if (missingAssessmentVariables.isNotEmpty) {
      throw StateError(
        'Assessment variables are not present in the observations: '
        '${missingAssessmentVariables.join(', ')}.',
      );
    }
    final List<String> requestedColumns = observationSource == 'feature_table'
        ? _requestedColumns(params['featureColumns'])
        : const <String>[];
    final List<String> featureColumns = observationSource != 'feature_table'
        ? table.columns
              .where(
                (String column) =>
                    column.startsWith('value_') || column.startsWith('psd_'),
              )
              .toList(growable: false)
        : requestedColumns.isEmpty
        ? _automaticNumericColumns(table)
              .where((String column) => !assessmentVariables.contains(column))
              .toList(growable: false)
        : requestedColumns;
    final Set<String> assessmentFeatures = featureColumns
        .where(assessmentVariables.contains)
        .toSet();
    if (assessmentFeatures.isNotEmpty) {
      throw StateError(
        'Assessment variables cannot also be fitting features: '
        '${assessmentFeatures.join(', ')}.',
      );
    }
    if (featureColumns.isEmpty) {
      throw StateError('No numeric feature columns are available to cluster.');
    }
    final List<List<double>> rows = table.rows
        .map(
          (Map<String, String> row) => featureColumns
              .map((String column) {
                final double? value = double.tryParse(row[column] ?? '');
                if (value == null || !value.isFinite) {
                  throw StateError(
                    'Column "$column" contains missing or non-numeric values.',
                  );
                }
                return value;
              })
              .toList(growable: false),
        )
        .toList(growable: false);
    final int componentCount =
        ((params['componentCount'] as num?)?.toInt() ?? 3).clamp(1, 32);
    final bool sweepComponents = params['sweepComponents'] == true;
    final int minimumComponentCount = sweepComponents
        ? ((params['minimumComponentCount'] as num?)?.toInt() ?? 2).clamp(1, 32)
        : componentCount;
    final int maximumComponentCount = sweepComponents
        ? ((params['maximumComponentCount'] as num?)?.toInt() ?? 6).clamp(1, 32)
        : componentCount;
    if (minimumComponentCount > maximumComponentCount) {
      throw ArgumentError(
        'Minimum components cannot exceed maximum components.',
      );
    }
    final List<int> componentCounts = <int>{
      for (
        int count = minimumComponentCount;
        count <= maximumComponentCount;
        count++
      )
        count,
      componentCount,
    }.toList()..sort();
    if (rows.length < componentCounts.last) {
      throw StateError(
        'Gaussian Mixture needs at least one row per component '
        '(${rows.length} rows, ${componentCounts.last} components).',
      );
    }
    final int maxIterations =
        ((params['maxIterations'] as num?)?.toInt() ?? 200).clamp(1, 10000);
    final double tolerance =
        (params['tolerance'] as num?)?.toDouble() ?? 0.0001;
    final double regularization =
        (params['regularization'] as num?)?.toDouble() ?? 0.000001;
    if (!tolerance.isFinite || tolerance <= 0) {
      throw ArgumentError('Convergence tolerance must be above zero.');
    }
    if (!regularization.isFinite || regularization <= 0) {
      throw ArgumentError('Variance regularization must be above zero.');
    }
    final bool standardize = params['standardize'] != false;
    final int seed = (params['seed'] as num?)?.toInt() ?? 42;
    final Map<int, NativeGaussianMixtureResult> results =
        <int, NativeGaussianMixtureResult>{};
    for (int index = 0; index < componentCounts.length; index++) {
      final int count = componentCounts[index];
      await context?.setProgress(
        componentCounts.length == 1
            ? 'Fitting $count Gaussian components'
            : 'Fitting k=$count (${index + 1} of ${componentCounts.length})',
      );
      final NativeGaussianMixtureResult? result =
          await computeGaussianMixtureBackground(
            rows,
            componentCount: count,
            tolerance: tolerance,
            maxIterations: maxIterations,
            regularization: regularization,
            standardize: standardize,
            seed: seed,
          );
      if (result == null) {
        throw UnsupportedError(
          'The BrainStory Gaussian mixture engine is unavailable.',
        );
      }
      results[count] = result;
    }
    final NativeGaussianMixtureResult result = results[componentCount]!;

    final List<String> outputColumns =
        table.columns
            .where((String column) => !column.startsWith('gmm_'))
            .toList(growable: true)
          ..addAll(<String>[
            'gmm_cluster',
            'gmm_probability',
            for (int component = 0; component < componentCount; component++)
              'gmm_p${component + 1}',
          ]);
    final List<Map<String, String>> outputRows =
        List<Map<String, String>>.generate(table.rows.length, (int rowIndex) {
          final Map<String, String> row = Map<String, String>.from(
            table.rows[rowIndex],
          )..removeWhere((String key, String value) => key.startsWith('gmm_'));
          final int assignment = result.assignments[rowIndex];
          final List<double> probabilities = result.probabilities[rowIndex];
          row['gmm_cluster'] = (assignment + 1).toString();
          row['gmm_probability'] = probabilities[assignment].toStringAsFixed(8);
          for (int component = 0; component < componentCount; component++) {
            row['gmm_p${component + 1}'] = probabilities[component]
                .toStringAsFixed(8);
          }
          return row;
        }, growable: false);
    dataset.featureTable = FeatureTableData(
      columns: outputColumns,
      rows: outputRows,
      source: table.source,
    );
    final Map<String, List<String>> assessmentValues = <String, List<String>>{
      for (final String variable in assessmentVariables)
        variable: table.rows
            .map((Map<String, String> row) => row[variable] ?? '')
            .toList(growable: false),
    };
    GaussianMixtureData buildModel(
      NativeGaussianMixtureResult fit, {
      List<GaussianMixtureData> candidates = const <GaussianMixtureData>[],
    }) => GaussianMixtureData(
      featureColumns: featureColumns,
      assignments: fit.assignments,
      probabilities: fit.probabilities,
      weights: fit.weights,
      means: fit.means,
      variances: fit.variances,
      converged: fit.converged,
      iterationCount: fit.iterationCount,
      logLikelihood: fit.logLikelihood,
      aic: fit.aic,
      bic: fit.bic,
      standardized: standardize,
      normalizationMean: fit.normalizationMean,
      normalizationScale: fit.normalizationScale,
      source: table.source,
      assessmentVariables: assessmentVariables,
      assessmentValues: assessmentValues,
      candidateModels: candidates,
      projection: GaussianMixtureProjectionData(
        observations: fit.projection.observations,
        componentMeans: fit.projection.componentMeans,
        componentCovariances: fit.projection.componentCovariances,
        explainedVarianceRatios: fit.projection.explainedVarianceRatios,
      ),
    );
    dataset.gaussianMixture = buildModel(
      result,
      candidates: <GaussianMixtureData>[
        for (final MapEntry<int, NativeGaussianMixtureResult> entry
            in results.entries)
          if (entry.key != componentCount) buildModel(entry.value),
      ],
    );
    await context?.setProgress(
      result.converged
          ? 'Converged in ${result.iterationCount} iterations'
          : 'Stopped after ${result.iterationCount} iterations',
    );
  }

  FeatureTableData _featureTableObservations(Dataset dataset) {
    final FeatureTableData? table = dataset.featureTable;
    if (table == null || table.rows.isEmpty) {
      throw StateError(
        'Gaussian Mixture feature-table mode requires a non-empty upstream feature table.',
      );
    }
    return table;
  }

  FeatureTableData _rawSegmentObservations(Dataset dataset) {
    final SegmentedTimeSeriesData? segmented = dataset.segmentedTimeSeries;
    if (segmented == null || segmented.segments.isEmpty) {
      throw StateError('Gaussian Mixture requires segmented time-series data.');
    }
    final List<SignalSegmentData> segments = segmented.materializedSegments();
    final SignalSegmentData expectedSegment = segments.first;
    final int expectedChannelCount = expectedSegment.channelSamples.length;
    final int expectedSampleCount = expectedSegment.channelSamples.isEmpty
        ? 0
        : expectedSegment.channelSamples.first.length;
    for (int index = 0; index < segments.length; index++) {
      final SignalSegmentData segment = segments[index];
      final int channelCount = segment.channelSamples.length;
      final int sampleCount = segment.channelSamples.isEmpty
          ? 0
          : segment.channelSamples.first.length;
      if (channelCount != expectedChannelCount ||
          sampleCount != expectedSampleCount) {
        final String label = segment.label.trim().isEmpty
            ? 'unlabeled'
            : segment.label.trim();
        throw StateError(
          'Raw GMM epoch ${index + 1} ("$label") is '
          '$channelCount channel(s) × $sampleCount sample(s); expected '
          '$expectedChannelCount × $expectedSampleCount. Unequal numbers of '
          'epochs per condition are allowed, but every epoch must have the '
          'same shape. Pool, select channels, or resample upstream before fitting.',
        );
      }
    }
    final List<List<double>> flattened = segments
        .map((SignalSegmentData segment) {
          if (segment.channelSamples.isEmpty) {
            throw StateError('A segment has no materialized signal samples.');
          }
          final int sampleCount = segment.channelSamples.first.length;
          if (sampleCount == 0 ||
              segment.channelSamples.any(
                (List<double> channel) => channel.length != sampleCount,
              )) {
            throw StateError(
              'Every segment channel must contain the same non-zero number of samples.',
            );
          }
          return segment.channelSamples
              .expand((List<double> channel) => channel)
              .toList(growable: false);
        })
        .toList(growable: false);
    final int width = flattened.first.length;
    if (flattened.any((List<double> row) => row.length != width)) {
      throw StateError(
        'Raw GMM segments must have identical channel and sample dimensions. '
        'Unequal numbers of epochs per condition are allowed. Pool, select '
        'channels, or resample upstream before fitting.',
      );
    }
    final List<String> valueColumns = List<String>.generate(
      width,
      (int index) => 'value_${index + 1}',
      growable: false,
    );
    return FeatureTableData(
      columns: <String>[
        'label',
        'kind',
        'start_seconds',
        'stop_seconds',
        ...valueColumns,
      ],
      rows: List<Map<String, String>>.generate(segments.length, (int index) {
        final SignalSegmentData segment = segments[index];
        return <String, String>{
          'label': segment.label,
          'kind': segment.kind,
          'start_seconds': segment.startSeconds.toString(),
          'stop_seconds': segment.stopSeconds.toString(),
          for (int valueIndex = 0; valueIndex < width; valueIndex++)
            valueColumns[valueIndex]: flattened[index][valueIndex].toString(),
        };
      }, growable: false),
      source: '${segmented.source} -> raw segments',
    );
  }

  FeatureTableData _psdSegmentObservations(Dataset dataset) {
    final FrequencySpectrumData? spectrum = dataset.spectrum;
    if (spectrum == null || spectrum.frequencies.isEmpty) {
      throw StateError('Gaussian Mixture requires upstream PSD data.');
    }
    final int binCount = spectrum.frequencies.length;
    final List<List<List<double>>> channelSegments = spectrum
        .channelSegmentPowers
        .where(
          (List<List<double>> channel) =>
              channel.isNotEmpty &&
              channel.every((List<double> values) => values.length == binCount),
        )
        .toList(growable: false);
    final int segmentCount = channelSegments.isNotEmpty
        ? channelSegments
              .map((List<List<double>> channel) => channel.length)
              .reduce(math.min)
        : spectrum.segmentPowers.length;
    if (segmentCount < 2) {
      throw StateError(
        'Gaussian Mixture needs segment-level PSD output with at least two segments. Configure PSD output as segments.',
      );
    }
    final List<List<double>> observations = List<List<double>>.generate(
      segmentCount,
      (int segment) => channelSegments.isNotEmpty
          ? <double>[
              for (final List<List<double>> channel in channelSegments)
                ...channel[segment],
            ]
          : spectrum.segmentPowers[segment],
      growable: false,
    );
    if (observations.any(
      (List<double> values) => values.length != observations.first.length,
    )) {
      throw StateError('PSD segments do not have matching dimensions.');
    }
    final List<String> valueColumns = <String>[
      if (channelSegments.isNotEmpty)
        for (int channel = 0; channel < channelSegments.length; channel++)
          for (int bin = 0; bin < binCount; bin++)
            'psd_${channel < spectrum.channelLabels.length ? spectrum.channelLabels[channel] : 'ch${channel + 1}'}_${spectrum.frequencies[bin].toStringAsFixed(3)}hz'
      else
        for (int bin = 0; bin < binCount; bin++)
          'psd_${spectrum.frequencies[bin].toStringAsFixed(3)}hz',
    ];
    final List<SignalSegmentData> sourceSegments =
        dataset.segmentedTimeSeries?.materializedSegments() ??
        const <SignalSegmentData>[];
    return FeatureTableData(
      columns: <String>[
        'label',
        'kind',
        'start_seconds',
        'stop_seconds',
        ...valueColumns,
      ],
      rows: List<Map<String, String>>.generate(segmentCount, (int index) {
        final SignalSegmentData? segment = index < sourceSegments.length
            ? sourceSegments[index]
            : null;
        return <String, String>{
          'label': segment?.label ?? '',
          'kind': segment?.kind ?? '',
          'start_seconds': segment?.startSeconds.toString() ?? '',
          'stop_seconds': segment?.stopSeconds.toString() ?? '',
          for (int value = 0; value < valueColumns.length; value++)
            valueColumns[value]: observations[index][value].toString(),
        };
      }, growable: false),
      source: spectrum.source,
    );
  }

  List<String> _requestedColumns(dynamic value) {
    if (value is List) {
      return value
          .map((dynamic item) => item.toString().trim())
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return value
        .toString()
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _automaticNumericColumns(FeatureTableData table) {
    return table.columns
        .where((String column) {
          if (column.startsWith('gmm_')) return false;
          return table.rows.every((Map<String, String> row) {
            final double? value = double.tryParse(row[column] ?? '');
            return value != null && value.isFinite;
          });
        })
        .toList(growable: false);
  }
}
