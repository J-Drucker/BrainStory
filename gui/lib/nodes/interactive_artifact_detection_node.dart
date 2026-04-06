import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import 'node_type.dart';

class InteractiveArtifactDetectionNodeType extends NodeType {
  static const List<String> supportedLabels = <String>[
    'blink',
    'saccade_vertical',
    'saccade_horizontal',
    'motion',
  ];

  static const String pendingStatus = 'pending';
  static const String acceptedStatus = 'accepted';
  static const String rejectedStatus = 'rejected';

  @override
  String get title => 'Interactive Artifact Detection';

  @override
  NodeCategory get category => NodeCategory.markerFunctions;

  @override
  Map<String, dynamic> get defaultParams => <String, dynamic>{
        'interactiveArtifactDetection': true,
        'artifactThreshold': 0.78,
        'artifactExemplars': <Map<String, dynamic>>[],
        'artifactCandidates': <Map<String, dynamic>>[],
        'artifactTemplates': <Map<String, dynamic>>[],
      };

  @override
  List<PortSpec> get inputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
      ];

  @override
  List<PortSpec> get outputs => const <PortSpec>[
        PortSpec(name: 'signal', type: PortType.signal),
        PortSpec(name: 'markers', type: PortType.markers),
      ];

  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) {
    final int exemplarCount =
        (params['artifactExemplars'] as List<dynamic>? ?? const <dynamic>[]).length;
    final int candidateCount =
        (params['artifactCandidates'] as List<dynamic>? ?? const <dynamic>[]).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Drag in the visualizer to label artifact exemplars. Hold Alt while dragging to choose a different label.',
        ),
        const SizedBox(height: 12),
        Text(
          '$exemplarCount exemplar${exemplarCount == 1 ? '' : 's'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          '$candidateCount candidate${candidateCount == 1 ? '' : 's'} tracked',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) async {
    final TimeSeriesData? timeSeries = dataset.timeSeries;
    if (timeSeries == null) {
      return;
    }

    dataset.timeSeries = timeSeries.copyWith(
      markers: acceptedMarkersForDataset(
        dataset.id,
        params,
        baseMarkers: timeSeries.markers,
      ),
    );
    dataset.ram['interactiveArtifactDetection.templates'] =
        (params['artifactTemplates'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => Map<String, dynamic>.from(value as Map))
            .toList(growable: false);
  }

  static List<ArtifactExemplarData> exemplarsForDataset(
    String datasetId,
    Map<String, dynamic> params,
  ) {
    return (params['artifactExemplars'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ArtifactExemplarData.fromJson)
        .where((ArtifactExemplarData exemplar) => exemplar.datasetId == datasetId)
        .toList(growable: false)
      ..sort(
        (ArtifactExemplarData a, ArtifactExemplarData b) =>
            a.onsetMicros.compareTo(b.onsetMicros),
      );
  }

  static List<ArtifactCandidateData> candidatesForDataset(
    String datasetId,
    Map<String, dynamic> params, {
    Set<String>? statuses,
  }) {
    return (params['artifactCandidates'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ArtifactCandidateData.fromJson)
        .where((ArtifactCandidateData candidate) => candidate.datasetId == datasetId)
        .where(
          (ArtifactCandidateData candidate) =>
              statuses == null || statuses.contains(candidate.status),
        )
        .toList(growable: false)
      ..sort(
        (ArtifactCandidateData a, ArtifactCandidateData b) =>
            a.onsetMicros.compareTo(b.onsetMicros),
      );
  }

  static List<ArtifactTemplateSummary> templateSummariesForDataset(
    String datasetId,
    Map<String, dynamic> params,
  ) {
    return (params['artifactTemplates'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ArtifactTemplateSummary.fromJson)
        .where((ArtifactTemplateSummary summary) => summary.datasetId == datasetId)
        .toList(growable: false)
      ..sort(
        (ArtifactTemplateSummary a, ArtifactTemplateSummary b) =>
            a.label.compareTo(b.label),
      );
  }

  static List<TimeMarker> acceptedMarkersForDataset(
    String datasetId,
    Map<String, dynamic> params, {
    required List<TimeMarker> baseMarkers,
  }) {
    final List<TimeMarker> preservedMarkers = baseMarkers
        .where(
          (TimeMarker marker) =>
              marker.attributes['brainstory.interactiveArtifactDetection'] != true,
        )
        .toList(growable: true);
    final List<TimeMarker> exemplarMarkers = exemplarsForDataset(datasetId, params)
        .map((ArtifactExemplarData exemplar) => exemplar.toMarker())
        .toList(growable: false);
    final List<TimeMarker> acceptedCandidates = candidatesForDataset(
      datasetId,
      params,
      statuses: const <String>{acceptedStatus},
    ).map((ArtifactCandidateData candidate) => candidate.toMarker()).toList(
          growable: false,
        );
    preservedMarkers.addAll(exemplarMarkers);
    preservedMarkers.addAll(acceptedCandidates);
    preservedMarkers.sort(
      (TimeMarker a, TimeMarker b) => a.onsetMicros.compareTo(b.onsetMicros),
    );
    return preservedMarkers;
  }

  static List<TimeMarker> displayMarkersForDataset(
    String datasetId,
    Map<String, dynamic> params, {
    required List<TimeMarker> baseMarkers,
  }) {
    final List<TimeMarker> markers = acceptedMarkersForDataset(
      datasetId,
      params,
      baseMarkers: baseMarkers,
    ).toList(growable: true);
    markers.addAll(
      candidatesForDataset(
        datasetId,
        params,
        statuses: const <String>{pendingStatus},
      ).map((ArtifactCandidateData candidate) => candidate.toMarker()),
    );
    markers.sort(
      (TimeMarker a, TimeMarker b) => a.onsetMicros.compareTo(b.onsetMicros),
    );
    return markers;
  }

  static ArtifactDetectionComputation recomputeDetectionsForDataset({
    required String datasetId,
    required TimeSeriesData timeSeries,
    required List<ArtifactExemplarData> exemplars,
    required List<ArtifactCandidateData> existingCandidates,
    double threshold = 0.78,
  }) {
    final List<ArtifactTemplateSummary> templates = <ArtifactTemplateSummary>[];
    final List<ArtifactCandidateData> nextCandidates = <ArtifactCandidateData>[];
    if (timeSeries.channels.isEmpty || exemplars.isEmpty) {
      return ArtifactDetectionComputation(
        templates: templates,
        candidates: nextCandidates,
      );
    }

    final Map<String, List<ArtifactExemplarData>> byLabel =
        <String, List<ArtifactExemplarData>>{};
    for (final ArtifactExemplarData exemplar in exemplars) {
      byLabel.putIfAbsent(exemplar.label, () => <ArtifactExemplarData>[]).add(exemplar);
    }

    final List<double> workingSignal = _artifactDetectionSignal(timeSeries.channels);
    final Map<String, ArtifactCandidateData> existingById =
        <String, ArtifactCandidateData>{
      for (final ArtifactCandidateData candidate in existingCandidates) candidate.id: candidate,
    };

    for (final MapEntry<String, List<ArtifactExemplarData>> entry in byLabel.entries) {
      final _ComputedTemplate? template = _buildTemplateForLabel(
        channels: timeSeries.channels,
        signal: workingSignal,
        sampleRate: timeSeries.sampleRate,
        label: entry.key,
        exemplars: entry.value,
      );
      if (template == null) {
        continue;
      }
      templates.add(
        ArtifactTemplateSummary(
          datasetId: datasetId,
          label: entry.key,
          exemplarCount: entry.value.length,
          sampleCount: template.sampleCount,
          durationMicros: template.durationMicros,
          previewSamples: _decimateTemplatePreview(template.samples),
          previewChannels: _decimateTemplateChannelsPreview(template.channelSamples),
        ),
      );
      nextCandidates.addAll(
        _detectCandidatesForTemplate(
          datasetId: datasetId,
          signal: workingSignal,
          sampleRate: timeSeries.sampleRate,
          template: template,
          threshold: threshold,
          exemplars: entry.value,
          existingById: existingById,
        ),
      );
    }

    nextCandidates.sort(
      (ArtifactCandidateData a, ArtifactCandidateData b) =>
          a.onsetMicros.compareTo(b.onsetMicros),
    );
    return ArtifactDetectionComputation(
      templates: templates,
      candidates: nextCandidates,
    );
  }
}

List<double> _decimateTemplatePreview(
  List<double> samples, {
  int targetPoints = 160,
}) {
  if (samples.length <= targetPoints) {
    return List<double>.from(samples, growable: false);
  }
  final double stride = samples.length / targetPoints;
  final List<double> preview = <double>[];
  for (int index = 0; index < targetPoints; index++) {
    final int sampleIndex = math.min(
      samples.length - 1,
      (index * stride).round(),
    );
    preview.add(samples[sampleIndex]);
  }
  return preview;
}

class ArtifactDetectionComputation {
  const ArtifactDetectionComputation({
    required this.templates,
    required this.candidates,
  });

  final List<ArtifactTemplateSummary> templates;
  final List<ArtifactCandidateData> candidates;
}

class ArtifactExemplarData {
  const ArtifactExemplarData({
    required this.id,
    required this.datasetId,
    required this.label,
    required this.onsetMicros,
    required this.durationMicros,
    this.channelMask = const <int>[],
  });

  final String id;
  final String datasetId;
  final String label;
  final int onsetMicros;
  final int durationMicros;
  final List<int> channelMask;

  int durationSamples(double sampleRate) =>
      ((durationMicros / 1000000.0) * sampleRate).round().clamp(1, 1 << 30);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'datasetId': datasetId,
      'label': label,
      'onsetMicros': onsetMicros,
      'durationMicros': durationMicros,
      'channelMask': channelMask,
    };
  }

  static ArtifactExemplarData fromJson(Map<String, dynamic> json) {
    return ArtifactExemplarData(
      id: json['id']?.toString() ?? '',
      datasetId: json['datasetId']?.toString() ?? '',
      label: json['label']?.toString() ?? 'blink',
      onsetMicros: (json['onsetMicros'] as num?)?.round() ?? 0,
      durationMicros: (json['durationMicros'] as num?)?.round() ?? 0,
      channelMask: (json['channelMask'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toInt())
          .toList(growable: false),
    );
  }

  TimeMarker toMarker() {
    return TimeMarker(
      onsetMicros: onsetMicros,
      durationMicros: durationMicros,
      label: label,
      markerType: MarkerType.artifact,
      channelMask: channelMask,
      attributes: <String, dynamic>{
        'brainstory.interactiveArtifactDetection': true,
        'brainstory.artifactSource': 'exemplar',
        'brainstory.artifactStatus': InteractiveArtifactDetectionNodeType.acceptedStatus,
        'brainstory.artifactId': id,
      },
    );
  }
}

class ArtifactCandidateData {
  const ArtifactCandidateData({
    required this.id,
    required this.datasetId,
    required this.label,
    required this.onsetMicros,
    required this.durationMicros,
    required this.score,
    required this.status,
    this.channelMask = const <int>[],
  });

  final String id;
  final String datasetId;
  final String label;
  final int onsetMicros;
  final int durationMicros;
  final double score;
  final String status;
  final List<int> channelMask;

  ArtifactCandidateData copyWith({
    String? status,
    double? score,
  }) {
    return ArtifactCandidateData(
      id: id,
      datasetId: datasetId,
      label: label,
      onsetMicros: onsetMicros,
      durationMicros: durationMicros,
      score: score ?? this.score,
      status: status ?? this.status,
      channelMask: channelMask,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'datasetId': datasetId,
      'label': label,
      'onsetMicros': onsetMicros,
      'durationMicros': durationMicros,
      'score': score,
      'status': status,
      'channelMask': channelMask,
    };
  }

  static ArtifactCandidateData fromJson(Map<String, dynamic> json) {
    return ArtifactCandidateData(
      id: json['id']?.toString() ?? '',
      datasetId: json['datasetId']?.toString() ?? '',
      label: json['label']?.toString() ?? 'blink',
      onsetMicros: (json['onsetMicros'] as num?)?.round() ?? 0,
      durationMicros: (json['durationMicros'] as num?)?.round() ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      status: json['status']?.toString() ??
          InteractiveArtifactDetectionNodeType.pendingStatus,
      channelMask: (json['channelMask'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toInt())
          .toList(growable: false),
    );
  }

  TimeMarker toMarker() {
    return TimeMarker(
      onsetMicros: onsetMicros,
      durationMicros: durationMicros,
      label: label,
      markerType: MarkerType.artifact,
      channelMask: channelMask,
      attributes: <String, dynamic>{
        'brainstory.interactiveArtifactDetection': true,
        'brainstory.artifactSource': 'candidate',
        'brainstory.artifactStatus': status,
        'brainstory.artifactId': id,
        'brainstory.matchScore': score,
      },
    );
  }
}

class ArtifactTemplateSummary {
  const ArtifactTemplateSummary({
    required this.datasetId,
    required this.label,
    required this.exemplarCount,
    required this.sampleCount,
    this.durationMicros = 0,
    this.previewSamples = const <double>[],
    this.previewChannels = const <List<double>>[],
  });

  final String datasetId;
  final String label;
  final int exemplarCount;
  final int sampleCount;
  final int durationMicros;
  final List<double> previewSamples;
  final List<List<double>> previewChannels;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'datasetId': datasetId,
      'label': label,
      'exemplarCount': exemplarCount,
      'sampleCount': sampleCount,
      'durationMicros': durationMicros,
      'previewSamples': previewSamples,
      'previewChannels': previewChannels,
    };
  }

  static ArtifactTemplateSummary fromJson(Map<String, dynamic> json) {
    return ArtifactTemplateSummary(
      datasetId: json['datasetId']?.toString() ?? '',
      label: json['label']?.toString() ?? 'blink',
      exemplarCount: (json['exemplarCount'] as num?)?.toInt() ?? 0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      durationMicros: (json['durationMicros'] as num?)?.round() ?? 0,
      previewSamples: (json['previewSamples'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      previewChannels: (json['previewChannels'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic channel) => (channel as List<dynamic>)
                .map((dynamic value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false),
    );
  }
}

class _ComputedTemplate {
  const _ComputedTemplate({
    required this.label,
    required this.samples,
    required this.channelSamples,
    required this.sampleCount,
    required this.durationMicros,
  });

  final String label;
  final List<double> samples;
  final List<List<double>> channelSamples;
  final int sampleCount;
  final int durationMicros;
}

List<double> _artifactDetectionSignal(List<List<double>> channels) {
  if (channels.isEmpty) {
    return const <double>[];
  }
  if (channels.length == 1) {
    return List<double>.from(channels.first, growable: false);
  }
  final int sampleCount = channels.first.length;
  return List<double>.generate(sampleCount, (int sampleIndex) {
    double sum = 0.0;
    for (final List<double> channel in channels) {
      sum += channel[sampleIndex];
    }
    return sum / channels.length;
  }, growable: false);
}

_ComputedTemplate? _buildTemplateForLabel({
  required List<List<double>> channels,
  required List<double> signal,
  required double sampleRate,
  required String label,
  required List<ArtifactExemplarData> exemplars,
}) {
  if (signal.isEmpty || exemplars.isEmpty) {
    return null;
  }

  final List<int> exemplarLengths = exemplars
      .map((ArtifactExemplarData exemplar) => exemplar.durationSamples(sampleRate))
      .where((int length) => length > 1)
      .toList(growable: false);
  if (exemplarLengths.isEmpty) {
    return null;
  }
  exemplarLengths.sort();
  final int targetLength = exemplarLengths[exemplarLengths.length ~/ 2];
  final int targetDurationMicros =
      ((targetLength / sampleRate) * 1000000.0).round();
  final List<List<double>> alignedSegments = <List<double>>[];
  final List<List<List<double>>> alignedChannelSegments = <List<List<double>>>[];
  List<double>? template;

  for (final ArtifactExemplarData exemplar in exemplars) {
    final int nominalStart =
        ((exemplar.onsetMicros / 1000000.0) * sampleRate).round();
    final int exemplarLength = exemplar.durationSamples(sampleRate);
    int bestStart = nominalStart;
    List<double> bestSegment = _extractResampledWindow(
      signal,
      nominalStart,
      exemplarLength,
      targetLength,
    );
    if (bestSegment.isEmpty) {
      continue;
    }
    if (template != null) {
      final int maxShiftSamples = math.max(
        1,
        math.min(targetLength ~/ 3, (sampleRate * 0.06).round()),
      );
      double bestScore = double.negativeInfinity;
      for (int shift = -maxShiftSamples; shift <= maxShiftSamples; shift++) {
        final List<double> candidate = _extractResampledWindow(
          signal,
          nominalStart + shift,
          exemplarLength,
          targetLength,
        );
        if (candidate.length != targetLength) {
          continue;
        }
        final double score = _normalizedCorrelation(template, candidate);
        if (score > bestScore) {
          bestScore = score;
          bestStart = nominalStart + shift;
          bestSegment = candidate;
        }
      }
    }
    alignedSegments.add(bestSegment);
    alignedChannelSegments.add(
      channels
          .map(
            (List<double> channel) => _extractResampledWindow(
              channel,
              bestStart,
              exemplarLength,
              targetLength,
            ),
          )
          .where((List<double> channel) => channel.length == targetLength)
          .toList(growable: false),
    );
    template = _meanWaveform(alignedSegments);
  }

  if (template == null || template.isEmpty) {
    return null;
  }
  final int channelCount = alignedChannelSegments.isEmpty
      ? 0
      : alignedChannelSegments
          .map((List<List<double>> segment) => segment.length)
          .reduce(math.min);
  final List<List<double>> meanChannelTemplates = List<List<double>>.generate(
    channelCount,
    (int channelIndex) => _meanWaveform(
      alignedChannelSegments
          .map((List<List<double>> segment) => segment[channelIndex])
          .toList(growable: false),
    ),
    growable: false,
  );
  return _ComputedTemplate(
    label: label,
    samples: template,
    channelSamples: meanChannelTemplates,
    sampleCount: template.length,
    durationMicros: targetDurationMicros,
  );
}

List<List<double>> _decimateTemplateChannelsPreview(
  List<List<double>> channels, {
  int targetPoints = 160,
}) {
  return channels
      .map(
        (List<double> channel) => _decimateTemplatePreview(
          channel,
          targetPoints: targetPoints,
        ),
      )
      .toList(growable: false);
}

List<ArtifactCandidateData> _detectCandidatesForTemplate({
  required String datasetId,
  required List<double> signal,
  required double sampleRate,
  required _ComputedTemplate template,
  required double threshold,
  required List<ArtifactExemplarData> exemplars,
  required Map<String, ArtifactCandidateData> existingById,
}) {
  if (signal.length < template.sampleCount || template.sampleCount < 4) {
    return const <ArtifactCandidateData>[];
  }

  final int stride = math.max(1, template.sampleCount ~/ 8);
  final List<_ScoredCandidateWindow> rawMatches = <_ScoredCandidateWindow>[];
  for (int start = 0; start + template.sampleCount <= signal.length; start += stride) {
    final List<double> window = signal.sublist(start, start + template.sampleCount);
    final double score = _normalizedCorrelation(template.samples, window);
    if (score < threshold) {
      continue;
    }
    final int onsetMicros = ((start / sampleRate) * 1000000.0).round();
    final int durationMicros = template.durationMicros;
    if (_overlapsExemplar(onsetMicros, durationMicros, exemplars)) {
      continue;
    }
    rawMatches.add(
      _ScoredCandidateWindow(
        onsetMicros: onsetMicros,
        durationMicros: durationMicros,
        score: score,
      ),
    );
  }

  rawMatches.sort(
    (_ScoredCandidateWindow a, _ScoredCandidateWindow b) => b.score.compareTo(a.score),
  );

  final List<_ScoredCandidateWindow> selected = <_ScoredCandidateWindow>[];
  for (final _ScoredCandidateWindow candidate in rawMatches) {
    final bool overlapsExisting = selected.any(
      (_ScoredCandidateWindow existing) =>
          _overlapFraction(
            candidate.onsetMicros,
            candidate.durationMicros,
            existing.onsetMicros,
            existing.durationMicros,
          ) > 0.5,
    );
    if (!overlapsExisting) {
      selected.add(candidate);
    }
    if (selected.length >= 32) {
      break;
    }
  }

  return selected.map((_ScoredCandidateWindow candidate) {
    final String id = _candidateId(
      label: template.label,
      onsetMicros: candidate.onsetMicros,
      durationMicros: candidate.durationMicros,
    );
    final ArtifactCandidateData? previous = existingById[id];
    return ArtifactCandidateData(
      id: id,
      datasetId: datasetId,
      label: template.label,
      onsetMicros: candidate.onsetMicros,
      durationMicros: candidate.durationMicros,
      score: candidate.score,
      status: previous?.status ?? InteractiveArtifactDetectionNodeType.pendingStatus,
      channelMask: previous?.channelMask ?? const <int>[],
    );
  }).toList(growable: false);
}

class _ScoredCandidateWindow {
  const _ScoredCandidateWindow({
    required this.onsetMicros,
    required this.durationMicros,
    required this.score,
  });

  final int onsetMicros;
  final int durationMicros;
  final double score;
}

bool _overlapsExemplar(
  int onsetMicros,
  int durationMicros,
  List<ArtifactExemplarData> exemplars,
) {
  for (final ArtifactExemplarData exemplar in exemplars) {
    if (_overlapFraction(
          onsetMicros,
          durationMicros,
          exemplar.onsetMicros,
          exemplar.durationMicros,
        ) > 0.5) {
      return true;
    }
  }
  return false;
}

double _overlapFraction(
  int startMicrosA,
  int durationMicrosA,
  int startMicrosB,
  int durationMicrosB,
) {
  final int endMicrosA = startMicrosA + math.max(1, durationMicrosA);
  final int endMicrosB = startMicrosB + math.max(1, durationMicrosB);
  final int overlapStart = math.max(startMicrosA, startMicrosB);
  final int overlapEnd = math.min(endMicrosA, endMicrosB);
  if (overlapEnd <= overlapStart) {
    return 0.0;
  }
  final int overlap = overlapEnd - overlapStart;
  return overlap / math.max(1, math.min(durationMicrosA, durationMicrosB));
}

String _candidateId({
  required String label,
  required int onsetMicros,
  required int durationMicros,
}) {
  return '$label:$onsetMicros:$durationMicros';
}

List<double> _extractResampledWindow(
  List<double> signal,
  int startSample,
  int sourceLength,
  int targetLength,
) {
  if (signal.isEmpty || sourceLength <= 1 || targetLength <= 1) {
    return const <double>[];
  }

  final int clampedStart = startSample.clamp(0, math.max(0, signal.length - 1));
  final int clampedEnd = math.min(signal.length, clampedStart + sourceLength);
  if (clampedEnd - clampedStart < 2) {
    return const <double>[];
  }

  final List<double> source = signal.sublist(clampedStart, clampedEnd);
  if (source.length == targetLength) {
    return source;
  }

  final double scale = (source.length - 1) / math.max(1, targetLength - 1);
  return List<double>.generate(targetLength, (int index) {
    final double position = index * scale;
    final int lower = position.floor().clamp(0, source.length - 1);
    final int upper = position.ceil().clamp(0, source.length - 1);
    if (lower == upper) {
      return source[lower];
    }
    final double fraction = position - lower;
    return source[lower] + ((source[upper] - source[lower]) * fraction);
  }, growable: false);
}

List<double> _meanWaveform(List<List<double>> segments) {
  if (segments.isEmpty) {
    return const <double>[];
  }
  final int length = segments.first.length;
  return List<double>.generate(length, (int index) {
    double sum = 0.0;
    for (final List<double> segment in segments) {
      sum += segment[index];
    }
    return sum / segments.length;
  }, growable: false);
}

double _normalizedCorrelation(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) {
    return -1.0;
  }
  final double meanA = a.reduce((double x, double y) => x + y) / a.length;
  final double meanB = b.reduce((double x, double y) => x + y) / b.length;
  double numerator = 0.0;
  double energyA = 0.0;
  double energyB = 0.0;
  for (int index = 0; index < a.length; index++) {
    final double centeredA = a[index] - meanA;
    final double centeredB = b[index] - meanB;
    numerator += centeredA * centeredB;
    energyA += centeredA * centeredA;
    energyB += centeredB * centeredB;
  }
  if (energyA <= 0 || energyB <= 0) {
    return -1.0;
  }
  return numerator / math.sqrt(energyA * energyB);
}
