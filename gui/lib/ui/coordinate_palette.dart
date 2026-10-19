import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import 'topomap_view.dart';

enum CoordinateColorAxis { x, y, z }

const Color coordinateNeutralColor = Color(0xFF7A7A7A);

TopomapColorScale coordinateColorScale(CoordinateColorAxis axis) {
  return switch (axis) {
    CoordinateColorAxis.x => TopomapColorScale(
      colors: const <Color>[
        Color(0xFF3C7EBE),
        coordinateNeutralColor,
        Color(0xFFA76C12),
      ],
      legendLabel: 'Left to right',
    ),
    CoordinateColorAxis.y => TopomapColorScale(
      colors: const <Color>[
        Color(0xFF628835),
        coordinateNeutralColor,
        Color(0xFF9064AF),
      ],
      legendLabel: 'Posterior to anterior',
    ),
    CoordinateColorAxis.z => TopomapColorScale(
      colors: const <Color>[
        Color(0xFF00908A),
        coordinateNeutralColor,
        Color(0xFFB5596A),
      ],
      legendLabel: 'Inferior to superior',
    ),
  };
}

/// Colors an electrode pair by its spatial midpoint. The axis furthest from
/// the coordinate origin chooses the hue family; sign chooses that axis's
/// pole. This keeps pair colors stable regardless of channel ordering.
Color coordinatePairColor(
  ChannelCoordinate first,
  ChannelCoordinate second, {
  required double maxAbsX,
  required double maxAbsY,
  required double maxAbsZ,
}) {
  final List<double> midpoint = <double>[
    (first.x + second.x) / 2,
    (first.y + second.y) / 2,
    (first.z + second.z) / 2,
  ];
  final List<double> bounds = <double>[
    math.max(maxAbsX, 1.0e-12),
    math.max(maxAbsY, 1.0e-12),
    math.max(maxAbsZ, 1.0e-12),
  ];
  int dominant = 0;
  for (int axis = 1; axis < 3; axis++) {
    if ((midpoint[axis] / bounds[axis]).abs() >
        (midpoint[dominant] / bounds[dominant]).abs()) {
      dominant = axis;
    }
  }
  final CoordinateColorAxis axis = CoordinateColorAxis.values[dominant];
  return topomapColorForValue(
    midpoint[dominant],
    TopomapValueBounds(min: -bounds[dominant], max: bounds[dominant]),
    coordinateColorScale(axis),
  );
}
