import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../nodes/interactive_artifact_detection_node.dart';

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
    final double waveformWidth = templates
        .map(
          (ArtifactTemplateSummary template) =>
              (template.durationMicros / 1000000.0) * pixelsPerSecond,
        )
        .fold<double>(0, math.max)
        .clamp(80.0, 280.0);

    return Container(
      width: double.infinity,
      height: 250,
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
            'Current template summary',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double cardWidth = templates.length == 1
                    ? constraints.maxWidth
                    : math.max(
                        waveformWidth + 40,
                        (constraints.maxWidth * 0.72).clamp(220.0, 360.0),
                      );
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: templates.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final ArtifactTemplateSummary template = templates[index];
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
                                  color: artifactTemplateColor(template.label),
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
                              const SizedBox(height: 8),
                              Expanded(
                                child: _LabeledTemplatePanel(
                                  label: 'Waveform',
                                  child: _ArtifactTemplateWaveformFallback(
                                    templates: <ArtifactTemplateSummary>[
                                      template,
                                    ],
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledTemplatePanel extends StatelessWidget {
  const _LabeledTemplatePanel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Expanded(child: child),
      ],
    );
  }
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
