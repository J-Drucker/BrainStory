import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/channel_coordinates_node.dart';
import 'raw_signal_browser.dart';
import 'topomap_view.dart';

class IcaViewer extends StatefulWidget {
  const IcaViewer({
    super.key,
    required this.dataset,
    required this.onCreateNode,
    this.initialExcludedComponents = const <int>{},
  });

  final Dataset dataset;
  final Future<void> Function(Set<int> excludedComponents) onCreateNode;
  final Set<int> initialExcludedComponents;

  @override
  State<IcaViewer> createState() => _IcaViewerState();
}

class _IcaViewerState extends State<IcaViewer> {
  static const List<double> _windowOptions = <double>[1, 2, 5, 10, 20, 30];
  static const List<double> _amplitudeOptions = <double>[
    0.25,
    0.5,
    1,
    2,
    4,
    8,
    16,
  ];
  static const List<double> _spacingOptions = <double>[
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    2,
  ];
  final Set<int> _excluded = <int>{};
  bool _previewing = false;
  bool _saving = false;
  bool _scaleToposSeparately = false;
  double _windowSeconds = 10;
  double _verticalScale = 1;
  double _spacing = 1;
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _excluded.addAll(widget.initialExcludedComponents);
    _horizontalController = ScrollController(keepScrollOffset: false);
    _verticalController = ScrollController(keepScrollOffset: false);
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IcaViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataset.id != widget.dataset.id) {
      _excluded
        ..clear()
        ..addAll(widget.initialExcludedComponents);
      _previewing = false;
      _verticalScale = 1;
      _spacing = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_horizontalController.hasClients) {
          _horizontalController.jumpTo(0);
        }
        if (_verticalController.hasClients) {
          _verticalController.jumpTo(0);
        }
      });
    }
  }

  MatrixTransformationData? get _transform =>
      widget.dataset.matrixTransformation;
  TimeSeriesData? get _activations => widget.dataset.timeSeries;

  @override
  Widget build(BuildContext context) {
    final MatrixTransformationData? transform = _transform;
    final TimeSeriesData? activations = _activations;
    if (transform == null ||
        activations == null ||
        activations.channels.isEmpty ||
        transform.mixingMatrix.isEmpty) {
      return const Center(
        child: Text('ICA activations or reconstruction metadata are missing.'),
      );
    }
    final int componentCount = math.min(
      transform.componentCount,
      activations.channelCount,
    );
    if (componentCount == 0) {
      return const Center(child: Text('No ICA components are available.'));
    }
    final bool trustworthy = transform.converged == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!trustworthy)
          Container(
            key: const ValueKey<String>('ica-nonconvergence-warning'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.14),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.7),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ICA did not converge after ${transform.iterationCount} iterations. Review is available, but an Apply ICA node cannot be created.',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        _buildControls(transform, componentCount, trustworthy),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth >= 1050) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: _buildTraceArea(transform, activations),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: math.min(480, constraints.maxWidth * 0.38),
                      child: _buildComponentGrid(transform, componentCount),
                    ),
                  ],
                );
              }
              return Column(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: _buildTraceArea(transform, activations),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 2,
                    child: _buildComponentGrid(transform, componentCount),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControls(
    MatrixTransformationData transform,
    int componentCount,
    bool trustworthy,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          key: const ValueKey<String>('ica-preview'),
          onPressed: () => setState(() => _previewing = !_previewing),
          icon: Icon(_previewing ? Icons.visibility_off : Icons.visibility),
          label: Text(_previewing ? 'Components' : 'Preview'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('ica-create-node'),
          onPressed: !trustworthy || _excluded.isEmpty || _saving
              ? null
              : _createNode,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Create Apply ICA node'),
        ),
        OutlinedButton.icon(
          key: const ValueKey<String>('ica-reset'),
          onPressed: () => setState(() {
            _excluded.clear();
            _previewing = false;
            _verticalScale = 1;
            _spacing = 1;
            if (_horizontalController.hasClients) {
              _horizontalController.jumpTo(0);
            }
          }),
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _excluded
              ..clear()
              ..addAll(
                List<int>.generate(componentCount, (int index) => index),
              );
          }),
          child: const Text('Select all'),
        ),
        TextButton(
          onPressed: () => setState(_excluded.clear),
          child: const Text('Clear'),
        ),
        const SizedBox(width: 6),
        Text(
          '${_excluded.length} excluded',
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        _scaleDropdown(
          label: 'Time',
          value: _windowSeconds,
          options: _windowOptions,
          format: (double value) => '${value.toStringAsFixed(0)} s',
          onChanged: (double value) => _windowSeconds = value,
        ),
        _scaleDropdown(
          label: 'Amplitude',
          value: _verticalScale,
          options: _amplitudeOptions,
          format: (double value) =>
              '${value.toStringAsFixed(value < 1 ? 2 : 0)}×',
          onChanged: (double value) => _verticalScale = value,
        ),
        _scaleDropdown(
          label: 'Spacing',
          value: _spacing,
          options: _spacingOptions,
          format: (double value) => '${value.toStringAsFixed(2)}×',
          onChanged: (double value) => _spacing = value,
        ),
        Tooltip(
          message:
              'Off uses one shared color scale so component strengths remain comparable.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                key: const ValueKey<String>('ica-separate-topo-scales'),
                value: _scaleToposSeparately,
                onChanged: (bool? value) =>
                    setState(() => _scaleToposSeparately = value ?? false),
              ),
              const Text('Scale each topo separately'),
            ],
          ),
        ),
        Text(
          '${transform.algorithm}  |  ${transform.iterationCount} iterations  |  tol ${transform.tolerance}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildTraceArea(
    MatrixTransformationData transform,
    TimeSeriesData activations,
  ) {
    final int sampleCount = activations.sampleCount;
    List<List<double>> traces = activations.channels;
    List<String> labels = transform.componentLabels;
    if (_previewing) {
      try {
        traces = transform.reconstructSensorChannels(
          activations.channels,
          excludedComponents: _excluded,
        );
        labels = transform.originalChannelLabels;
      } on Object {
        return const Center(
          child: Text('Sensor-space preview is unavailable.'),
        );
      }
    }
    if (labels.length != traces.length) {
      labels = List<String>.generate(
        traces.length,
        (int index) => _previewing ? 'Channel ${index + 1}' : 'IC ${index + 1}',
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _previewing
                  ? 'Sensor-space preview'
                  : 'Component activation traces',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double duration = sampleCount / activations.sampleRate;
                  final double canvasWidth = math.max(
                    constraints.maxWidth,
                    constraints.maxWidth * duration / _windowSeconds,
                  );
                  final double canvasHeight = math.max(
                    constraints.maxHeight,
                    traces.length * 52.0 * _spacing,
                  );
                  return Listener(
                    key: const ValueKey<String>('ica-trace-viewport'),
                    onPointerSignal: _handleTracePointerSignal,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (DragUpdateDetails details) =>
                          _scrollHorizontal(-details.delta.dx),
                      onDoubleTap: () {
                        if (_horizontalController.hasClients) {
                          _horizontalController.jumpTo(0);
                        }
                      },
                      child: Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: canvasHeight > constraints.maxHeight,
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          child: Scrollbar(
                            controller: _horizontalController,
                            thumbVisibility: canvasWidth > constraints.maxWidth,
                            notificationPredicate:
                                (ScrollNotification notice) =>
                                    notice.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              controller: _horizontalController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: canvasWidth,
                                height: canvasHeight,
                                child: CustomPaint(
                                  key: ValueKey<String>(
                                    _previewing
                                        ? 'ica-preview-traces'
                                        : 'ica-component-traces',
                                  ),
                                  painter: _StackedTracePainter(
                                    traces: traces,
                                    labels: labels,
                                    colors: _previewing
                                        ? null
                                        : List<Color>.generate(
                                            traces.length,
                                            _componentColor,
                                          ),
                                    excluded: _previewing
                                        ? const <int>{}
                                        : _excluded,
                                    verticalScale: _verticalScale,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Text(
              'Drag or scroll to pan. Ctrl-scroll changes amplitude; Ctrl-Shift-scroll changes time.',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scaleDropdown({
    required String label,
    required double value,
    required List<double> options,
    required String Function(double value) format,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('$label: ', style: const TextStyle(color: Colors.white70)),
        DropdownButton<double>(
          value: value,
          items: options
              .map(
                (double option) => DropdownMenuItem<double>(
                  value: option,
                  child: Text(format(option)),
                ),
              )
              .toList(growable: false),
          onChanged: (double? next) {
            if (next != null) setState(() => onChanged(next));
          },
        ),
      ],
    );
  }

  Widget _buildComponentGrid(
    MatrixTransformationData transform,
    int componentCount,
  ) {
    final TopomapValueBounds sharedBounds = _sharedTopomapBounds(
      transform,
      componentCount,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = constraints.maxWidth >= 420 ? 2 : 1;
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: columns == 1 ? 1.65 : 0.86,
            ),
            itemCount: componentCount,
            itemBuilder: (BuildContext context, int index) {
              return _buildComponentTile(transform, index, sharedBounds);
            },
          );
        },
      ),
    );
  }

  Widget _buildComponentTile(
    MatrixTransformationData transform,
    int componentIndex,
    TopomapValueBounds sharedBounds,
  ) {
    final String label = componentIndex < transform.componentLabels.length
        ? transform.componentLabels[componentIndex]
        : 'IC ${componentIndex + 1}';
    final double? energy = componentIndex < transform.componentEnergies.length
        ? transform.componentEnergies[componentIndex]
        : null;
    final List<TopomapPointValue> points = _componentTopomapPoints(
      transform,
      componentIndex,
    );
    final bool selected = _excluded.contains(componentIndex);
    return InkWell(
      key: ValueKey<String>('ica-component-$componentIndex'),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.redAccent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.035),
          border: Border.all(
            color: selected
                ? Colors.redAccent
                : Colors.white.withValues(alpha: 0.12),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Checkbox(
                  key: ValueKey<String>(
                    'ica-component-checkbox-$componentIndex',
                  ),
                  value: selected,
                  onChanged: (bool? value) => setState(() {
                    value == true
                        ? _excluded.add(componentIndex)
                        : _excluded.remove(componentIndex);
                  }),
                ),
                Expanded(
                  child: InkWell(
                    key: ValueKey<String>(
                      'ica-component-label-$componentIndex',
                    ),
                    onTap: () => _toggleComponent(componentIndex),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white54
                              : _componentColor(componentIndex),
                        ),
                      ),
                    ),
                  ),
                ),
                if (energy != null)
                  Text(
                    '${(energy * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
              ],
            ),
            Expanded(
              child: InkWell(
                key: ValueKey<String>('ica-component-topo-$componentIndex'),
                onTap: () => _toggleComponent(componentIndex),
                child: points.length >= 3
                    ? InterpolatedTopomap(
                        points: points,
                        bounds: _scaleToposSeparately
                            ? _symmetricBounds(points)
                            : sharedBounds,
                        scale: TopomapColorScale(
                          colors: const <Color>[
                            Color(0xFF315A71),
                            Color(0xFF34363A),
                            Color(0xFF8A493F),
                          ],
                        ),
                        showLabels: false,
                        sampleDensity: 0.65,
                      )
                    : const Center(
                        child: Text(
                          'Coordinates unavailable',
                          key: ValueKey<String>('ica-missing-coordinates'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createNode() async {
    setState(() => _saving = true);
    try {
      await widget.onCreateNode(Set<int>.from(_excluded));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleComponent(int componentIndex) {
    setState(() {
      _excluded.contains(componentIndex)
          ? _excluded.remove(componentIndex)
          : _excluded.add(componentIndex);
    });
  }

  Color _componentColor(int index) {
    final int value =
        rawSignalChannelPalette[index % rawSignalChannelPalette.length]
            .toARGB32();
    return Color(
      0xFF000000 |
          ((255 - ((value >> 16) & 0xFF)) << 16) |
          ((255 - ((value >> 8) & 0xFF)) << 8) |
          (255 - (value & 0xFF)),
    );
  }

  void _scrollHorizontal(double delta) {
    if (!_horizontalController.hasClients) return;
    _horizontalController.jumpTo(
      (_horizontalController.offset + delta).clamp(
        0.0,
        _horizontalController.position.maxScrollExtent,
      ),
    );
  }

  void _handleTracePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final bool control = HardwareKeyboard.instance.isControlPressed;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    if (control && shift && event.scrollDelta.dy != 0) {
      _stepWindowSeconds(event.scrollDelta.dy < 0 ? -1 : 1);
    } else if (control && event.scrollDelta.dy != 0) {
      _stepAmplitude(event.scrollDelta.dy < 0 ? 1 : -1);
    } else {
      final double delta =
          event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      _scrollHorizontal(delta);
    }
  }

  void _stepWindowSeconds(int direction) {
    int nearest = 0;
    double distance = double.infinity;
    for (int index = 0; index < _windowOptions.length; index++) {
      final double candidate = (_windowOptions[index] - _windowSeconds).abs();
      if (candidate < distance) {
        distance = candidate;
        nearest = index;
      }
    }
    setState(() {
      _windowSeconds =
          _windowOptions[(nearest + direction).clamp(
            0,
            _windowOptions.length - 1,
          )];
    });
  }

  void _stepAmplitude(int direction) {
    final int current = _amplitudeOptions.indexOf(_verticalScale);
    setState(() {
      _verticalScale =
          _amplitudeOptions[(current + direction).clamp(
            0,
            _amplitudeOptions.length - 1,
          )];
    });
  }
}

TopomapValueBounds _sharedTopomapBounds(
  MatrixTransformationData transform,
  int componentCount,
) {
  double maximum = 0;
  for (int component = 0; component < componentCount; component++) {
    for (final TopomapPointValue point in _componentTopomapPoints(
      transform,
      component,
    )) {
      maximum = math.max(maximum, point.value.abs());
    }
  }
  if (maximum == 0) maximum = 1;
  return TopomapValueBounds(min: -maximum, max: maximum);
}

List<TopomapPointValue> _componentTopomapPoints(
  MatrixTransformationData transform,
  int componentIndex,
) {
  final List<TopomapPointValue> points = <TopomapPointValue>[];
  for (
    int channel = 0;
    channel < transform.originalChannelLabels.length;
    channel++
  ) {
    if (channel >= transform.mixingMatrix.length ||
        componentIndex >= transform.mixingMatrix[channel].length) {
      continue;
    }
    final String label = transform.originalChannelLabels[channel];
    final ChannelCoordinate? coordinate =
        ChannelCoordinatesNodeType.coordinateForChannelLabel(
          transform.originalChannelCoordinates,
          label,
        );
    if (coordinate == null) continue;
    points.add(
      TopomapPointValue(
        label: label,
        coordinate: coordinate,
        value: transform.mixingMatrix[channel][componentIndex],
      ),
    );
  }
  return points;
}

TopomapValueBounds _symmetricBounds(List<TopomapPointValue> points) {
  double maximum = 0;
  for (final TopomapPointValue point in points) {
    maximum = math.max(maximum, point.value.abs());
  }
  if (maximum == 0) maximum = 1;
  return TopomapValueBounds(min: -maximum, max: maximum);
}

class _StackedTracePainter extends CustomPainter {
  const _StackedTracePainter({
    required this.traces,
    required this.labels,
    required this.colors,
    required this.excluded,
    required this.verticalScale,
  });

  final List<List<double>> traces;
  final List<String> labels;
  final List<Color>? colors;
  final Set<int> excluded;
  final double verticalScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (traces.isEmpty || size.width <= 0 || size.height <= 0) return;
    const double labelWidth = 58;
    final double plotWidth = math.max(1, size.width - labelWidth);
    final double rowHeight = size.height / traces.length;
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final Paint tracePaint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (int row = 0; row < traces.length; row++) {
      final double centerY = (row + 0.5) * rowHeight;
      canvas.drawLine(
        Offset(labelWidth, centerY),
        Offset(size.width, centerY),
        gridPaint,
      );
      final TextPainter labelPainter = TextPainter(
        text: TextSpan(
          text: row < labels.length ? labels[row] : '${row + 1}',
          style: TextStyle(
            color: excluded.contains(row)
                ? Colors.white24
                : colors?[row] ?? Colors.white70,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: labelWidth - 6);
      labelPainter.paint(
        canvas,
        Offset(2, centerY - (labelPainter.height / 2)),
      );
      final List<double> values = traces[row];
      if (values.length < 2) continue;
      tracePaint.color = excluded.contains(row)
          ? Colors.white.withValues(alpha: 0.16)
          : colors?[row] ?? const Color(0xFF63D4EF);
      double maximum = 0;
      for (final double value in values) {
        if (value.isFinite) maximum = math.max(maximum, value.abs());
      }
      if (maximum == 0) maximum = 1;
      final int columns = math.max(2, plotWidth.floor());
      final Path path = Path();
      for (int column = 0; column < columns; column++) {
        final int sample = ((column / (columns - 1)) * (values.length - 1))
            .round();
        final double x = labelWidth + (column / (columns - 1)) * plotWidth;
        final double y =
            centerY -
            (values[sample] / maximum * verticalScale).clamp(-1.0, 1.0) *
                rowHeight *
                0.38;
        column == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, tracePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StackedTracePainter oldDelegate) {
    return oldDelegate.traces != traces ||
        oldDelegate.labels != labels ||
        oldDelegate.colors != colors ||
        oldDelegate.excluded != excluded ||
        oldDelegate.verticalScale != verticalScale;
  }
}
