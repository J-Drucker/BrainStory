import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class SpectralFeaturesNodeType extends NodeType {
  @override
  String get title => 'Spectral Features';

  @override
  NodeCategory get category => NodeCategory.transform;

  @override
  String get subcategory => 'Frequency Domain';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'powerFeatures': <String, dynamic>{
          'total_power': true,
          'delta_power': true,
          'theta_power': true,
          'alpha_power': true,
          'beta_power': true,
          'gamma_power': false,
        },
        'ratioFeatures': <String, dynamic>{
          'theta_alpha_ratio': true,
          'theta_beta_ratio': false,
          'alpha_beta_ratio': true,
          'delta_beta_ratio': false,
        },
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'psd', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'table', type: PortType.metadata),
      ];

  @override
  bool get supportsBackgroundRun => true;

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('powerFeatures', () => Map<String, dynamic>.from(defaultParams['powerFeatures'] as Map));
    params.putIfAbsent('ratioFeatures', () => Map<String, dynamic>.from(defaultParams['ratioFeatures'] as Map));

    final Map<String, dynamic> powerFeatures =
        Map<String, dynamic>.from(params['powerFeatures'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> ratioFeatures =
        Map<String, dynamic>.from(params['ratioFeatures'] as Map? ?? <String, dynamic>{});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Computes a feature table from PSD data. The output is stored as a table artifact so it can be exported to CSV easily later.',
        ),
        const SizedBox(height: 12),
        _FeatureGroupSection(
          title: 'Power',
          entries: const <MapEntry<String, String>>[
            MapEntry<String, String>('total_power', 'Total power'),
            MapEntry<String, String>('delta_power', 'Delta power (0-4 Hz)'),
            MapEntry<String, String>('theta_power', 'Theta power (4-8 Hz)'),
            MapEntry<String, String>('alpha_power', 'Alpha power (8-12 Hz)'),
            MapEntry<String, String>('beta_power', 'Beta power (12-40 Hz)'),
            MapEntry<String, String>('gamma_power', 'Gamma power (40+ Hz)'),
          ],
          selected: powerFeatures,
          onChanged: (String key, bool value) {
            setState(() {
              final Map<String, dynamic> next = Map<String, dynamic>.from(
                params['powerFeatures'] as Map? ?? <String, dynamic>{},
              );
              next[key] = value;
              params['powerFeatures'] = next;
            });
          },
        ),
        const SizedBox(height: 12),
        _FeatureGroupSection(
          title: 'Ratios',
          entries: const <MapEntry<String, String>>[
            MapEntry<String, String>('theta_alpha_ratio', 'Theta / Alpha'),
            MapEntry<String, String>('theta_beta_ratio', 'Theta / Beta'),
            MapEntry<String, String>('alpha_beta_ratio', 'Alpha / Beta'),
            MapEntry<String, String>('delta_beta_ratio', 'Delta / Beta'),
          ],
          selected: ratioFeatures,
          onChanged: (String key, bool value) {
            setState(() {
              final Map<String, dynamic> next = Map<String, dynamic>.from(
                params['ratioFeatures'] as Map? ?? <String, dynamic>{},
              );
              next[key] = value;
              params['ratioFeatures'] = next;
            });
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'More grouped feature families can be added later without changing the output format.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final FrequencySpectrumData? spectrum = dataset.spectrum;
    if (spectrum == null ||
        spectrum.frequencies.isEmpty ||
        spectrum.power.isEmpty) {
      dataset.featureTable = null;
      return;
    }

    final Map<String, String> row = <String, String>{
      'dataset': dataset.label,
    };
    final List<String> columns = <String>['dataset'];
    final Map<String, dynamic> powerFeatures =
        Map<String, dynamic>.from(params['powerFeatures'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> ratioFeatures =
        Map<String, dynamic>.from(params['ratioFeatures'] as Map? ?? <String, dynamic>{});

    final Map<String, double> bandPower = <String, double>{
      'delta': _bandPower(spectrum, minHz: 0.0, maxHz: 4.0),
      'theta': _bandPower(spectrum, minHz: 4.0, maxHz: 8.0),
      'alpha': _bandPower(spectrum, minHz: 8.0, maxHz: 12.0),
      'beta': _bandPower(spectrum, minHz: 12.0, maxHz: 40.0),
      'gamma': _bandPower(spectrum, minHz: 40.0, maxHz: double.infinity),
    };
    final double totalPower = _bandPower(
      spectrum,
      minHz: 0.0,
      maxHz: double.infinity,
    );

    void addFeature(String column, double value) {
      columns.add(column);
      row[column] = value.toStringAsFixed(6);
    }

    if (powerFeatures['total_power'] == true) {
      addFeature('total_power', totalPower);
    }
    if (powerFeatures['delta_power'] == true) {
      addFeature('delta_power', bandPower['delta'] ?? 0.0);
    }
    if (powerFeatures['theta_power'] == true) {
      addFeature('theta_power', bandPower['theta'] ?? 0.0);
    }
    if (powerFeatures['alpha_power'] == true) {
      addFeature('alpha_power', bandPower['alpha'] ?? 0.0);
    }
    if (powerFeatures['beta_power'] == true) {
      addFeature('beta_power', bandPower['beta'] ?? 0.0);
    }
    if (powerFeatures['gamma_power'] == true) {
      addFeature('gamma_power', bandPower['gamma'] ?? 0.0);
    }

    if (ratioFeatures['theta_alpha_ratio'] == true) {
      addFeature(
        'theta_alpha_ratio',
        _safeRatio(bandPower['theta'] ?? 0.0, bandPower['alpha'] ?? 0.0),
      );
    }
    if (ratioFeatures['theta_beta_ratio'] == true) {
      addFeature(
        'theta_beta_ratio',
        _safeRatio(bandPower['theta'] ?? 0.0, bandPower['beta'] ?? 0.0),
      );
    }
    if (ratioFeatures['alpha_beta_ratio'] == true) {
      addFeature(
        'alpha_beta_ratio',
        _safeRatio(bandPower['alpha'] ?? 0.0, bandPower['beta'] ?? 0.0),
      );
    }
    if (ratioFeatures['delta_beta_ratio'] == true) {
      addFeature(
        'delta_beta_ratio',
        _safeRatio(bandPower['delta'] ?? 0.0, bandPower['beta'] ?? 0.0),
      );
    }

    dataset.featureTable = FeatureTableData(
      columns: columns,
      rows: <Map<String, String>>[row],
      source: spectrum.source,
    );
    dataset.ram['spectralFeatures.params'] = <String, dynamic>{
      'powerFeatures': powerFeatures,
      'ratioFeatures': ratioFeatures,
    };
  }
}

class _FeatureGroupSection extends StatelessWidget {
  const _FeatureGroupSection({
    required this.title,
    required this.entries,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<MapEntry<String, String>> entries;
  final Map<String, dynamic> selected;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...entries.map((MapEntry<String, String> entry) {
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                value: selected[entry.key] == true,
                title: Text(entry.value),
                onChanged: (bool? value) => onChanged(entry.key, value ?? false),
              );
            }),
          ],
        ),
      ),
    );
  }
}

double _bandPower(
  FrequencySpectrumData spectrum, {
  required double minHz,
  required double maxHz,
}) {
  double total = 0.0;
  final int count = spectrum.frequencies.length < spectrum.power.length
      ? spectrum.frequencies.length
      : spectrum.power.length;
  for (int index = 0; index < count; index++) {
    final double frequency = spectrum.frequencies[index];
    if (frequency < minHz || frequency >= maxHz) {
      continue;
    }
    total += spectrum.power[index];
  }
  return total;
}

double _safeRatio(double numerator, double denominator) {
  if (denominator == 0.0) {
    return 0.0;
  }
  return numerator / denominator;
}
