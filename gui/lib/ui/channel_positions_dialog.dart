import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'topomap_view.dart';

Future<void> showChannelPositionsDialog(
  BuildContext context, {
  required Dataset dataset,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: const Color(0xFF111316),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 960,
            maxHeight: 760,
          ),
          child: _ChannelPositionsDialog(dataset: dataset),
        ),
      );
    },
  );
}

enum _TopomapValueAxis {
  x,
  y,
  z,
}

class _ChannelPositionsDialog extends StatefulWidget {
  const _ChannelPositionsDialog({
    required this.dataset,
  });

  final Dataset dataset;

  @override
  State<_ChannelPositionsDialog> createState() => _ChannelPositionsDialogState();
}

class _ChannelPositionsDialogState extends State<_ChannelPositionsDialog> {
  _TopomapValueAxis _selectedAxis = _TopomapValueAxis.y;

  @override
  Widget build(BuildContext context) {
    final TimeSeriesData? timeSeries = widget.dataset.timeSeries;
    final List<_ChannelPositionRow> rows = _rowsForTimeSeries(timeSeries);
    final String units = rows.isEmpty ? 'mm' : rows.first.coordinate.units;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Channel positions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.dataset.label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                color: Colors.white70,
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No channel coordinates are attached to this dataset yet.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const Text(
                                        'Scalp map',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_axisSpec(_selectedAxis).description} ($units)',
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _AxisToggleBar(
                                  selectedAxis: _selectedAxis,
                                  onSelected: (_TopomapValueAxis axis) {
                                    setState(() {
                                      _selectedAxis = axis;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: InterpolatedTopomap(
                                points: _topomapPointsForAxis(rows, _selectedAxis),
                                scale: _topomapScaleForAxis(_selectedAxis),
                                bounds: _boundsForAxis(rows, _selectedAxis),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TopomapLegendBar(
                              scale: _topomapScaleForAxis(_selectedAxis),
                              bounds: _boundsForAxis(rows, _selectedAxis),
                              units: units,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _ChannelPositionTable(
                          rows: rows,
                          units: units,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AxisToggleBar extends StatelessWidget {
  const _AxisToggleBar({
    required this.selectedAxis,
    required this.onSelected,
  });

  final _TopomapValueAxis selectedAxis;
  final ValueChanged<_TopomapValueAxis> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _TopomapValueAxis.values.map((_TopomapValueAxis axis) {
            final _AxisVisualSpec spec = _axisSpec(axis);
            final bool selected = axis == selectedAxis;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => onSelected(axis),
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? spec.scale.endColor.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? spec.scale.endColor.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    spec.label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _ChannelPositionTable extends StatelessWidget {
  const _ChannelPositionTable({
    required this.rows,
    required this.units,
  });

  final List<_ChannelPositionRow> rows;
  final String units;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'XYZ coordinates ($units)',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        const _ChannelPositionTableHeader(),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            itemBuilder: (BuildContext context, int index) {
              final _ChannelPositionRow row = rows[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.label,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _CoordinateValueCell(
                        value: row.coordinate.x,
                        color: _colorForAxis(
                          _TopomapValueAxis.x,
                          row.coordinate.x,
                          row.xBounds,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _CoordinateValueCell(
                        value: row.coordinate.y,
                        color: _colorForAxis(
                          _TopomapValueAxis.y,
                          row.coordinate.y,
                          row.yBounds,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _CoordinateValueCell(
                        value: row.coordinate.z,
                        color: _colorForAxis(
                          _TopomapValueAxis.z,
                          row.coordinate.z,
                          row.zBounds,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChannelPositionTableHeader extends StatelessWidget {
  const _ChannelPositionTableHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Text(
            'Channel',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'X',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Y',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Z',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _CoordinateValueCell extends StatelessWidget {
  const _CoordinateValueCell({
    required this.value,
    required this.color,
  });

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        value.toStringAsFixed(2),
        style: const TextStyle(
          color: Colors.white,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ChannelPositionRow {
  const _ChannelPositionRow({
    required this.label,
    required this.coordinate,
    required this.xBounds,
    required this.yBounds,
    required this.zBounds,
  });

  final String label;
  final ChannelCoordinate coordinate;
  final TopomapValueBounds xBounds;
  final TopomapValueBounds yBounds;
  final TopomapValueBounds zBounds;
}

class _AxisVisualSpec {
  const _AxisVisualSpec({
    required this.label,
    required this.description,
    required this.scale,
  });

  final String label;
  final String description;
  final TopomapColorScale scale;
}

List<_ChannelPositionRow> _rowsForTimeSeries(TimeSeriesData? timeSeries) {
  if (timeSeries == null || timeSeries.channelCoordinates.isEmpty) {
    return const <_ChannelPositionRow>[];
  }

  final List<String> labels = timeSeries.channelLabels.isEmpty
      ? timeSeries.channelCoordinates.keys.toList(growable: false)
      : timeSeries.channelLabels;
  final List<MapEntry<String, ChannelCoordinate>> orderedEntries = labels
      .where((String label) => timeSeries.channelCoordinates.containsKey(label))
      .map(
        (String label) => MapEntry<String, ChannelCoordinate>(
          label,
          timeSeries.channelCoordinates[label]!,
        ),
      )
      .toList(growable: true);
  for (final MapEntry<String, ChannelCoordinate> entry
      in timeSeries.channelCoordinates.entries) {
    if (orderedEntries.any((candidate) => candidate.key == entry.key)) {
      continue;
    }
    orderedEntries.add(entry);
  }

  final TopomapValueBounds xBounds = TopomapValueBounds.fromValues(
    orderedEntries.map((MapEntry<String, ChannelCoordinate> entry) => entry.value.x),
  );
  final TopomapValueBounds yBounds = TopomapValueBounds.fromValues(
    orderedEntries.map((MapEntry<String, ChannelCoordinate> entry) => entry.value.y),
  );
  final TopomapValueBounds zBounds = TopomapValueBounds.fromValues(
    orderedEntries.map((MapEntry<String, ChannelCoordinate> entry) => entry.value.z),
  );

  return orderedEntries
      .map(
        (MapEntry<String, ChannelCoordinate> entry) => _ChannelPositionRow(
          label: entry.key,
          coordinate: entry.value,
          xBounds: xBounds,
          yBounds: yBounds,
          zBounds: zBounds,
        ),
      )
      .toList(growable: false);
}

List<TopomapPointValue> _topomapPointsForAxis(
  List<_ChannelPositionRow> rows,
  _TopomapValueAxis axis,
) {
  return rows.map((_ChannelPositionRow row) {
    return TopomapPointValue(
      label: row.label,
      coordinate: row.coordinate,
      value: _axisValue(row, axis),
    );
  }).toList(growable: false);
}

double _axisValue(_ChannelPositionRow row, _TopomapValueAxis axis) {
  switch (axis) {
    case _TopomapValueAxis.x:
      return row.coordinate.x;
    case _TopomapValueAxis.y:
      return row.coordinate.y;
    case _TopomapValueAxis.z:
      return row.coordinate.z;
  }
}

TopomapValueBounds _boundsForAxis(
  List<_ChannelPositionRow> rows,
  _TopomapValueAxis axis,
) {
  if (rows.isEmpty) {
    return const TopomapValueBounds(min: -1, max: 1);
  }
  switch (axis) {
    case _TopomapValueAxis.x:
      return rows.first.xBounds;
    case _TopomapValueAxis.y:
      return rows.first.yBounds;
    case _TopomapValueAxis.z:
      return rows.first.zBounds;
  }
}

_AxisVisualSpec _axisSpec(_TopomapValueAxis axis) {
  switch (axis) {
    case _TopomapValueAxis.x:
      return const _AxisVisualSpec(
        label: 'X',
        description: 'Transverse / left-right',
        scale: TopomapColorScale(
          startColor: Color(0xFF00E5FF),
          endColor: Color(0xFFFF5252),
          legendLabel: 'Left to right',
        ),
      );
    case _TopomapValueAxis.y:
      return const _AxisVisualSpec(
        label: 'Y',
        description: 'Posterior-anterior',
        scale: TopomapColorScale(
          startColor: Color(0xFFFF4DFF),
          endColor: Color(0xFF00E676),
          legendLabel: 'Posterior to anterior',
        ),
      );
    case _TopomapValueAxis.z:
      return const _AxisVisualSpec(
        label: 'Z',
        description: 'Craniocaudal / inferior-superior',
        scale: TopomapColorScale(
          startColor: Color(0xFFFFFF66),
          endColor: Color(0xFF40C4FF),
          legendLabel: 'Inferior to superior',
        ),
      );
  }
}

TopomapColorScale _topomapScaleForAxis(_TopomapValueAxis axis) {
  return _axisSpec(axis).scale;
}

Color _colorForAxis(
  _TopomapValueAxis axis,
  double value,
  TopomapValueBounds bounds,
) {
  return topomapColorForValue(
    value,
    bounds,
    _topomapScaleForAxis(axis),
  );
}
