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
    primary: (routedStart.dx + routedEnd.dx) / 2,
  );
  _addWireDetourAxes(
    candidateYs,
    existingPolylines,
    horizontal: false,
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
  for (final List<Offset> rawCandidate in orderedCandidates) {
    final List<Offset> candidate = _compressPolyline(rawCandidate);
    if (candidate.length < 2) {
      continue;
    }
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
    if (_polylineConflictCount(candidate, existingPolylines) > 0) {
      continue;
    }
    final double score =
        _polylineLength(candidate) +
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

  final List<Offset> searchedRoute = _findClearOrthogonalRoute(
    start: routedStart,
    end: routedEnd,
    startVertical: preferVertical,
    endVertical: endVertical,
    obstacles: inflatedObstacles,
    existingPolylines: existingPolylines,
    seedXs: candidateXs,
    seedYs: candidateYs,
    clearance: clearance,
  );
  if (searchedRoute.length < 2) {
    return <Offset>[start];
  }
  return _withEndpointLeads(
    searchedRoute,
    start: start,
    end: end,
    hasStartLead: startDirection != null,
    hasEndLead: endDirection != null,
  );
}

List<Offset> _findClearOrthogonalRoute({
  required Offset start,
  required Offset end,
  required bool startVertical,
  required bool? endVertical,
  required List<Rect> obstacles,
  required List<List<Offset>> existingPolylines,
  required List<double> seedXs,
  required List<double> seedYs,
  required double clearance,
}) {
  const double wireLaneSpacing = 7;
  final Set<double> xs = <double>{start.dx, end.dx, ...seedXs};
  final Set<double> ys = <double>{start.dy, end.dy, ...seedYs};
  for (final Rect obstacle in obstacles) {
    xs
      ..add(obstacle.left)
      ..add(obstacle.right);
    ys
      ..add(obstacle.top)
      ..add(obstacle.bottom);
  }
  for (final List<Offset> polyline in existingPolylines) {
    for (final Offset point in polyline) {
      xs
        ..add(point.dx)
        ..add(point.dx - wireLaneSpacing)
        ..add(point.dx + wireLaneSpacing);
      ys
        ..add(point.dy)
        ..add(point.dy - wireLaneSpacing)
        ..add(point.dy + wireLaneSpacing);
    }
  }

  final Iterable<double> allXs = <double>[
    start.dx,
    end.dx,
    ...obstacles.expand((Rect rect) => <double>[rect.left, rect.right]),
    ...existingPolylines.expand(
      (List<Offset> route) => route.map((Offset point) => point.dx),
    ),
  ];
  final Iterable<double> allYs = <double>[
    start.dy,
    end.dy,
    ...obstacles.expand((Rect rect) => <double>[rect.top, rect.bottom]),
    ...existingPolylines.expand(
      (List<Offset> route) => route.map((Offset point) => point.dy),
    ),
  ];
  final double outerMargin = math.max(64, clearance * 4);
  xs
    ..add(allXs.reduce(math.min) - outerMargin)
    ..add(allXs.reduce(math.max) + outerMargin);
  ys
    ..add(allYs.reduce(math.min) - outerMargin)
    ..add(allYs.reduce(math.max) + outerMargin);

  final List<double> sortedXs = xs.toList()..sort();
  final List<double> sortedYs = ys.toList()..sort();
  final int width = sortedXs.length;
  final int height = sortedYs.length;
  final int startX = sortedXs.indexOf(start.dx);
  final int startY = sortedYs.indexOf(start.dy);
  final int endX = sortedXs.indexOf(end.dx);
  final int endY = sortedYs.indexOf(end.dy);
  final int startPoint = (startY * width) + startX;
  final int endPoint = (endY * width) + endX;
  final Map<int, double> distances = <int, double>{};
  final Map<int, int> previous = <int, int>{};
  final _RoutePriorityQueue queue = _RoutePriorityQueue();

  Offset pointForIndex(int pointIndex) {
    return Offset(
      sortedXs[pointIndex % width],
      sortedYs[pointIndex ~/ width],
    );
  }

  Iterable<int> neighborPoints(int pointIndex) sync* {
    final int x = pointIndex % width;
    final int y = pointIndex ~/ width;
    if (x > 0) yield pointIndex - 1;
    if (x + 1 < width) yield pointIndex + 1;
    if (y > 0) yield pointIndex - width;
    if (y + 1 < height) yield pointIndex + width;
  }

  bool segmentIsClear(Offset a, Offset b) {
    return !_segmentIntersectsObstacles(a, b, obstacles) &&
        _polylineConflictCount(<Offset>[a, b], existingPolylines) == 0;
  }

  for (final int neighbor in neighborPoints(startPoint)) {
    final Offset neighborPoint = pointForIndex(neighbor);
    final bool vertical = _segmentIsVertical(start, neighborPoint);
    if (vertical != startVertical || !segmentIsClear(start, neighborPoint)) {
      continue;
    }
    final int state = (neighbor * 2) + (vertical ? 1 : 0);
    final double distance = (neighborPoint - start).distance;
    distances[state] = distance;
    previous[state] = -1;
    queue.add(_RouteQueueEntry(state: state, distance: distance));
  }

  int? goalState;
  while (queue.isNotEmpty) {
    final _RouteQueueEntry current = queue.removeFirst();
    if (current.distance != distances[current.state]) {
      continue;
    }
    final int pointIndex = current.state ~/ 2;
    final bool arrivedVertically = current.state.isOdd;
    if (pointIndex == endPoint &&
        (endVertical == null || arrivedVertically == endVertical)) {
      goalState = current.state;
      break;
    }
    final Offset currentPoint = pointForIndex(pointIndex);
    for (final int neighbor in neighborPoints(pointIndex)) {
      final Offset neighborPoint = pointForIndex(neighbor);
      final bool vertical = _segmentIsVertical(currentPoint, neighborPoint);
      if (!segmentIsClear(currentPoint, neighborPoint)) {
        continue;
      }
      final int nextState = (neighbor * 2) + (vertical ? 1 : 0);
      final double bendPenalty = vertical == arrivedVertically ? 0 : 16;
      final double nextDistance =
          current.distance +
          (neighborPoint - currentPoint).distance +
          bendPenalty;
      if (nextDistance >= (distances[nextState] ?? double.infinity)) {
        continue;
      }
      distances[nextState] = nextDistance;
      previous[nextState] = current.state;
      queue.add(_RouteQueueEntry(state: nextState, distance: nextDistance));
    }
  }

  if (goalState == null) {
    // A connection is withheld rather than drawn through a node or another wire.
    return <Offset>[start];
  }
  final List<Offset> reversed = <Offset>[];
  int state = goalState;
  while (state >= 0) {
    reversed.add(pointForIndex(state ~/ 2));
    state = previous[state] ?? -1;
  }
  return _compressPolyline(<Offset>[start, ...reversed.reversed]);
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
  required double primary,
}) {
  final Set<double> expanded = values.toSet();
  const double detour = 7;
  for (final List<Offset> polyline in polylines) {
    for (final Offset point in polyline) {
      final double value = horizontal ? point.dx : point.dy;
      expanded
        ..add(value - detour)
        ..add(value + detour);
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
  if ((a - b).distance < epsilon || (c - d).distance < epsilon) {
    return false;
  }
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
      x >= math.min(horizontalStart.dx, horizontalEnd.dx) - epsilon &&
      x <= math.max(horizontalStart.dx, horizontalEnd.dx) + epsilon &&
      y >= math.min(verticalStart.dy, verticalEnd.dy) - epsilon &&
      y <= math.max(verticalStart.dy, verticalEnd.dy) + epsilon;
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
    if (compact.length >= 2) {
      final Offset a = compact[compact.length - 2];
      final Offset b = compact.last;
      final bool sameVertical =
          (a.dx - b.dx).abs() < 0.001 && (b.dx - point.dx).abs() < 0.001;
      final bool sameHorizontal =
          (a.dy - b.dy).abs() < 0.001 && (b.dy - point.dy).abs() < 0.001;
      if (sameVertical || sameHorizontal) {
        compact[compact.length - 1] = point;
        continue;
      }
    }
    compact.add(point);
  }
  return compact;
}

class _RouteQueueEntry {
  const _RouteQueueEntry({required this.state, required this.distance});

  final int state;
  final double distance;
}

class _RoutePriorityQueue {
  final List<_RouteQueueEntry> _entries = <_RouteQueueEntry>[];

  bool get isNotEmpty => _entries.isNotEmpty;

  void add(_RouteQueueEntry entry) {
    _entries.add(entry);
    int index = _entries.length - 1;
    while (index > 0) {
      final int parent = (index - 1) ~/ 2;
      if (_entries[parent].distance <= entry.distance) break;
      _entries[index] = _entries[parent];
      index = parent;
    }
    _entries[index] = entry;
  }

  _RouteQueueEntry removeFirst() {
    final _RouteQueueEntry first = _entries.first;
    final _RouteQueueEntry last = _entries.removeLast();
    if (_entries.isEmpty) return first;
    int index = 0;
    while (true) {
      final int left = (index * 2) + 1;
      if (left >= _entries.length) break;
      final int right = left + 1;
      final int child = right < _entries.length &&
              _entries[right].distance < _entries[left].distance
          ? right
          : left;
      if (_entries[child].distance >= last.distance) break;
      _entries[index] = _entries[child];
      index = child;
    }
    _entries[index] = last;
    return first;
  }
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
