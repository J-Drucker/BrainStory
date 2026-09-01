import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../nodes/channel_coordinates_node.dart';
import 'topomap_view.dart';

class IcaViewer extends StatefulWidget {
  const IcaViewer({super.key, required this.dataset, required this.onApply});

  final Dataset dataset;
  final Future<void> Function(Set<int> excludedComponents) onApply;

  @override
  State<IcaViewer> createState() => _IcaViewerState();
}

class _IcaViewerState extends State<IcaViewer> {
  static const List<double> _windowOptions = <double>[1, 2, 5, 10, 20, 30];
  final Set<int> _excluded = <int>{};
  bool _previewing = false;
  bool _applying = false;
  double _windowSeconds = 10;
  double _startFraction = 0;
  double _verticalScale = 1;

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
              'ICA did not converge after ${transform.iterationCount} iterations. Review is available, but exclusions cannot be applied.',
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
          key: const ValueKey<String>('ica-apply'),
          onPressed: !trustworthy || _excluded.isEmpty || _applying
              ? null
              : _apply,
          icon: _applying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Apply'),
        ),
        OutlinedButton.icon(
          key: const ValueKey<String>('ica-reset'),
          onPressed: () => setState(() {
            _excluded.clear();
            _previewing = false;
            _startFraction = 0;
            _verticalScale = 1;
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
        DropdownButton<double>(
          value: _windowSeconds,
          items: _windowOptions
              .map(
                (double seconds) => DropdownMenuItem<double>(
                  value: seconds,
                  child: Text('${seconds.toStringAsFixed(0)} s'),
                ),
              )
              .toList(growable: false),
          onChanged: (double? value) {
            if (value != null) setState(() => _windowSeconds = value);
          },
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
    final int windowSamples = math.max(
      1,
      math.min(sampleCount, (_windowSeconds * activations.sampleRate).round()),
    );
    final int maxStart = math.max(0, sampleCount - windowSamples);
    final int startSample = (maxStart * _startFraction).round();
    final int endSample = math.min(sampleCount, startSample + windowSamples);
    final List<List<double>> activationWindow = activations.channels
        .map((List<double> channel) => channel.sublist(startSample, endSample))
        .toList(growable: false);
    List<List<double>> traces = activationWindow;
    List<String> labels = transform.componentLabels;
    if (_previewing) {
      try {
        traces = transform.reconstructSensorChannels(
          activationWindow,
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
              child: Listener(
                key: const ValueKey<String>('ica-trace-viewport'),
                onPointerSignal: _handleTracePointerSignal,
                child: CustomPaint(
                  key: ValueKey<String>(
                    _previewing ? 'ica-preview-traces' : 'ica-component-traces',
                  ),
                  painter: _StackedTracePainter(
                    traces: traces,
                    labels: labels,
                    verticalScale: _verticalScale,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            if (maxStart > 0)
              Slider(
                value: _startFraction,
                onChanged: (double value) =>
                    setState(() => _startFraction = value),
              ),
            Text(
              '${(startSample / activations.sampleRate).toStringAsFixed(1)}-${(endSample / activations.sampleRate).toStringAsFixed(1)} s',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComponentGrid(
    MatrixTransformationData transform,
    int componentCount,
  ) {
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
              return _buildComponentTile(transform, index);
            },
          );
        },
      ),
    );
  }

  Widget _buildComponentTile(
    MatrixTransformationData transform,
    int componentIndex,
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
      onTap: () => setState(() {
        selected
            ? _excluded.remove(componentIndex)
            : _excluded.add(componentIndex);
      }),
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
                  value: selected,
                  onChanged: (bool? value) => setState(() {
                    value == true
                        ? _excluded.add(componentIndex)
                        : _excluded.remove(componentIndex);
                  }),
                ),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
              child: points.length >= 3
                  ? InterpolatedTopomap(
                      points: points,
                      bounds: _symmetricBounds(points),
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
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await widget.onApply(Set<int>.from(_excluded));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _handleTracePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed ||
        event.scrollDelta.dy == 0) {
      return;
    }
    setState(() {
      _verticalScale =
          (_verticalScale * (event.scrollDelta.dy < 0 ? 1.25 : 0.8)).clamp(
            0.125,
            16.0,
          );
    });
  }
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
    required this.verticalScale,
  });

  final List<List<double>> traces;
  final List<String> labels;
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
      ..color = const Color(0xFF63D4EF)
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
          style: const TextStyle(color: Colors.white70, fontSize: 10),
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
        oldDelegate.verticalScale != verticalScale;
  }
}
