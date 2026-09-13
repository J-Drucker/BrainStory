import 'dart:math' as math;

import 'package:flutter/material.dart';

List<Offset> buildConnectionPolyline({
  required Offset start,
  required Offset end,
  required bool preferVertical,
  bool? endVertical,
  Offset? startDirection,
  Offset? endDirection,
  required double gridWidth,
  required double gridHeight,
  List<Rect> obstacles = const <Rect>[],
  List<List<Offset>> existingPolylines = const <List<Offset>>[],
  double clearance = 12.0,
}) {
  final List<Rect> inflatedObstacles = obstacles
      .map((Rect rect) => rect.inflate(clearance))
      .toList(growable: false);
  final double leadLength = clearance + 4;
  final Offset routedStart = startDirection == null
      ? start
      : start + (startDirection * leadLength);
  final Offset routedEnd = endDirection == null
      ? end
      : end + (endDirection * leadLength);

  final List<List<Offset>> candidates = <List<Offset>>[];
  final List<double> candidateYs = _candidateAxisValues(
    primary: _snapToHalfGrid((routedStart.dy + routedEnd.dy) / 2, gridHeight),
    obstacleStarts: inflatedObstacles.map((Rect rect) => rect.top),
    obstacleEnds: inflatedObstacles.map((Rect rect) => rect.bottom),
    gridSize: gridHeight,
  );
  final List<double> candidateXs = _candidateAxisValues(
    primary: _snapToHalfGrid((routedStart.dx + routedEnd.dx) / 2, gridWidth),
    obstacleStarts: inflatedObstacles.map((Rect rect) => rect.left),
    obstacleEnds: inflatedObstacles.map((Rect rect) => rect.right),
    gridSize: gridWidth,
  );
  _addWireDetourAxes(
    candidateXs,
    existingPolylines,
    horizontal: true,
    gridSize: gridWidth,
    primary: (routedStart.dx + routedEnd.dx) / 2,
  );
  _addWireDetourAxes(
    candidateYs,
    existingPolylines,
    horizontal: false,
    gridSize: gridHeight,
    primary: (routedStart.dy + routedEnd.dy) / 2,
  );
  _addEndpointDetourAxes(
    candidateXs,
    routedStart.dx,
    routedEnd.dx,
    clearance: clearance,
  );
  _addEndpointDetourAxes(
    candidateYs,
    routedStart.dy,
    routedEnd.dy,
    clearance: clearance,
  );

  if ((routedStart.dx - routedEnd.dx).abs() < 0.001 ||
      (routedStart.dy - routedEnd.dy).abs() < 0.001) {
    candidates.add(<Offset>[routedStart, routedEnd]);
  }

  for (final double midY in candidateYs) {
    candidates.add(<Offset>[
      routedStart,
      Offset(routedStart.dx, midY),
      Offset(routedEnd.dx, midY),
      routedEnd,
    ]);
  }
  for (final double midX in candidateXs) {
    candidates.add(<Offset>[
      routedStart,
      Offset(midX, routedStart.dy),
      Offset(midX, routedEnd.dy),
      routedEnd,
    ]);
  }
  for (final double midX in candidateXs) {
    for (final double midY in candidateYs) {
      candidates.add(<Offset>[
        routedStart,
        Offset(midX, routedStart.dy),
        Offset(midX, midY),
        Offset(routedEnd.dx, midY),
        routedEnd,
      ]);
      candidates.add(<Offset>[
        routedStart,
        Offset(routedStart.dx, midY),
        Offset(midX, midY),
        Offset(midX, routedEnd.dy),
        routedEnd,
      ]);
    }
  }

  final Iterable<List<Offset>> orderedCandidates = preferVertical
      ? candidates
      : <List<Offset>>[
          ...candidates.where(
            (List<Offset> points) =>
                points.length > 2 && points[1].dy == routedStart.dy,
          ),
          ...candidates.where(
            (List<Offset> points) =>
                !(points.length > 2 && points[1].dy == routedStart.dy),
          ),
        ];

  List<Offset>? best;
  double bestScore = double.infinity;
  for (final List<Offset> candidate in orderedCandidates) {
    if (_polylineIntersectsObstacles(candidate, inflatedObstacles)) {
      continue;
    }
    if (_segmentIsVertical(candidate[0], candidate[1]) != preferVertical ||
        (endVertical != null &&
            _segmentIsVertical(
                  candidate[candidate.length - 2],
                  candidate.last,
                ) !=
                endVertical)) {
      continue;
    }
    final double score =
        _polylineLength(candidate) +
        (_polylineConflictCount(candidate, existingPolylines) * 10000) +
        ((preferVertical == _isVerticalCandidate(candidate)) ? 0.0 : 4.0);
    if (score < bestScore) {
      best = candidate;
      bestScore = score;
    }
  }

  if (best != null) {
    return _withEndpointLeads(
      best,
      start: start,
      end: end,
      hasStartLead: startDirection != null,
      hasEndLead: endDirection != null,
    );
  }

  return _withEndpointLeads(
    candidates.first,
    start: start,
    end: end,
    hasStartLead: startDirection != null,
    hasEndLead: endDirection != null,
  );
}

List<Offset> _withEndpointLeads(
  List<Offset> route, {
  required Offset start,
  required Offset end,
  required bool hasStartLead,
  required bool hasEndLead,
}) {
  return _compressPolyline(<Offset>[
    if (hasStartLead) start,
    ...route,
    if (hasEndLead) end,
  ]);
}

void _addEndpointDetourAxes(
  List<double> values,
  double start,
  double end, {
  required double clearance,
}) {
  final Set<double> expanded = values.toSet()
    ..add(start - (clearance * 2))
    ..add(start + (clearance * 2))
    ..add(end - (clearance * 2))
    ..add(end + (clearance * 2));
  final double primary = (start + end) / 2;
  values
    ..clear()
    ..addAll(expanded)
    ..sort(
      (double a, double b) =>
          (a - primary).abs().compareTo((b - primary).abs()),
    );
}

bool _segmentIsVertical(Offset start, Offset end) {
  return (start.dx - end.dx).abs() < 0.001;
}

void _addWireDetourAxes(
  List<double> values,
  List<List<Offset>> polylines, {
  required bool horizontal,
  required double gridSize,
  required double primary,
}) {
  final Set<double> expanded = values.toSet();
  final double detour = gridSize / 2;
  for (final List<Offset> polyline in polylines) {
    for (final Offset point in polyline) {
      final double value = horizontal ? point.dx : point.dy;
      expanded
        ..add(_snapToHalfGrid(value - detour, gridSize))
        ..add(_snapToHalfGrid(value + detour, gridSize));
    }
  }
  values
    ..clear()
    ..addAll(expanded)
    ..sort(
      (double a, double b) =>
          (a - primary).abs().compareTo((b - primary).abs()),
    );
}

int _polylineConflictCount(
  List<Offset> candidate,
  List<List<Offset>> existingPolylines,
) {
  int conflicts = 0;
  for (
    int candidateIndex = 1;
    candidateIndex < candidate.length;
    candidateIndex++
  ) {
    final Offset a = candidate[candidateIndex - 1];
    final Offset b = candidate[candidateIndex];
    for (final List<Offset> existing in existingPolylines) {
      for (
        int existingIndex = 1;
        existingIndex < existing.length;
        existingIndex++
      ) {
        if (_orthogonalSegmentsConflict(
          a,
          b,
          existing[existingIndex - 1],
          existing[existingIndex],
        )) {
          conflicts++;
        }
      }
    }
  }
  return conflicts;
}

bool _orthogonalSegmentsConflict(Offset a, Offset b, Offset c, Offset d) {
  const double epsilon = 0.001;
  final bool abVertical = (a.dx - b.dx).abs() < epsilon;
  final bool cdVertical = (c.dx - d.dx).abs() < epsilon;
  if (abVertical && cdVertical) {
    if ((a.dx - c.dx).abs() >= epsilon) return false;
    final double overlap =
        math.min(math.max(a.dy, b.dy), math.max(c.dy, d.dy)) -
        math.max(math.min(a.dy, b.dy), math.min(c.dy, d.dy));
    return overlap > epsilon;
  }
  if (!abVertical && !cdVertical) {
    if ((a.dy - c.dy).abs() >= epsilon) return false;
    final double overlap =
        math.min(math.max(a.dx, b.dx), math.max(c.dx, d.dx)) -
        math.max(math.min(a.dx, b.dx), math.min(c.dx, d.dx));
    return overlap > epsilon;
  }
  final Offset verticalStart = abVertical ? a : c;
  final Offset verticalEnd = abVertical ? b : d;
  final Offset horizontalStart = abVertical ? c : a;
  final Offset horizontalEnd = abVertical ? d : b;
  final double x = verticalStart.dx;
  final double y = horizontalStart.dy;
  final bool crosses =
      x > math.min(horizontalStart.dx, horizontalEnd.dx) + epsilon &&
      x < math.max(horizontalStart.dx, horizontalEnd.dx) - epsilon &&
      y > math.min(verticalStart.dy, verticalEnd.dy) + epsilon &&
      y < math.max(verticalStart.dy, verticalEnd.dy) - epsilon;
  return crosses;
}

double _snapToHalfGrid(double value, double gridSize) {
  final double halfGrid = gridSize / 2;
  return (value / halfGrid).round() * halfGrid;
}

List<double> _candidateAxisValues({
  required double primary,
  required Iterable<double> obstacleStarts,
  required Iterable<double> obstacleEnds,
  required double gridSize,
}) {
  final Set<double> values = <double>{primary};
  for (final double edge in obstacleStarts) {
    values.add(_snapToHalfGrid(edge, gridSize));
  }
  for (final double edge in obstacleEnds) {
    values.add(_snapToHalfGrid(edge, gridSize));
  }
  final List<double> sorted = values.toList()
    ..sort(
      (double a, double b) =>
          (a - primary).abs().compareTo((b - primary).abs()),
    );
  return sorted;
}

bool _polylineIntersectsObstacles(List<Offset> points, List<Rect> obstacles) {
  for (int index = 1; index < points.length; index++) {
    if (_segmentIntersectsObstacles(
      points[index - 1],
      points[index],
      obstacles,
    )) {
      return true;
    }
  }
  return false;
}

bool _segmentIntersectsObstacles(Offset a, Offset b, List<Rect> obstacles) {
  for (final Rect obstacle in obstacles) {
    if (_segmentIntersectsRect(a, b, obstacle)) {
      return true;
    }
  }
  return false;
}

bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
  if ((a.dx - b.dx).abs() < 0.001) {
    final double x = a.dx;
    if (x <= rect.left || x >= rect.right) {
      return false;
    }
    final double top = a.dy < b.dy ? a.dy : b.dy;
    final double bottom = a.dy > b.dy ? a.dy : b.dy;
    return bottom > rect.top && top < rect.bottom;
  }

  if ((a.dy - b.dy).abs() < 0.001) {
    final double y = a.dy;
    if (y <= rect.top || y >= rect.bottom) {
      return false;
    }
    final double left = a.dx < b.dx ? a.dx : b.dx;
    final double right = a.dx > b.dx ? a.dx : b.dx;
    return right > rect.left && left < rect.right;
  }

  return false;
}

double _polylineLength(List<Offset> points) {
  double total = 0.0;
  for (int index = 1; index < points.length; index++) {
    total += (points[index] - points[index - 1]).distance;
  }
  return total;
}

bool _isVerticalCandidate(List<Offset> points) {
  return points.length > 2 && (points[1].dx - points.first.dx).abs() < 0.001;
}

List<Offset> _compressPolyline(List<Offset> points) {
  final List<Offset> compact = <Offset>[];
  for (final Offset point in points) {
    if (compact.isEmpty) {
      compact.add(point);
      continue;
    }
    if ((compact.last - point).distance < 0.001) {
      continue;
    }
    compact.add(point);
  }
  return compact;
}

class ConnectionPainter extends CustomPainter {
  const ConnectionPainter({
    required this.start,
    required this.end,
    required this.preferVertical,
    this.endVertical,
    this.startDirection,
    this.endDirection,
    required this.gridWidth,
    required this.gridHeight,
    this.obstacles = const <Rect>[],
    this.existingPolylines = const <List<Offset>>[],
    this.selected = false,
    this.color = Colors.orangeAccent,
  });

  final Offset start;
  final Offset end;
  final bool preferVertical;
  final bool? endVertical;
  final Offset? startDirection;
  final Offset? endDirection;
  final double gridWidth;
  final double gridHeight;
  final List<Rect> obstacles;
  final List<List<Offset>> existingPolylines;
  final bool selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = selected ? Colors.white : color
      ..strokeWidth = selected ? 4 : 2
      ..style = PaintingStyle.stroke;

    final List<Offset> points = buildConnectionPolyline(
      start: start,
      end: end,
      preferVertical: preferVertical,
      endVertical: endVertical,
      startDirection: startDirection,
      endDirection: endDirection,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      obstacles: obstacles,
      existingPolylines: existingPolylines,
    );
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return start != oldDelegate.start ||
        end != oldDelegate.end ||
        selected != oldDelegate.selected ||
        color != oldDelegate.color ||
        preferVertical != oldDelegate.preferVertical ||
        endVertical != oldDelegate.endVertical ||
        startDirection != oldDelegate.startDirection ||
        endDirection != oldDelegate.endDirection ||
        gridWidth != oldDelegate.gridWidth ||
        gridHeight != oldDelegate.gridHeight ||
        obstacles != oldDelegate.obstacles ||
        existingPolylines != oldDelegate.existingPolylines;
  }
}
