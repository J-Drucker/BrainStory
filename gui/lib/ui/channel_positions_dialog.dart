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
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
          child: _ChannelPositionsDialog(dataset: dataset),
        ),
      );
    },
  );
}

enum _TopomapValueAxis { x, y, z }

class _ChannelPositionsDialog extends StatefulWidget {
  const _ChannelPositionsDialog({required this.dataset});

  final Dataset dataset;

  @override
  State<_ChannelPositionsDialog> createState() =>
      _ChannelPositionsDialogState();
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                points: _topomapPointsForAxis(
                                  rows,
                                  _selectedAxis,
                                ),
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
                        child: _ChannelPositionTable(rows: rows, units: units),
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
  const _AxisToggleBar({required this.selectedAxis, required this.onSelected});

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
          children: _TopomapValueAxis.values
              .map((_TopomapValueAxis axis) {
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
                            ? spec.scale.palette.last.withValues(alpha: 0.22)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? spec.scale.palette.last.withValues(alpha: 0.7)
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
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ChannelPositionTable extends StatelessWidget {
  const _ChannelPositionTable({required this.rows, required this.units});

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
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
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
    return Row(
      children: <Widget>[
        const Expanded(
          flex: 3,
          child: Text(
            'Channel',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(
          flex: 2,
          child: _AxisHeaderCell(axis: _TopomapValueAxis.x),
        ),
        const Expanded(
          flex: 2,
          child: _AxisHeaderCell(axis: _TopomapValueAxis.y),
        ),
        const Expanded(
          flex: 2,
          child: _AxisHeaderCell(axis: _TopomapValueAxis.z),
        ),
      ],
    );
  }
}

class _AxisHeaderCell extends StatelessWidget {
  const _AxisHeaderCell({required this.axis});

  final _TopomapValueAxis axis;

  @override
  Widget build(BuildContext context) {
    final _AxisVisualSpec spec = _axisSpec(axis);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _AxisOrientationIcon(axis: axis, colors: spec.scale.palette),
        const SizedBox(width: 6),
        Text(
          spec.label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AxisOrientationIcon extends StatelessWidget {
  const _AxisOrientationIcon({required this.axis, required this.colors});

  final _TopomapValueAxis axis;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final bool sagittal = axis == _TopomapValueAxis.z;
    return CustomPaint(
      size: Size(sagittal ? 24 : 14, sagittal ? 12 : 24),
      painter: _AxisOrientationIconPainter(sagittal: sagittal, colors: colors),
    );
  }
}

class _AxisOrientationIconPainter extends CustomPainter {
  const _AxisOrientationIconPainter({
    required this.sagittal,
    required this.colors,
  });

  final bool sagittal;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect paintBounds = Offset.zero & size;
    final Paint fillPaint = Paint()
      ..shader = LinearGradient(colors: colors).createShader(paintBounds)
      ..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    if (sagittal) {
      final Rect ovalRect = Rect.fromLTWH(
        1.0,
        1.0,
        size.width - 2,
        size.height - 2,
      );
      canvas.drawOval(ovalRect, fillPaint);
      canvas.drawOval(ovalRect, strokePaint);
      return;
    }

    final double width = size.width;
    final double height = size.height;
    final Path path = Path()
      ..moveTo(width * 0.5, height * 0.04)
      ..cubicTo(
        width * 0.2,
        height * 0.12,
        width * 0.08,
        height * 0.38,
        width * 0.08,
        height * 0.55,
      )
      ..cubicTo(
        width * 0.08,
        height * 0.9,
        width * 0.32,
        height * 0.98,
        width * 0.5,
        height * 0.98,
      )
      ..cubicTo(
        width * 0.68,
        height * 0.98,
        width * 0.92,
        height * 0.9,
        width * 0.92,
        height * 0.55,
      )
      ..cubicTo(
        width * 0.92,
        height * 0.38,
        width * 0.8,
        height * 0.12,
        width * 0.5,
        height * 0.04,
      )
      ..close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _AxisOrientationIconPainter oldDelegate) {
    return oldDelegate.sagittal != sagittal || oldDelegate.colors != colors;
  }
}

class _CoordinateValueCell extends StatelessWidget {
  const _CoordinateValueCell({required this.value, required this.color});

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
        border: Border.all(color: color.withValues(alpha: 0.5)),
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

  final TopomapValueBounds xBounds = _symmetricBoundsForValues(
    orderedEntries.map(
      (MapEntry<String, ChannelCoordinate> entry) => entry.value.x,
    ),
  );
  final TopomapValueBounds yBounds = _symmetricBoundsForValues(
    orderedEntries.map(
      (MapEntry<String, ChannelCoordinate> entry) => entry.value.y,
    ),
  );
  final TopomapValueBounds zBounds = _symmetricBoundsForValues(
    orderedEntries.map(
      (MapEntry<String, ChannelCoordinate> entry) => entry.value.z,
    ),
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
  return rows
      .map((_ChannelPositionRow row) {
        return TopomapPointValue(
          label: row.label,
          coordinate: row.coordinate,
          value: _axisValue(row, axis),
        );
      })
      .toList(growable: false);
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
      const Color negativeColor = Color(0xFF3C7EBE);
      const Color neutralColor = Color(0xFF7A7A7A);
      const Color positiveColor = Color(0xFFA76C12);
      return _AxisVisualSpec(
        label: 'X',
        description: 'Transverse / left-right',
        scale: TopomapColorScale(
          colors: <Color>[negativeColor, neutralColor, positiveColor],
          legendLabel: 'Left to right',
        ),
      );
    case _TopomapValueAxis.y:
      const Color negativeColor = Color(0xFF628835);
      const Color neutralColor = Color(0xFF7A7A7A);
      const Color positiveColor = Color(0xFF9064AF);
      return _AxisVisualSpec(
        label: 'Y',
        description: 'Posterior-anterior',
        scale: TopomapColorScale(
          colors: <Color>[negativeColor, neutralColor, positiveColor],
          legendLabel: 'Posterior to anterior',
        ),
      );
    case _TopomapValueAxis.z:
      const Color negativeColor = Color(0xFF00908A);
      const Color neutralColor = Color(0xFF7A7A7A);
      const Color positiveColor = Color(0xFFB5596A);
      return _AxisVisualSpec(
        label: 'Z',
        description: 'Craniocaudal / inferior-superior',
        scale: TopomapColorScale(
          colors: <Color>[negativeColor, neutralColor, positiveColor],
          legendLabel: 'Inferior to superior',
        ),
      );
  }
}

TopomapValueBounds _symmetricBoundsForValues(Iterable<double> values) {
  double maxAbs = 0;
  for (final double value in values) {
    maxAbs = maxAbs < value.abs() ? value.abs() : maxAbs;
  }
  if (maxAbs == 0) {
    return const TopomapValueBounds(min: -1, max: 1);
  }
  return TopomapValueBounds(min: -maxAbs, max: maxAbs);
}

TopomapColorScale _topomapScaleForAxis(_TopomapValueAxis axis) {
  return _axisSpec(axis).scale;
}

Color _colorForAxis(
  _TopomapValueAxis axis,
  double value,
  TopomapValueBounds bounds,
) {
  return topomapColorForValue(value, bounds, _topomapScaleForAxis(axis));
}
