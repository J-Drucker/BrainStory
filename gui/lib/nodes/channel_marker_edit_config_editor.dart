import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'add_remove_markers_node.dart';
import 'edit_channels_node.dart';

enum ChannelMarkerEditTab { channels, markers }

class ChannelMarkerEditConfigEditor extends StatelessWidget {
  const ChannelMarkerEditConfigEditor({
    super.key,
    required this.dataset,
    required this.channelConfig,
    required this.markers,
    required this.onChannelConfigChanged,
    required this.onMarkersChanged,
    this.initialTab = ChannelMarkerEditTab.channels,
    this.initialVisibleChannelIndices,
    this.channelHeaderAction,
  });

  final Dataset dataset;
  final Map<String, dynamic> channelConfig;
  final List<TimeMarker> markers;
  final ValueChanged<Map<String, dynamic>> onChannelConfigChanged;
  final ValueChanged<List<TimeMarker>> onMarkersChanged;
  final ChannelMarkerEditTab initialTab;
  final List<int>? initialVisibleChannelIndices;
  final Widget? channelHeaderAction;

  @override
  Widget build(BuildContext context) {
    final TimeSeriesData? series = dataset.timeSeries;
    final List<String> labels = series == null
        ? const <String>[]
        : series.channelLabels.length == series.channelCount
        ? series.channelLabels
        : List<String>.generate(
            series.channelCount,
            (int index) => index < series.channelLabels.length
                ? series.channelLabels[index]
                : 'Ch ${index + 1}',
          );
    return DefaultTabController(
      initialIndex: initialTab.index,
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const TabBar(
            tabs: <Tab>[
              Tab(text: 'Channels'),
              Tab(text: 'Markers'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                if (series == null)
                  const Center(child: Text('No time-domain channels.'))
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (channelHeaderAction != null) ...<Widget>[
                        Align(
                          alignment: Alignment.centerRight,
                          child: channelHeaderAction!,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        child: ChannelEditConfigEditor(
                          channelLabels: labels,
                          config: channelConfig,
                          initialVisibleChannelIndices:
                              initialVisibleChannelIndices,
                          currentCoordinateCount:
                              series.channelCoordinates.length,
                          onChanged: onChannelConfigChanged,
                        ),
                      ),
                    ],
                  ),
                MarkerLabelEditConfigEditor(
                  markers: markers,
                  onChanged: onMarkersChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MarkerLabelEditConfigEditor extends StatefulWidget {
  const MarkerLabelEditConfigEditor({
    super.key,
    required this.markers,
    required this.onChanged,
  });

  final List<TimeMarker> markers;
  final ValueChanged<List<TimeMarker>> onChanged;

  @override
  State<MarkerLabelEditConfigEditor> createState() =>
      _MarkerLabelEditConfigEditorState();
}

class _MarkerLabelEditConfigEditorState
    extends State<MarkerLabelEditConfigEditor> {
  late List<TimeMarker> _baseMarkers;
  late List<String> _labels;
  final Map<String, String> _renames = <String, String>{};
  final Set<String> _deletedLabels = <String>{};
  final List<_BoundaryCombinationDraft> _boundaryDrafts =
      <_BoundaryCombinationDraft>[];
  int _nextBoundaryDraftId = 1;

  @override
  void initState() {
    super.initState();
    _reset(widget.markers);
  }

  void _reset(List<TimeMarker> markers) {
    _baseMarkers = List<TimeMarker>.from(markers, growable: false);
    _labels =
        markers
            .map((TimeMarker marker) => marker.label)
            .where((String label) => label.trim().isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    _renames
      ..clear()
      ..addEntries(
        _labels.map((String label) => MapEntry<String, String>(label, '')),
      );
    _deletedLabels.clear();
    _boundaryDrafts
      ..clear()
      ..add(_BoundaryCombinationDraft(id: _nextBoundaryDraftId++));
  }

  Map<String, String> get _effectiveRenames => <String, String>{
    for (final MapEntry<String, String> entry in _renames.entries)
      if (!_deletedLabels.contains(entry.key) && entry.value.trim().isNotEmpty)
        entry.key: entry.value.trim(),
  };

  String? _validationMessage(_BoundaryCombinationDraft draft) {
    if (draft.startLabel == null && draft.stopLabel == null) {
      return null;
    }
    if (draft.startLabel == null || draft.stopLabel == null) {
      return 'Choose both a start marker and a stop marker.';
    }
    if (_deletedLabels.contains(draft.startLabel) ||
        _deletedLabels.contains(draft.stopLabel)) {
      return 'A boundary label cannot also be deleted.';
    }
    if (draft.blockLabel.trim().isEmpty) {
      return 'Enter a block label.';
    }
    final Map<String, String> renamed = _effectiveRenames;
    if ((renamed[draft.startLabel] ?? draft.startLabel) ==
        (renamed[draft.stopLabel] ?? draft.stopLabel)) {
      return 'Start and stop labels must differ.';
    }
    return null;
  }

  MarkerBoundaryCombinationResult? _preview(_BoundaryCombinationDraft draft) {
    if (_validationMessage(draft) != null ||
        draft.startLabel == null ||
        draft.stopLabel == null) {
      return null;
    }
    return AddRemoveMarkersNodeType.combineBoundaryMarkers(
      _renamedAndFilteredMarkers(),
      startLabel: _effectiveRenames[draft.startLabel] ?? draft.startLabel!,
      stopLabel: _effectiveRenames[draft.stopLabel] ?? draft.stopLabel!,
      blockLabel: draft.blockLabel,
      replaceBoundaries: false,
    );
  }

  List<TimeMarker> _renamedAndFilteredMarkers() {
    final Map<String, String> renamed = _effectiveRenames;
    return _baseMarkers
        .where((TimeMarker marker) => !_deletedLabels.contains(marker.label))
        .map((TimeMarker marker) {
          final String? replacement = renamed[marker.label];
          return replacement == null
              ? marker
              : marker.copyWith(label: replacement);
        })
        .toList(growable: false);
  }

  void _emit() {
    List<TimeMarker> result = _renamedAndFilteredMarkers();
    for (final _BoundaryCombinationDraft draft in _boundaryDrafts) {
      if (_validationMessage(draft) != null ||
          draft.startLabel == null ||
          draft.stopLabel == null) {
        continue;
      }
      result = AddRemoveMarkersNodeType.combineBoundaryMarkers(
        result,
        startLabel: _effectiveRenames[draft.startLabel] ?? draft.startLabel!,
        stopLabel: _effectiveRenames[draft.stopLabel] ?? draft.stopLabel!,
        blockLabel: draft.blockLabel,
        replaceBoundaries: draft.replaceBoundaries,
      ).markers;
    }
    widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_labels.isEmpty) {
      return const Center(child: Text('No markers.'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Rename or delete marker labels.'),
          const SizedBox(height: 12),
          for (int index = 0; index < _labels.length; index++) ...<Widget>[
            if (index > 0) const Divider(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _labels[index],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    enabled: !_deletedLabels.contains(_labels[index]),
                    initialValue: _renames[_labels[index]],
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'New label',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (String value) {
                      _renames[_labels[index]] = value;
                      _emit();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: _deletedLabels.contains(_labels[index]),
                  onChanged: (bool? value) {
                    setState(() {
                      value == true
                          ? _deletedLabels.add(_labels[index])
                          : _deletedLabels.remove(_labels[index]);
                    });
                    _emit();
                  },
                ),
                const Text('Delete'),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Combine boundaries into blocks',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('Each stop closes the earliest unmatched start.'),
          const SizedBox(height: 12),
          for (int index = 0; index < _boundaryDrafts.length; index++)
            _buildBoundaryEditor(_boundaryDrafts[index], index),
          TextButton.icon(
            onPressed: () => setState(() {
              _boundaryDrafts.add(
                _BoundaryCombinationDraft(id: _nextBoundaryDraftId++),
              );
            }),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add pair-to-block transform'),
          ),
        ],
      ),
    );
  }

  Widget _buildBoundaryEditor(_BoundaryCombinationDraft draft, int index) {
    final String? validation = _validationMessage(draft);
    final MarkerBoundaryCombinationResult? preview = _preview(draft);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_boundaryDrafts.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Remove transform',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => _boundaryDrafts.removeAt(index));
                  _emit();
                },
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool horizontal = constraints.maxWidth >= 620;
              final List<Widget> fields = <Widget>[
                _boundaryDropdown(
                  draft: draft,
                  role: 'Start',
                  value: draft.startLabel,
                  onChanged: (String? value) => draft.startLabel = value,
                ),
                _boundaryDropdown(
                  draft: draft,
                  role: 'Stop',
                  value: draft.stopLabel,
                  onChanged: (String? value) => draft.stopLabel = value,
                ),
                TextFormField(
                  key: ValueKey<String>('${draft.id}-block'),
                  initialValue: draft.blockLabel,
                  decoration: const InputDecoration(
                    labelText: 'Block label',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (String value) {
                    draft.blockLabel = value;
                    setState(() {});
                    _emit();
                  },
                ),
              ];
              if (!horizontal) {
                return Column(
                  children: fields
                      .map(
                        (Widget field) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: field,
                        ),
                      )
                      .toList(growable: false),
                );
              }
              return Row(
                children: fields
                    .map(
                      (Widget field) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: field,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          if (validation != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(validation, style: const TextStyle(color: Colors.redAccent)),
          ] else if (preview != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '${preview.combinedCount} complete pair${preview.combinedCount == 1 ? '' : 's'}; '
              '${preview.unmatchedStartCount} unmatched start${preview.unmatchedStartCount == 1 ? '' : 's'}; '
              '${preview.unmatchedStopCount} unmatched stop${preview.unmatchedStopCount == 1 ? '' : 's'}.',
              style: const TextStyle(color: Colors.white60),
            ),
          ],
          Row(
            children: <Widget>[
              Checkbox(
                value: draft.replaceBoundaries,
                onChanged: (bool? value) {
                  setState(() => draft.replaceBoundaries = value ?? true);
                  _emit();
                },
              ),
              const Expanded(
                child: Text('Replace paired start and stop markers'),
              ),
            ],
          ),
          Divider(color: Colors.white.withValues(alpha: 0.10)),
        ],
      ),
    );
  }

  Widget _boundaryDropdown({
    required _BoundaryCombinationDraft draft,
    required String role,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('${draft.id}-$role-${value ?? 'none'}'),
      initialValue: value ?? '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '$role marker',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem<String>(value: '', child: Text('None')),
        ..._labels.map(
          (String label) => DropdownMenuItem<String>(
            value: label,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (String? next) {
        onChanged(next == null || next.isEmpty ? null : next);
        setState(() {});
        _emit();
      },
    );
  }
}

class _BoundaryCombinationDraft {
  _BoundaryCombinationDraft({required this.id});

  final int id;
  String? startLabel;
  String? stopLabel;
  String blockLabel = '';
  bool replaceBoundaries = true;
}
