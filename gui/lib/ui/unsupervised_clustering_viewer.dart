import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';

class UnsupervisedClusteringViewer extends StatefulWidget {
  const UnsupervisedClusteringViewer({super.key, required this.dataset});

  final Dataset dataset;

  @override
  State<UnsupervisedClusteringViewer> createState() =>
      _UnsupervisedClusteringViewerState();
}

class _UnsupervisedClusteringViewerState
    extends State<UnsupervisedClusteringViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sliceController =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..addListener(() {
          if (_playing && mounted) setState(() {});
        });
  double _yaw = -0.65;
  double _pitch = -0.35;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Offset? _hoverPosition;
  bool _showObservations = true;
  bool _useFourthComponent = false;
  bool _playing = false;
  double _manualSlicePosition = 0.5;
  bool _secondaryDragging = false;

  GaussianMixtureData? get _model => widget.dataset.gaussianMixture;
  GaussianMixtureProjectionData? get _projection => _model?.projection;

  @override
  void dispose() {
    _sliceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GaussianMixtureData? model = _model;
    final GaussianMixtureProjectionData? projection = _projection;
    if (model == null ||
        projection == null ||
        projection.observations.isEmpty) {
      return const Center(
        child: Text(
          'Run Gaussian Mixture again to calculate its clustering projection.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final int dimensionCount = projection.dimensionCount;
    final bool canSliceFourth = dimensionCount >= 4;
    final _Range fourthRange = canSliceFourth
        ? _rangeOf(projection.observations.map((List<double> row) => row[3]))
        : const _Range(0, 0);
    final double slicePosition = _playing
        ? _pingPong(_sliceController.value)
        : _manualSlicePosition;
    final double fourthValue = fourthRange.valueAt(slicePosition);

    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: <Widget>[
          _buildToolbar(
            model: model,
            projection: projection,
            canSliceFourth: canSliceFourth,
          ),
          if (_useFourthComponent && canSliceFourth)
            _buildSliceControls(
              fourthRange: fourthRange,
              slicePosition: slicePosition,
              fourthValue: fourthValue,
            ),
          Expanded(
            child: Listener(
              onPointerDown: (PointerDownEvent event) {
                if ((event.buttons & kSecondaryMouseButton) != 0) {
                  _secondaryDragging = true;
                }
              },
              onPointerMove: (PointerMoveEvent event) {
                if (_secondaryDragging &&
                    (event.buttons & kSecondaryMouseButton) != 0) {
                  setState(() => _pan += event.delta);
                }
              },
              onPointerUp: (_) => _secondaryDragging = false,
              onPointerCancel: (_) => _secondaryDragging = false,
              onPointerSignal: (PointerSignalEvent event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    _zoom = (_zoom * math.exp(-event.scrollDelta.dy * 0.0015))
                        .clamp(0.35, 8.0);
                  });
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                onHover: (PointerHoverEvent event) {
                  setState(() => _hoverPosition = event.localPosition);
                },
                onExit: (_) => setState(() => _hoverPosition = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _resetView,
                  onScaleUpdate: (ScaleUpdateDetails details) {
                    setState(() {
                      if (details.pointerCount > 1) {
                        _zoom = (_zoom * details.scale).clamp(0.35, 8.0);
                        _pan += details.focalPointDelta;
                      } else {
                        _yaw += details.focalPointDelta.dx * 0.008;
                        _pitch = (_pitch + details.focalPointDelta.dy * 0.008)
                            .clamp(-math.pi / 2, math.pi / 2);
                      }
                    });
                  },
                  child: CustomPaint(
                    key: const ValueKey<String>('unsupervised-clustering-3d'),
                    painter: _ClusteringPainter(
                      model: model,
                      projection: projection,
                      yaw: _yaw,
                      pitch: _pitch,
                      zoom: _zoom,
                      pan: _pan,
                      showObservations: _showObservations,
                      fourthValue: _useFourthComponent && canSliceFourth
                          ? fourthValue
                          : null,
                      fourthRange: fourthRange,
                      hoverPosition: _hoverPosition,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar({
    required GaussianMixtureData model,
    required GaussianMixtureProjectionData projection,
    required bool canSliceFourth,
  }) {
    final String explained = projection.explainedVarianceRatios
        .take(3)
        .map((double value) => '${(value * 100).toStringAsFixed(1)}%')
        .join(' / ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${model.componentCount} Gaussian components',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'PC1 / PC2 / PC3 variance: $explained',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Show observations',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.scatter_plot, size: 18, color: Colors.white70),
                Switch(
                  key: const ValueKey<String>('clustering-observations-toggle'),
                  value: _showObservations,
                  onChanged: (bool value) {
                    setState(() => _showObservations = value);
                  },
                ),
              ],
            ),
          ),
          if (canSliceFourth)
            Tooltip(
              message: 'Use PC4 slice',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('4D', style: TextStyle(color: Colors.white70)),
                  Switch(
                    key: const ValueKey<String>('clustering-pc4-toggle'),
                    value: _useFourthComponent,
                    onChanged: (bool value) {
                      setState(() {
                        _useFourthComponent = value;
                        if (!value) _stopPlayback();
                      });
                    },
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: 'Reset view',
            onPressed: _resetView,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
    );
  }

  Widget _buildSliceControls({
    required _Range fourthRange,
    required double slicePosition,
    required double fourthValue,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('clustering-pc4-play'),
            tooltip: _playing ? 'Pause PC4 sweep' : 'Play PC4 sweep',
            onPressed: () {
              setState(() {
                if (_playing) {
                  _stopPlayback();
                } else {
                  _playing = true;
                  _sliceController.repeat();
                }
              });
            },
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          Text(
            'PC4 ${fourthRange.minimum.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          Expanded(
            child: Slider(
              key: const ValueKey<String>('clustering-pc4-slider'),
              value: slicePosition,
              onChanged: (double value) {
                setState(() {
                  _stopPlayback();
                  _manualSlicePosition = value;
                });
              },
            ),
          ),
          Text(
            fourthRange.maximum.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 76,
            child: Text(
              fourthValue.toStringAsFixed(2),
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _stopPlayback() {
    _playing = false;
    _sliceController.stop();
  }

  void _resetView() {
    setState(() {
      _yaw = -0.65;
      _pitch = -0.35;
      _zoom = 1;
      _pan = Offset.zero;
    });
  }
}

class _ClusteringPainter extends CustomPainter {
  const _ClusteringPainter({
    required this.model,
    required this.projection,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
    required this.showObservations,
    required this.fourthValue,
    required this.fourthRange,
    required this.hoverPosition,
  });

  final GaussianMixtureData model;
  final GaussianMixtureProjectionData projection;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset pan;
  final bool showObservations;
  final double? fourthValue;
  final _Range fourthRange;
  final Offset? hoverPosition;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final List<_GaussianSlice> slices = _gaussianSlices();
    final _SceneTransform transform = _SceneTransform.fromData(
      size: size,
      observations: projection.observations,
      slices: slices,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
      pan: pan,
    );
    _drawAxes(canvas, transform);
    _drawGaussians(canvas, transform, slices);
    final List<_ProjectedObservation> points = showObservations
        ? _drawObservations(canvas, transform)
        : const <_ProjectedObservation>[];
    _drawLegend(canvas, size);
    _drawHover(canvas, size, points);
  }

  List<_GaussianSlice> _gaussianSlices() {
    return List<_GaussianSlice>.generate(model.componentCount, (int component) {
      final List<double> sourceMean =
          component < projection.componentMeans.length
          ? projection.componentMeans[component]
          : const <double>[];
      final List<List<double>> sourceCovariance =
          component < projection.componentCovariances.length
          ? projection.componentCovariances[component]
          : const <List<double>>[];
      final List<double> mean = List<double>.generate(
        3,
        (int index) => index < sourceMean.length ? sourceMean[index] : 0,
      );
      final List<List<double>> covariance = List<List<double>>.generate(
        3,
        (int row) => List<double>.generate(
          3,
          (int column) =>
              row < sourceCovariance.length &&
                  column < sourceCovariance[row].length
              ? sourceCovariance[row][column]
              : row == column
              ? 1.0e-6
              : 0,
        ),
      );
      double visibility = 1;
      double radiusScale = 1;
      if (fourthValue != null &&
          sourceMean.length >= 4 &&
          sourceCovariance.length >= 4 &&
          sourceCovariance.every((List<double> row) => row.length >= 4)) {
        final double variance4 = sourceCovariance[3][3].abs().clamp(
          1.0e-9,
          double.infinity,
        );
        final double delta = fourthValue! - sourceMean[3];
        final double standardizedSquared = delta * delta / variance4;
        visibility = math.exp(-0.5 * standardizedSquared);
        radiusScale = math.sqrt(math.max(0, 1 - standardizedSquared / 4));
        for (int row = 0; row < 3; row++) {
          mean[row] += sourceCovariance[row][3] / variance4 * delta;
          for (int column = 0; column < 3; column++) {
            covariance[row][column] -=
                sourceCovariance[row][3] *
                sourceCovariance[3][column] /
                variance4;
          }
        }
      }
      return _GaussianSlice(
        mean: _Vec3(mean[0], mean[1], mean[2]),
        covariance: covariance,
        radiusScale: radiusScale,
        visibility: visibility,
        color: _clusterColor(component, model.componentCount),
      );
    }, growable: false);
  }

  void _drawAxes(Canvas canvas, _SceneTransform transform) {
    const List<_Vec3> axes = <_Vec3>[
      _Vec3(1, 0, 0),
      _Vec3(0, 1, 0),
      _Vec3(0, 0, 1),
    ];
    const List<String> labels = <String>['PC1', 'PC2', 'PC3'];
    final Paint axisPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final _ScreenPoint origin = transform.project(const _Vec3(0, 0, 0));
    for (int index = 0; index < axes.length; index++) {
      final _ScreenPoint end = transform.project(axes[index]);
      canvas.drawLine(origin.offset, end.offset, axisPaint);
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, end.offset + const Offset(4, -6));
    }
  }

  void _drawGaussians(
    Canvas canvas,
    _SceneTransform transform,
    List<_GaussianSlice> slices,
  ) {
    final List<_MeshTriangle> triangles = <_MeshTriangle>[];
    for (final _GaussianSlice slice in slices) {
      if (slice.visibility < 0.015 || slice.radiusScale <= 0.01) continue;
      final List<List<_Vec3>> rings = _ellipsoidRings(slice);
      for (int latitude = 0; latitude < rings.length - 1; latitude++) {
        for (
          int longitude = 0;
          longitude < rings[latitude].length;
          longitude++
        ) {
          final int next = (longitude + 1) % rings[latitude].length;
          final _ScreenPoint a = transform.project(rings[latitude][longitude]);
          final _ScreenPoint b = transform.project(rings[latitude][next]);
          final _ScreenPoint c = transform.project(rings[latitude + 1][next]);
          final _ScreenPoint d = transform.project(
            rings[latitude + 1][longitude],
          );
          triangles
            ..add(_MeshTriangle(a, b, c, slice))
            ..add(_MeshTriangle(a, c, d, slice));
        }
      }
    }
    triangles.sort(
      (_MeshTriangle a, _MeshTriangle b) => a.depth.compareTo(b.depth),
    );
    for (final _MeshTriangle triangle in triangles) {
      final Path path = Path()
        ..moveTo(triangle.a.offset.dx, triangle.a.offset.dy)
        ..lineTo(triangle.b.offset.dx, triangle.b.offset.dy)
        ..lineTo(triangle.c.offset.dx, triangle.c.offset.dy)
        ..close();
      final double alpha = (0.055 * triangle.slice.visibility).clamp(0, 0.09);
      canvas.drawPath(
        path,
        Paint()
          ..color = triangle.slice.color.withValues(alpha: alpha)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = triangle.slice.color.withValues(
            alpha: (0.12 * triangle.slice.visibility).clamp(0, 0.18),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.45,
      );
    }
  }

  List<_ProjectedObservation> _drawObservations(
    Canvas canvas,
    _SceneTransform transform,
  ) {
    final List<_ProjectedObservation> points = <_ProjectedObservation>[];
    final double sliceBandwidth = math.max(fourthRange.span * 0.08, 1.0e-6);
    for (int index = 0; index < projection.observations.length; index++) {
      final List<double> row = projection.observations[index];
      if (row.isEmpty) continue;
      double visibility = 1;
      if (fourthValue != null && row.length >= 4) {
        final double delta = (row[3] - fourthValue!) / sliceBandwidth;
        visibility = math.exp(-0.5 * delta * delta);
      }
      if (visibility < 0.025) continue;
      final _Vec3 value = _Vec3(
        row[0],
        row.length > 1 ? row[1] : 0,
        row.length > 2 ? row[2] : 0,
      );
      final _ScreenPoint point = transform.project(value);
      final int cluster = index < model.assignments.length
          ? model.assignments[index]
          : 0;
      final double probability =
          index < model.probabilities.length &&
              cluster >= 0 &&
              cluster < model.probabilities[index].length
          ? model.probabilities[index][cluster]
          : 0;
      points.add(
        _ProjectedObservation(
          index: index,
          cluster: cluster,
          probability: probability,
          point: point,
          visibility: visibility,
        ),
      );
    }
    points.sort(
      (_ProjectedObservation a, _ProjectedObservation b) =>
          a.point.depth.compareTo(b.point.depth),
    );
    for (final _ProjectedObservation observation in points) {
      final Color color = _clusterPointColor(
        observation.cluster,
        model.componentCount,
      );
      canvas.drawCircle(
        observation.point.offset,
        1.7,
        Paint()
          ..color = color.withValues(
            alpha: observation.visibility.clamp(0.08, 1),
          ),
      );
    }
    return points;
  }

  void _drawLegend(Canvas canvas, Size size) {
    const double swatch = 8;
    const double gap = 7;
    final double width = math.min(size.width - 24, model.componentCount * 74.0);
    double x = (size.width - width) / 2;
    final double y = size.height - 24;
    for (int component = 0; component < model.componentCount; component++) {
      canvas.drawCircle(
        Offset(x + swatch / 2, y),
        swatch / 2,
        Paint()..color = _clusterPointColor(component, model.componentCount),
      );
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: ' ${component + 1}',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + swatch + 2, y - label.height / 2));
      x += label.width + swatch + gap;
    }
  }

  void _drawHover(
    Canvas canvas,
    Size size,
    List<_ProjectedObservation> points,
  ) {
    final Offset? hover = hoverPosition;
    if (hover == null || points.isEmpty) return;
    _ProjectedObservation? nearest;
    double distance = 10;
    for (final _ProjectedObservation point in points) {
      final double candidate = (point.point.offset - hover).distance;
      if (candidate < distance) {
        distance = candidate;
        nearest = point;
      }
    }
    if (nearest == null) return;
    final TextPainter text = TextPainter(
      text: TextSpan(
        text:
            'Observation ${nearest.index + 1}\nCluster ${nearest.cluster + 1}  ${(nearest.probability * 100).toStringAsFixed(1)}%',
        style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Size boxSize = Size(text.width + 16, text.height + 12);
    final Offset desired = nearest.point.offset + const Offset(10, -10);
    final Offset position = Offset(
      desired.dx.clamp(4, math.max(4, size.width - boxSize.width - 4)),
      desired.dy.clamp(4, math.max(4, size.height - boxSize.height - 4)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(position & boxSize, const Radius.circular(4)),
      Paint()..color = const Color(0xE6212329),
    );
    text.paint(canvas, position + const Offset(8, 6));
  }

  List<List<_Vec3>> _ellipsoidRings(_GaussianSlice slice) {
    final List<List<double>> l = _cholesky3(slice.covariance);
    const int latitudes = 8;
    const int longitudes = 16;
    return List<List<_Vec3>>.generate(latitudes + 1, (int latitude) {
      final double phi = -math.pi / 2 + math.pi * latitude / latitudes;
      return List<_Vec3>.generate(longitudes, (int longitude) {
        final double theta = 2 * math.pi * longitude / longitudes;
        final List<double> sphere = <double>[
          math.cos(phi) * math.cos(theta),
          math.sin(phi),
          math.cos(phi) * math.sin(theta),
        ];
        final double scale = 2 * slice.radiusScale;
        return slice.mean +
            _Vec3(
              scale * (l[0][0] * sphere[0]),
              scale * (l[1][0] * sphere[0] + l[1][1] * sphere[1]),
              scale *
                  (l[2][0] * sphere[0] +
                      l[2][1] * sphere[1] +
                      l[2][2] * sphere[2]),
            );
      }, growable: false);
    }, growable: false);
  }

  List<List<double>> _cholesky3(List<List<double>> covariance) {
    final List<List<double>> l = List<List<double>>.generate(
      3,
      (_) => List<double>.filled(3, 0),
    );
    for (int row = 0; row < 3; row++) {
      for (int column = 0; column <= row; column++) {
        double value = covariance[row][column];
        for (int inner = 0; inner < column; inner++) {
          value -= l[row][inner] * l[column][inner];
        }
        if (row == column) {
          l[row][column] = math.sqrt(math.max(value, 1.0e-9));
        } else {
          l[row][column] = value / math.max(l[column][column], 1.0e-9);
        }
      }
    }
    return l;
  }

  @override
  bool shouldRepaint(covariant _ClusteringPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.projection != projection ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.zoom != zoom ||
      oldDelegate.pan != pan ||
      oldDelegate.showObservations != showObservations ||
      oldDelegate.fourthValue != fourthValue ||
      oldDelegate.hoverPosition != hoverPosition;
}

class _SceneTransform {
  const _SceneTransform({
    required this.size,
    required this.center,
    required this.dataScale,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
  });

  factory _SceneTransform.fromData({
    required Size size,
    required List<List<double>> observations,
    required List<_GaussianSlice> slices,
    required double yaw,
    required double pitch,
    required double zoom,
    required Offset pan,
  }) {
    final List<_Vec3> values = <_Vec3>[
      for (final List<double> row in observations)
        _Vec3(
          row.isNotEmpty ? row[0] : 0,
          row.length > 1 ? row[1] : 0,
          row.length > 2 ? row[2] : 0,
        ),
      for (final _GaussianSlice slice in slices) ...<_Vec3>[
        slice.mean,
        _Vec3(slice.mean.x + _axisExtent(slice, 0), slice.mean.y, slice.mean.z),
        _Vec3(slice.mean.x - _axisExtent(slice, 0), slice.mean.y, slice.mean.z),
        _Vec3(slice.mean.x, slice.mean.y + _axisExtent(slice, 1), slice.mean.z),
        _Vec3(slice.mean.x, slice.mean.y - _axisExtent(slice, 1), slice.mean.z),
        _Vec3(slice.mean.x, slice.mean.y, slice.mean.z + _axisExtent(slice, 2)),
        _Vec3(slice.mean.x, slice.mean.y, slice.mean.z - _axisExtent(slice, 2)),
      ],
    ];
    if (values.isEmpty) values.add(const _Vec3(0, 0, 0));
    double minX = values.first.x;
    double maxX = values.first.x;
    double minY = values.first.y;
    double maxY = values.first.y;
    double minZ = values.first.z;
    double maxZ = values.first.z;
    for (final _Vec3 value in values.skip(1)) {
      minX = math.min(minX, value.x);
      maxX = math.max(maxX, value.x);
      minY = math.min(minY, value.y);
      maxY = math.max(maxY, value.y);
      minZ = math.min(minZ, value.z);
      maxZ = math.max(maxZ, value.z);
    }
    final _Vec3 center = _Vec3(
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      (minZ + maxZ) / 2,
    );
    final double span = math.max(
      1.0e-6,
      math.max(maxX - minX, math.max(maxY - minY, maxZ - minZ)),
    );
    return _SceneTransform(
      size: size,
      center: center,
      dataScale: 2 / span,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
      pan: pan,
    );
  }

  final Size size;
  final _Vec3 center;
  final double dataScale;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset pan;

  static double _axisExtent(_GaussianSlice slice, int axis) {
    if (axis >= slice.covariance.length ||
        axis >= slice.covariance[axis].length) {
      return 0;
    }
    return 2 *
        slice.radiusScale *
        math.sqrt(math.max(0, slice.covariance[axis][axis]));
  }

  _ScreenPoint project(_Vec3 source) {
    final _Vec3 value = (source - center) * dataScale;
    final double cosYaw = math.cos(yaw);
    final double sinYaw = math.sin(yaw);
    final double x1 = cosYaw * value.x + sinYaw * value.z;
    final double z1 = -sinYaw * value.x + cosYaw * value.z;
    final double cosPitch = math.cos(pitch);
    final double sinPitch = math.sin(pitch);
    final double y2 = cosPitch * value.y - sinPitch * z1;
    final double z2 = sinPitch * value.y + cosPitch * z1;
    final double perspective = 4 / (4 - z2.clamp(-2.5, 2.5));
    final double sceneSize = math.min(size.width, size.height) * 0.38 * zoom;
    return _ScreenPoint(
      Offset(
        size.width / 2 + pan.dx + x1 * sceneSize * perspective,
        size.height / 2 + pan.dy - y2 * sceneSize * perspective,
      ),
      z2,
    );
  }
}

class _GaussianSlice {
  const _GaussianSlice({
    required this.mean,
    required this.covariance,
    required this.radiusScale,
    required this.visibility,
    required this.color,
  });

  final _Vec3 mean;
  final List<List<double>> covariance;
  final double radiusScale;
  final double visibility;
  final Color color;
}

class _MeshTriangle {
  const _MeshTriangle(this.a, this.b, this.c, this.slice);

  final _ScreenPoint a;
  final _ScreenPoint b;
  final _ScreenPoint c;
  final _GaussianSlice slice;

  double get depth => (a.depth + b.depth + c.depth) / 3;
}

class _ProjectedObservation {
  const _ProjectedObservation({
    required this.index,
    required this.cluster,
    required this.probability,
    required this.point,
    required this.visibility,
  });

  final int index;
  final int cluster;
  final double probability;
  final _ScreenPoint point;
  final double visibility;
}

class _ScreenPoint {
  const _ScreenPoint(this.offset, this.depth);

  final Offset offset;
  final double depth;
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _Vec3 operator +(_Vec3 other) => _Vec3(x + other.x, y + other.y, z + other.z);
  _Vec3 operator -(_Vec3 other) => _Vec3(x - other.x, y - other.y, z - other.z);
  _Vec3 operator *(double scalar) => _Vec3(x * scalar, y * scalar, z * scalar);
}

class _Range {
  const _Range(this.minimum, this.maximum);

  final double minimum;
  final double maximum;

  double get span => maximum - minimum;
  double valueAt(double position) => minimum + span * position.clamp(0, 1);
}

_Range _rangeOf(Iterable<double> values) {
  final List<double> finite = values
      .where((double value) => value.isFinite)
      .toList();
  if (finite.isEmpty) return const _Range(0, 0);
  final double minimum = finite.reduce(math.min);
  final double maximum = finite.reduce(math.max);
  if (minimum == maximum) return _Range(minimum - 0.5, maximum + 0.5);
  return _Range(minimum, maximum);
}

double _pingPong(double value) => value <= 0.5 ? value * 2 : (1 - value) * 2;

Color _clusterColor(int index, int count) {
  final double position = count <= 1 ? 0.5 : index / (count - 1);
  return HSVColor.fromAHSV(1, position * 275, 0.62, 0.72).toColor();
}

Color _clusterPointColor(int index, int count) {
  final double position = count <= 1 ? 0.5 : index / (count - 1);
  return HSVColor.fromAHSV(1, position * 275, 0.72, 1).toColor();
}
