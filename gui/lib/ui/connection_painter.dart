import 'package:flutter/material.dart';

List<Offset> buildConnectionPolyline({
  required Offset start,
  required Offset end,
  required bool preferVertical,
  required double gridWidth,
  required double gridHeight,
  List<Rect> obstacles = const <Rect>[],
  double clearance = 12.0,
}) {
  final List<Rect> inflatedObstacles = obstacles
      .map((Rect rect) => rect.inflate(clearance))
      .toList(growable: false);

  final List<List<Offset>> candidates = <List<Offset>>[];
  final List<double> candidateYs = _candidateAxisValues(
    primary: _snapToHalfGrid((start.dy + end.dy) / 2, gridHeight),
    obstacleStarts: inflatedObstacles.map((Rect rect) => rect.top),
    obstacleEnds: inflatedObstacles.map((Rect rect) => rect.bottom),
    gridSize: gridHeight,
  );
  final List<double> candidateXs = _candidateAxisValues(
    primary: _snapToHalfGrid((start.dx + end.dx) / 2, gridWidth),
    obstacleStarts: inflatedObstacles.map((Rect rect) => rect.left),
    obstacleEnds: inflatedObstacles.map((Rect rect) => rect.right),
    gridSize: gridWidth,
  );

  if ((start.dx - end.dx).abs() < 0.001 || (start.dy - end.dy).abs() < 0.001) {
    candidates.add(<Offset>[start, end]);
  }

  for (final double midY in candidateYs) {
    candidates.add(<Offset>[
      start,
      Offset(start.dx, midY),
      Offset(end.dx, midY),
      end,
    ]);
  }
  for (final double midX in candidateXs) {
    candidates.add(<Offset>[
      start,
      Offset(midX, start.dy),
      Offset(midX, end.dy),
      end,
    ]);
  }

  final Iterable<List<Offset>> orderedCandidates = preferVertical
      ? candidates
      : <List<Offset>>[
          ...candidates.where((List<Offset> points) => points.length > 2 && points[1].dy == start.dy),
          ...candidates.where((List<Offset> points) => !(points.length > 2 && points[1].dy == start.dy)),
        ];

  List<Offset>? best;
  double bestScore = double.infinity;
  for (final List<Offset> candidate in orderedCandidates) {
    if (_polylineIntersectsObstacles(candidate, inflatedObstacles)) {
      continue;
    }
    final double score = _polylineLength(candidate) +
        ((preferVertical == _isVerticalCandidate(candidate)) ? 0.0 : 1.0);
    if (score < bestScore) {
      best = candidate;
      bestScore = score;
    }
  }

  if (best != null) {
    return _compressPolyline(best);
  }

  return _compressPolyline(candidates.first);
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
  final List<double> sorted = values.toList(growable: false)
    ..sort((double a, double b) => (a - primary).abs().compareTo((b - primary).abs()));
  return sorted;
}

bool _polylineIntersectsObstacles(List<Offset> points, List<Rect> obstacles) {
  for (int index = 1; index < points.length; index++) {
    if (_segmentIntersectsObstacles(points[index - 1], points[index], obstacles)) {
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
    required this.gridWidth,
    required this.gridHeight,
    this.obstacles = const <Rect>[],
    this.selected = false,
    this.color = Colors.orangeAccent,
  });

  final Offset start;
  final Offset end;
  final bool preferVertical;
  final double gridWidth;
  final double gridHeight;
  final List<Rect> obstacles;
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
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      obstacles: obstacles,
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
        gridWidth != oldDelegate.gridWidth ||
        gridHeight != oldDelegate.gridHeight ||
        obstacles != oldDelegate.obstacles;
  }
}
