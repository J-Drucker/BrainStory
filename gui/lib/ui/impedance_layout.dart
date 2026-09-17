import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/data_artifacts.dart';

class ImpedanceLayout {
  const ImpedanceLayout({
    required this.positions,
    required this.surfaceSize,
    required this.circleRadius,
    required this.usesCoordinates,
    this.neighborPairs = const <ImpedanceNeighborPair>[],
  });

  final List<Offset> positions;
  final Size surfaceSize;
  final double circleRadius;
  final bool usesCoordinates;
  final List<ImpedanceNeighborPair> neighborPairs;
}

class ImpedanceNeighborPair {
  const ImpedanceNeighborPair(this.first, this.second);

  final int first;
  final int second;
}

ImpedanceLayout layoutImpedanceCircles({
  required List<String> channelLabels,
  required Map<String, ChannelCoordinate> coordinates,
  required Size viewportSize,
  double preferredRadius = 30,
}) {
  final int count = channelLabels.length;
  if (count == 0) {
    return ImpedanceLayout(
      positions: const <Offset>[],
      surfaceSize: viewportSize,
      circleRadius: preferredRadius,
      usesCoordinates: false,
    );
  }

  final List<ChannelCoordinate?> matched = channelLabels
      .map((String label) => _coordinateForLabel(coordinates, label))
      .toList(growable: false);
  if (matched.every((ChannelCoordinate? coordinate) => coordinate != null)) {
    return _coordinateLayout(
      matched.cast<ChannelCoordinate>(),
      viewportSize,
      preferredRadius,
    );
  }
  return _gridLayout(count, viewportSize, preferredRadius);
}

List<ImpedanceNeighborPair> impedanceNeighborPairs(
  List<ChannelCoordinate> coordinates,
) {
  final List<ImpedanceNeighborPair> result = <ImpedanceNeighborPair>[];
  for (int first = 0; first < coordinates.length; first++) {
    for (int second = first + 1; second < coordinates.length; second++) {
      final double pairDistance = _distance(
        coordinates[first],
        coordinates[second],
      );
      bool blocked = false;
      for (int candidate = 0; candidate < coordinates.length; candidate++) {
        if (candidate == first || candidate == second) {
          continue;
        }
        if (_distance(coordinates[first], coordinates[candidate]) <
                pairDistance ||
            _distance(coordinates[second], coordinates[candidate]) <
                pairDistance) {
          blocked = true;
          break;
        }
      }
      if (!blocked) {
        result.add(ImpedanceNeighborPair(first, second));
      }
    }
  }
  return result;
}

ImpedanceLayout _coordinateLayout(
  List<ChannelCoordinate> coordinates,
  Size viewportSize,
  double radius,
) {
  const double gap = 8;
  final List<ImpedanceNeighborPair> neighbors = impedanceNeighborPairs(
    coordinates,
  );
  final double maxAbsX = coordinates
      .map((ChannelCoordinate coordinate) => coordinate.x.abs())
      .fold<double>(0, math.max);
  final double maxAbsY = coordinates
      .map((ChannelCoordinate coordinate) => coordinate.y.abs())
      .fold<double>(0, math.max);
  final double availableWidth = math.max(1, viewportSize.width - 4 * radius);
  final double availableHeight = math.max(1, viewportSize.height - 4 * radius);
  final double fitScaleX = maxAbsX == 0
      ? double.infinity
      : availableWidth / (2 * maxAbsX);
  final double fitScaleY = maxAbsY == 0
      ? double.infinity
      : availableHeight / (2 * maxAbsY);
  double fitScale = math.min(fitScaleX, fitScaleY);
  if (!fitScale.isFinite) {
    fitScale = 1;
  }

  double minimumNeighborDistance = double.infinity;
  for (final ImpedanceNeighborPair pair in neighbors) {
    final double distance = _distance(
      coordinates[pair.first],
      coordinates[pair.second],
    );
    if (distance > 1e-9) {
      minimumNeighborDistance = math.min(minimumNeighborDistance, distance);
    }
  }
  final double collisionScale = minimumNeighborDistance.isFinite
      ? (2 * radius + gap) / minimumNeighborDistance
      : fitScale;
  final double scale = math.max(fitScale, collisionScale);
  double width = math.max(viewportSize.width, 2 * maxAbsX * scale + 4 * radius);
  double height = math.max(
    viewportSize.height,
    2 * maxAbsY * scale + 4 * radius,
  );
  final List<Offset> positions = coordinates
      .map(
        (ChannelCoordinate coordinate) => Offset(
          width / 2 + coordinate.x * scale,
          height / 2 - coordinate.y * scale,
        ),
      )
      .toList(growable: false);

  // Coincident coordinates have no preservable pair distance. Keep each
  // electrode on its original radial direction and move later duplicates out.
  for (int index = 0; index < positions.length; index++) {
    Offset direction = Offset(coordinates[index].x, -coordinates[index].y);
    if (direction.distance < 1e-9) {
      final double angle = index * math.pi * (3 - math.sqrt(5));
      direction = Offset(math.cos(angle), math.sin(angle));
    } else {
      direction /= direction.distance;
    }
    int guard = 0;
    while (_overlapsEarlier(positions, index, 2 * radius + gap) &&
        guard < 1000) {
      positions[index] += direction * (2 * radius + gap);
      guard++;
    }
  }

  final double minX = positions
      .map((Offset point) => point.dx)
      .reduce(math.min);
  final double minY = positions
      .map((Offset point) => point.dy)
      .reduce(math.min);
  final double shiftX = minX < 2 * radius ? 2 * radius - minX : 0;
  final double shiftY = minY < 2 * radius ? 2 * radius - minY : 0;
  for (int index = 0; index < positions.length; index++) {
    positions[index] += Offset(shiftX, shiftY);
  }
  width = math.max(
    width + shiftX,
    positions.map((Offset point) => point.dx).reduce(math.max) + 2 * radius,
  );
  height = math.max(
    height + shiftY,
    positions.map((Offset point) => point.dy).reduce(math.max) + 2 * radius,
  );

  return ImpedanceLayout(
    positions: positions,
    surfaceSize: Size(width, height),
    circleRadius: radius,
    usesCoordinates: true,
    neighborPairs: neighbors,
  );
}

ImpedanceLayout _gridLayout(int count, Size viewportSize, double radius) {
  const double gap = 16;
  final int columns = math.max(1, math.sqrt(count).round());
  final int rows = (count / columns).ceil();
  final double cellSize = 2 * radius + gap;
  final double width = math.max(viewportSize.width, columns * cellSize + gap);
  final double height = math.max(viewportSize.height, rows * cellSize + gap);
  final double gridWidth = columns * cellSize;
  final double gridHeight = rows * cellSize;
  final double startX = (width - gridWidth) / 2 + cellSize / 2;
  final double startY = (height - gridHeight) / 2 + cellSize / 2;
  return ImpedanceLayout(
    positions: List<Offset>.generate(
      count,
      (int index) => Offset(
        startX + (index % columns) * cellSize,
        startY + (index ~/ columns) * cellSize,
      ),
      growable: false,
    ),
    surfaceSize: Size(width, height),
    circleRadius: radius,
    usesCoordinates: false,
  );
}

bool _overlapsEarlier(
  List<Offset> positions,
  int index,
  double minimumDistance,
) {
  for (int other = 0; other < index; other++) {
    if ((positions[index] - positions[other]).distance < minimumDistance) {
      return true;
    }
  }
  return false;
}

double _distance(ChannelCoordinate first, ChannelCoordinate second) => math
    .sqrt(math.pow(first.x - second.x, 2) + math.pow(first.y - second.y, 2));

ChannelCoordinate? _coordinateForLabel(
  Map<String, ChannelCoordinate> coordinates,
  String label,
) {
  final String normalized = _normalizeLabel(label);
  final ChannelCoordinate? exact =
      coordinates[label] ?? coordinates[normalized];
  if (exact != null) {
    return exact;
  }
  for (final MapEntry<String, ChannelCoordinate> entry in coordinates.entries) {
    if (_normalizeLabel(entry.key) == normalized ||
        _normalizeLabel(entry.value.label) == normalized) {
      return entry.value;
    }
  }
  return null;
}

String _normalizeLabel(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
