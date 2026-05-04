import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';

class TopomapPointValue {
  const TopomapPointValue({
    required this.label,
    required this.coordinate,
    required this.value,
  });

  final String label;
  final ChannelCoordinate coordinate;
  final double value;
}

class TopomapValueBounds {
  const TopomapValueBounds({
    required this.min,
    required this.max,
  });

  final double min;
  final double max;

  static TopomapValueBounds fromValues(Iterable<double> values) {
    final List<double> list = values.toList(growable: false);
    if (list.isEmpty) {
      return const TopomapValueBounds(min: -1, max: 1);
    }
    double minValue = list.first;
    double maxValue = list.first;
    for (final double value in list.skip(1)) {
      minValue = math.min(minValue, value);
      maxValue = math.max(maxValue, value);
    }
    if (minValue == maxValue) {
      return TopomapValueBounds(min: minValue - 1, max: maxValue + 1);
    }
    return TopomapValueBounds(min: minValue, max: maxValue);
  }
}

class TopomapColorScale {
  const TopomapColorScale({
    required this.startColor,
    required this.endColor,
    this.legendLabel = '',
  });

  final Color startColor;
  final Color endColor;
  final String legendLabel;
}

Color topomapColorForValue(
  double value,
  TopomapValueBounds bounds,
  TopomapColorScale scale,
) {
  final double t = ((value - bounds.min) / (bounds.max - bounds.min))
      .clamp(0.0, 1.0);
  return Color.lerp(scale.startColor, scale.endColor, t) ?? scale.endColor;
}

class TopomapLegendBar extends StatelessWidget {
  const TopomapLegendBar({
    super.key,
    required this.scale,
    required this.bounds,
    this.units = '',
  });

  final TopomapColorScale scale;
  final TopomapValueBounds bounds;
  final String units;

  @override
  Widget build(BuildContext context) {
    final String suffix = units.isEmpty ? '' : ' $units';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (scale.legendLabel.isNotEmpty)
          Text(
            scale.legendLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (scale.legendLabel.isNotEmpty) const SizedBox(height: 8),
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: <Color>[
                scale.startColor,
                scale.endColor,
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${bounds.min.toStringAsFixed(1)}$suffix',
                style: TextStyle(
                  color: scale.startColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${bounds.max.toStringAsFixed(1)}$suffix',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: scale.endColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class InterpolatedTopomap extends StatelessWidget {
  const InterpolatedTopomap({
    super.key,
    required this.points,
    required this.scale,
    required this.bounds,
    this.showLabels = true,
  });

  final List<TopomapPointValue> points;
  final TopomapColorScale scale;
  final TopomapValueBounds bounds;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _InterpolatedTopomapPainter(
                points: points,
                scale: scale,
                bounds: bounds,
                showLabels: showLabels,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InterpolatedTopomapPainter extends CustomPainter {
  const _InterpolatedTopomapPainter({
    required this.points,
    required this.scale,
    required this.bounds,
    required this.showLabels,
  });

  final List<TopomapPointValue> points;
  final TopomapColorScale scale;
  final TopomapValueBounds bounds;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (math.min(size.width, size.height) / 2) - 24;
    final double scalpRadius = radius * 0.84;
    final _ProjectedTopomapGeometry geometry = _projectGeometry(
      points,
      center,
      scalpRadius,
    );

    final Paint headOutlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF0B0D10)
        ..style = PaintingStyle.fill,
    );
    _paintInterpolatedField(canvas, center, radius, geometry);
    _paintHeadChrome(canvas, center, radius, headOutlinePaint);
    _paintElectrodes(canvas, geometry.points);
  }

  void _paintInterpolatedField(
    Canvas canvas,
    Offset center,
    double radius,
    _ProjectedTopomapGeometry geometry,
  ) {
    final double step = math.max(4.0, radius / 44.0);
    final double sampleRadius = step * 0.78;
    final double softeningDistance = radius * 0.14;
    final double softeningDistanceSquared =
        softeningDistance * softeningDistance;
    final Paint fieldPaint = Paint()..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(
          Rect.fromCircle(
            center: center,
            radius: radius - 2,
          ),
        ),
    );

    for (double y = center.dy - radius; y <= center.dy + radius; y += step) {
      for (double x = center.dx - radius; x <= center.dx + radius; x += step) {
        final Offset sample = Offset(x, y);
        final double radialDistance = (sample - center).distance;
        if (radialDistance > radius) {
          continue;
        }
        final double? value = _interpolatedFieldValue(
          sample,
          geometry.points,
          softeningDistanceSquared,
        );
        if (value == null) {
          continue;
        }
        final double edgeFade =
            1 - math.pow(radialDistance / radius, 2).toDouble();
        fieldPaint.color = topomapColorForValue(value, bounds, scale).withValues(
          alpha: (0.22 + (edgeFade * 0.38)).clamp(0.0, 0.6),
        );
        canvas.drawCircle(sample, sampleRadius, fieldPaint);
      }
    }

    canvas.restore();
  }

  double? _interpolatedFieldValue(
    Offset sample,
    List<_ProjectedPoint> points,
    double softeningDistanceSquared,
  ) {
    if (points.isEmpty) {
      return null;
    }
    double weightedSum = 0;
    double weightTotal = 0;
    for (final _ProjectedPoint point in points) {
      final Offset delta = sample - point.position;
      final double distanceSquared = (delta.dx * delta.dx) + (delta.dy * delta.dy);
      if (distanceSquared <= 1) {
        return point.value;
      }
      final double weight = 1 / (distanceSquared + softeningDistanceSquared);
      weightedSum += point.value * weight;
      weightTotal += weight;
    }
    if (weightTotal <= 0) {
      return null;
    }
    return weightedSum / weightTotal;
  }

  void _paintHeadChrome(
    Canvas canvas,
    Offset center,
    double radius,
    Paint headOutlinePaint,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.03)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, radius, headOutlinePaint);

    final Path nose = Path()
      ..moveTo(center.dx, center.dy - radius - 8)
      ..lineTo(center.dx - 10, center.dy - radius + 10)
      ..lineTo(center.dx + 10, center.dy - radius + 10)
      ..close();
    canvas.drawPath(
      nose,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );

    final Rect leftEar = Rect.fromCenter(
      center: Offset(center.dx - radius - 4, center.dy),
      width: 16,
      height: radius * 0.34,
    );
    final Rect rightEar = Rect.fromCenter(
      center: Offset(center.dx + radius + 4, center.dy),
      width: 16,
      height: radius * 0.34,
    );
    final Paint earPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawOval(leftEar, earPaint);
    canvas.drawOval(rightEar, earPaint);
    canvas.drawOval(leftEar, headOutlinePaint);
    canvas.drawOval(rightEar, headOutlinePaint);
  }

  void _paintElectrodes(Canvas canvas, List<_ProjectedPoint> points) {
    final Paint pointFillPaint = Paint()
      ..color = const Color(0xFF0F1217)
      ..style = PaintingStyle.fill;
    final Paint pointOutlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (final _ProjectedPoint point in points) {
      canvas.drawCircle(point.position, 6.5, pointFillPaint);
      canvas.drawCircle(point.position, 6.5, pointOutlinePaint);
      if (!showLabels) {
        continue;
      }
      final TextPainter labelPainter = TextPainter(
        text: TextSpan(
          text: point.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
          point.position.dx + 8,
          point.position.dy - (labelPainter.height / 2),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InterpolatedTopomapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.scale != scale ||
        oldDelegate.bounds != bounds ||
        oldDelegate.showLabels != showLabels;
  }
}

class _ProjectedPoint {
  const _ProjectedPoint({
    required this.label,
    required this.position,
    required this.value,
  });

  final String label;
  final Offset position;
  final double value;
}

class _ProjectedTopomapGeometry {
  const _ProjectedTopomapGeometry({
    required this.points,
  });

  final List<_ProjectedPoint> points;
}

_ProjectedTopomapGeometry _projectGeometry(
  List<TopomapPointValue> values,
  Offset center,
  double radius,
) {
  double maxExtent = 1.0;
  for (final TopomapPointValue point in values) {
    maxExtent = math.max(maxExtent, point.coordinate.x.abs());
    maxExtent = math.max(maxExtent, point.coordinate.y.abs());
  }
  final double scale = radius / maxExtent;

  return _ProjectedTopomapGeometry(
    points: values.map((TopomapPointValue point) {
      return _ProjectedPoint(
        label: point.label,
        position: Offset(
          center.dx + (point.coordinate.x * scale),
          center.dy - (point.coordinate.y * scale),
        ),
        value: point.value,
      );
    }).toList(growable: false),
  );
}
