import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../nodes/interactive_artifact_detection_node.dart';
import 'topomap_view.dart';

Color artifactTemplateColor(String label) {
  switch (label) {
    case 'blink':
      return const Color(0xFFFF4D8D);
    case 'saccade_vertical':
      return const Color(0xFFFF8C42);
    case 'saccade_horizontal':
      return const Color(0xFFFFC145);
    case 'motion':
      return const Color(0xFFFF5A36);
    default:
      return const Color(0xFFFF9F1C);
  }
}

class ArtifactTemplatePreview extends StatelessWidget {
  const ArtifactTemplatePreview({
    super.key,
    required this.templates,
    required this.channelLabels,
    required this.channelCoordinates,
    required this.pixelsPerSecond,
  });

  final List<ArtifactTemplateSummary> templates;
  final List<String> channelLabels;
  final Map<String, ChannelCoordinate> channelCoordinates;
  final double pixelsPerSecond;

  @override
  Widget build(BuildContext context) {
    final List<List<TopomapPointValue>> templatePointSets = templates
        .map(
          (ArtifactTemplateSummary template) => _templateTopomapPoints(
            template,
            channelLabels: channelLabels,
            channelCoordinates: channelCoordinates,
          ),
        )
        .toList(growable: false);
    final bool hasTopomapData = templatePointSets.any(
      (List<TopomapPointValue> points) => points.length >= 3,
    );
    final TopomapColorScale sharedScale = _artifactTemplateTopomapScale();
    final TopomapValueBounds sharedBounds = _artifactTemplateSharedBounds(
      templatePointSets,
    );
    final double waveformWidth = templates
        .map(
          (ArtifactTemplateSummary template) =>
              (template.durationMicros / 1000000.0) * pixelsPerSecond,
        )
        .fold<double>(0, math.max)
        .clamp(80.0, 280.0);

    return Container(
      width: hasTopomapData ? double.infinity : waveformWidth + 20,
      height: hasTopomapData ? 308 : 132,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hasTopomapData
                ? 'Current template topomap'
                : 'Current template summary',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: hasTopomapData
                ? LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final double cardWidth = templates.length == 1
                          ? constraints.maxWidth
                          : (constraints.maxWidth * 0.78)
                                .clamp(220.0, 260.0)
                                .toDouble();
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: templates.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final ArtifactTemplateSummary template =
                              templates[index];
                          final List<TopomapPointValue> points =
                              templatePointSets[index];
                          if (points.length < 3) {
                            return SizedBox(
                              width: cardWidth,
                              child: _ArtifactTemplateWaveformFallback(
                                templates: <ArtifactTemplateSummary>[template],
                              ),
                            );
                          }
                          return SizedBox(
                            width: cardWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: artifactTemplateColor(
                                    template.label,
                                  ).withValues(alpha: 0.22),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      template.label,
                                      style: TextStyle(
                                        color: artifactTemplateColor(
                                          template.label,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${template.exemplarCount} exemplar${template.exemplarCount == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: InterpolatedTopomap(
                                        key: ValueKey<String>(
                                          '${template.label}:${template.exemplarCount}:${template.sampleCount}:${points.map((TopomapPointValue point) => point.value.toStringAsFixed(3)).join(',')}',
                                        ),
                                        points: points,
                                        scale: sharedScale,
                                        bounds: sharedBounds,
                                        showLabels: false,
                                        sampleDensity: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  )
                : _ArtifactTemplateWaveformFallback(templates: templates),
          ),
        ],
      ),
    );
  }
}

TopomapColorScale _artifactTemplateTopomapScale() {
  return TopomapColorScale(
    colors: <Color>[
      const Color(0xFF143D8F),
      const Color(0xFF2EC4FF),
      const Color(0xFFFFF4B0),
      const Color(0xFFFF8C42),
      const Color(0xFFFF4D6D),
    ],
    legendLabel: '',
    sigmoidStrength: 1.35,
  );
}

TopomapValueBounds _artifactTemplateSharedBounds(
  List<List<TopomapPointValue>> templatePointSets,
) {
  final List<double> values = templatePointSets
      .expand(
        (List<TopomapPointValue> points) =>
            points.map((TopomapPointValue point) => point.value),
      )
      .toList(growable: false);
  if (values.isEmpty) {
    return const TopomapValueBounds(min: -1, max: 1);
  }

  double minValue = values.first;
  double maxValue = values.first;
  for (final double value in values.skip(1)) {
    minValue = math.min(minValue, value);
    maxValue = math.max(maxValue, value);
  }

  if (minValue == maxValue) {
    final double pad = minValue == 0 ? 1.0 : minValue.abs() * 0.25;
    return TopomapValueBounds(min: minValue - pad, max: maxValue + pad);
  }
  return TopomapValueBounds(min: minValue, max: maxValue);
}

List<TopomapPointValue> _templateTopomapPoints(
  ArtifactTemplateSummary template, {
  required List<String> channelLabels,
  required Map<String, ChannelCoordinate> channelCoordinates,
}) {
  if (channelLabels.isEmpty || channelCoordinates.isEmpty) {
    return const <TopomapPointValue>[];
  }
  final List<double> snapshotValues = _artifactTemplateSnapshotValues(template);
  if (snapshotValues.isEmpty) {
    return const <TopomapPointValue>[];
  }

  final int usableCount = math.min(channelLabels.length, snapshotValues.length);
  final List<TopomapPointValue> points = <TopomapPointValue>[];
  for (int index = 0; index < usableCount; index++) {
    final String label = channelLabels[index];
    final ChannelCoordinate? coordinate = channelCoordinates[label];
    if (coordinate == null) {
      continue;
    }
    points.add(
      TopomapPointValue(
        label: label,
        coordinate: coordinate,
        value: snapshotValues[index],
      ),
    );
  }
  return points;
}

List<double> _artifactTemplateSnapshotValues(ArtifactTemplateSummary template) {
  if (template.peakTopomapValues.isNotEmpty) {
    return template.peakTopomapValues;
  }
  final List<List<double>> channels = template.previewChannels;
  if (channels.isEmpty) {
    return const <double>[];
  }
  final int sampleIndex = _peakGfpSampleIndex(channels);
  return channels
      .where((List<double> channel) => channel.length > sampleIndex)
      .map((List<double> channel) => channel[sampleIndex])
      .toList(growable: false);
}

int _peakGfpSampleIndex(List<List<double>> channels) {
  if (channels.isEmpty) {
    return 0;
  }
  final int sampleCount = channels
      .map((List<double> channel) => channel.length)
      .fold<int>(channels.first.length, math.min);
  if (sampleCount <= 1) {
    return 0;
  }

  int bestIndex = 0;
  double bestGfp = double.negativeInfinity;
  for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    double mean = 0.0;
    for (final List<double> channel in channels) {
      mean += channel[sampleIndex];
    }
    mean /= channels.length;

    double variance = 0.0;
    for (final List<double> channel in channels) {
      final double centered = channel[sampleIndex] - mean;
      variance += centered * centered;
    }
    final double gfp = math.sqrt(variance / channels.length);
    if (gfp > bestGfp) {
      bestGfp = gfp;
      bestIndex = sampleIndex;
    }
  }
  return bestIndex;
}

class _ArtifactTemplateWaveformFallback extends StatelessWidget {
  const _ArtifactTemplateWaveformFallback({required this.templates});

  final List<ArtifactTemplateSummary> templates;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArtifactTemplatePainter(templates: templates),
      child: const SizedBox.expand(),
    );
  }
}

class _ArtifactTemplatePainter extends CustomPainter {
  const _ArtifactTemplatePainter({required this.templates});

  final List<ArtifactTemplateSummary> templates;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final Paint baselinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;

    final double baselineY = size.height - 6;
    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      baselinePaint,
    );
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      gridPaint,
    );

    double maxValue = 1.0;
    for (final ArtifactTemplateSummary template in templates) {
      for (final double sample in template.previewSamples) {
        if (sample > maxValue) {
          maxValue = sample;
        }
      }
    }

    for (final ArtifactTemplateSummary template in templates) {
      final List<double> samples = template.previewSamples;
      if (samples.length < 2) {
        continue;
      }
      final Path path = Path();
      for (int index = 0; index < samples.length; index++) {
        final double x = samples.length == 1
            ? 0
            : (index / (samples.length - 1)) * size.width;
        final double normalized = (samples[index] / maxValue).clamp(0.0, 1.0);
        final double y = baselineY - (normalized * (size.height - 14));
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final Paint paint = Paint()
        ..color = artifactTemplateColor(template.label).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.0;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArtifactTemplatePainter oldDelegate) {
    return oldDelegate.templates != templates;
  }
}
