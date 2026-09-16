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
    'featureColumns': '',
    'standardize': true,
    'maxIterations': 200,
    'tolerance': 0.0001,
    'regularization': 0.000001,
    'seed': 42,
  };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
    PortSpec(name: 'feature_table', type: PortType.metadata),
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
          'Fits a diagonal-covariance Gaussian mixture to rows in the incoming feature table. Cluster assignments and probabilities are appended to the table.',
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
        const SizedBox(height: 12),
        NodeParamTextField(
          params: params,
          paramKey: 'featureColumns',
          labelText: 'Feature columns (comma-separated; blank = all numeric)',
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
    final FeatureTableData? table = dataset.featureTable;
    if (table == null || table.rows.isEmpty) {
      throw StateError('Gaussian Mixture requires a non-empty feature table.');
    }
    final List<String> requestedColumns = _requestedColumns(
      params['featureColumns'],
    );
    final List<String> featureColumns = requestedColumns.isEmpty
        ? _automaticNumericColumns(table)
        : requestedColumns;
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
    if (rows.length < componentCount) {
      throw StateError(
        'Gaussian Mixture needs at least one row per component '
        '(${rows.length} rows, $componentCount components).',
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
    await context?.setProgress('Fitting $componentCount Gaussian components');
    final NativeGaussianMixtureResult? result =
        await computeGaussianMixtureBackground(
          rows,
          componentCount: componentCount,
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
    dataset.gaussianMixture = GaussianMixtureData(
      featureColumns: featureColumns,
      assignments: result.assignments,
      probabilities: result.probabilities,
      weights: result.weights,
      means: result.means,
      variances: result.variances,
      converged: result.converged,
      iterationCount: result.iterationCount,
      logLikelihood: result.logLikelihood,
      aic: result.aic,
      bic: result.bic,
      standardized: standardize,
      normalizationMean: result.normalizationMean,
      normalizationScale: result.normalizationScale,
      source: table.source,
    );
    await context?.setProgress(
      result.converged
          ? 'Converged in ${result.iterationCount} iterations'
          : 'Stopped after ${result.iterationCount} iterations',
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
