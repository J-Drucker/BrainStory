import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class ChannelExclusionNodeType extends NodeType {
  @override
  String get title => 'Channel Exclusion';

  @override
  NodeCategory get category => NodeCategory.import;

  @override
  String get subcategory => 'Quality Control';

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'selectedDatasetIds': <String>[],
        'selectedChannels': <String>[],
        'action': 'mark_bad',
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    params.putIfAbsent('selectedChannels', () => <String>[]);
    params.putIfAbsent('action', () => 'mark_bad');

    final List<dynamic> selectedDatasetIds =
        params['selectedDatasetIds'] as List<dynamic>? ?? const <dynamic>[];
    final TimeSeriesData? visibleTimeSeries = datasets.values
        .where((Dataset dataset) =>
            selectedDatasetIds.isEmpty || selectedDatasetIds.contains(dataset.id))
        .map((Dataset dataset) => dataset.timeSeries)
        .whereType<TimeSeriesData>()
        .cast<TimeSeriesData?>()
        .firstWhere((TimeSeriesData? value) => value != null, orElse: () => null);
    final List<String> availableChannels = visibleTimeSeries?.channelLabels.isNotEmpty == true
        ? visibleTimeSeries!.channelLabels
        : List<String>.generate(
            visibleTimeSeries?.channelCount ?? 0,
            (int index) => 'Ch ${index + 1}',
            growable: false,
          );
    final Set<String> selectedChannels = Set<String>.from(
      params['selectedChannels'] as List<dynamic>? ?? const <dynamic>[],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Select channels to treat as bad. Remove drops them from the signal, interpolate will require channel locations later, and mark bad creates a recording-long artifact marker called "bad channel".',
        ),
        const SizedBox(height: 12),
        NodeParamDropdownField<String>(
          params: params,
          paramKey: 'action',
          labelText: 'Action',
          options: const <NodeDropdownOption<String>>[
            NodeDropdownOption<String>(value: 'remove', label: 'Remove'),
            NodeDropdownOption<String>(
              value: 'interpolate',
              label: 'Interpolate',
            ),
            NodeDropdownOption<String>(value: 'mark_bad', label: 'Mark bad'),
          ],
          onChanged: (_) {
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        if (availableChannels.isEmpty)
          const Text(
            'No channel labels are available yet for the currently selected datasets.',
            style: TextStyle(color: Colors.black54),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableChannels.map((String label) {
              final bool selected = selectedChannels.contains(label);
              return FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: (bool next) {
                  setState(() {
                    final Set<String> updated = Set<String>.from(selectedChannels);
                    if (next) {
                      updated.add(label);
                    } else {
                      updated.remove(label);
                    }
                    params['selectedChannels'] = updated.toList(growable: false);
                  });
                },
              );
            }).toList(growable: false),
          ),
        if ((params['action']?.toString() ?? 'mark_bad') == 'interpolate') ...<Widget>[
          const SizedBox(height: 10),
          const Text(
            'Interpolation will stay disabled until BrainStory has channel-location support for this dataset.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null || timeSeries.channels.isEmpty) {
      return;
    }

    final List<String> channelLabels = timeSeries.channelLabels.isNotEmpty
        ? timeSeries.channelLabels
        : List<String>.generate(
            timeSeries.channelCount,
            (int index) => 'Ch ${index + 1}',
            growable: false,
          );
    final Set<String> selectedChannels = Set<String>.from(
      params['selectedChannels'] as List<dynamic>? ?? const <dynamic>[],
    );
    final List<int> selectedIndices = <int>[];
    for (int index = 0; index < channelLabels.length; index++) {
      if (selectedChannels.contains(channelLabels[index])) {
        selectedIndices.add(index);
      }
    }

    final String action = params['action']?.toString() ?? 'mark_bad';
    dataset.ram['channelExclusion.params'] = <String, dynamic>{
      'selectedChannels': selectedChannels.toList(growable: false),
      'action': action,
    };

    if (selectedIndices.isEmpty) {
      return;
    }

    if (action == 'remove') {
      final Set<int> removed = selectedIndices.toSet();
      dataset.timeSeries = timeSeries.copyWith(
        channelSamples: timeSeries.channels
            .asMap()
            .entries
            .where((MapEntry<int, List<double>> entry) => !removed.contains(entry.key))
            .map((MapEntry<int, List<double>> entry) => entry.value)
            .toList(growable: false),
        channelLabels: channelLabels
            .asMap()
            .entries
            .where((MapEntry<int, String> entry) => !removed.contains(entry.key))
            .map((MapEntry<int, String> entry) => entry.value)
            .toList(growable: false),
        source:
            '${timeSeries.source.isEmpty ? 'Channel exclusion' : '${timeSeries.source} -> Channel exclusion'} (removed)',
      );
      return;
    }

    if (action == 'interpolate') {
      dataset.ram['channelExclusion.lastWarning'] =
          'Interpolation requires channel locations and is not available yet.';
      return;
    }

    final int fullDurationMicros = ((timeSeries.sampleCount / timeSeries.sampleRate) * 1000000.0)
        .round();
    final List<int> channelMask = List<int>.filled(channelLabels.length, 0, growable: false);
    for (final int index in selectedIndices) {
      if (index >= 0 && index < channelMask.length) {
        channelMask[index] = 1;
      }
    }
    dataset.timeSeries = timeSeries.copyWith(
      markers: <TimeMarker>[
        ...timeSeries.markers,
        TimeMarker(
          onsetMicros: 0,
          durationMicros: fullDurationMicros,
          label: 'bad channel',
          markerType: MarkerType.artifact,
          channelMask: channelMask,
        ),
      ],
      source:
          '${timeSeries.source.isEmpty ? 'Channel exclusion' : '${timeSeries.source} -> Channel exclusion'} (marked bad)',
    );
  }
}
