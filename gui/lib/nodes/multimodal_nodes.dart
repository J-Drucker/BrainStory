import 'package:flutter/material.dart';

import '../model/dataset.dart';
import 'node_type.dart';

abstract class _MultimodalPlaceholderNodeType extends NodeType {
  String get placeholderDescription;

  @override
  NodeCategory get category => NodeCategory.multimodal;

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(placeholderDescription),
        const SizedBox(height: 12),
        const Text(
          'Placeholder only for now. This node establishes the workflow location and parameter surface without implementing the backend yet.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}

class DetectPeaksNodeType extends _MultimodalPlaceholderNodeType {
  @override
  String get title => 'Detect Peaks';

  @override
  String get subcategory => 'Electrocardiography (EKG)';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'signalSource': 'ekg',
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'markers', type: PortType.markers),
      ];

  @override
  String get placeholderDescription =>
      'Placeholder for EKG peak detection. This will eventually mark cardiac peaks so downstream IBI and HRV nodes can operate on them.';

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    dataset.ram['multimodal.ekg.detectPeaks.params'] = <String, dynamic>{
      'signalSource': params['signalSource'] ?? 'ekg',
      'implemented': false,
    };
  }
}

class InterbeatIntervalNodeType extends _MultimodalPlaceholderNodeType {
  @override
  String get title => 'Interbeat-interval (IBI)';

  @override
  String get subcategory => 'Electrocardiography (EKG)';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'units': 'milliseconds',
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'markers', type: PortType.markers),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'table', type: PortType.metadata),
      ];

  @override
  String get placeholderDescription =>
      'Placeholder for converting detected EKG peaks into an interbeat-interval series.';

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    dataset.ram['multimodal.ekg.ibi.params'] = <String, dynamic>{
      'units': params['units'] ?? 'milliseconds',
      'implemented': false,
    };
  }
}

class HeartRateVariabilityNodeType extends _MultimodalPlaceholderNodeType {
  @override
  String get title => 'Heart rate variability (HRV)';

  @override
  String get subcategory => 'Electrocardiography (EKG)';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'domain': 'time_domain',
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'table', type: PortType.metadata),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'table', type: PortType.metadata),
      ];

  @override
  String get placeholderDescription =>
      'Placeholder for heart-rate-variability features derived from interbeat intervals.';

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    dataset.ram['multimodal.ekg.hrv.params'] = <String, dynamic>{
      'domain': params['domain'] ?? 'time_domain',
      'implemented': false,
    };
  }
}
