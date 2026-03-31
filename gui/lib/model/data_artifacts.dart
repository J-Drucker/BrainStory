class TimeMarker {
  const TimeMarker({
    required this.timeSeconds,
    required this.label,
    this.kind = 'event',
  });

  final double timeSeconds;
  final String label;
  final String kind;

  TimeMarker copyWith({
    double? timeSeconds,
    String? label,
    String? kind,
  }) {
    return TimeMarker(
      timeSeconds: timeSeconds ?? this.timeSeconds,
      label: label ?? this.label,
      kind: kind ?? this.kind,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timeSeconds': timeSeconds,
      'label': label,
      'kind': kind,
    };
  }

  static TimeMarker fromJson(Map<String, dynamic> json) {
    return TimeMarker(
      timeSeconds: (json['timeSeconds'] as num?)?.toDouble() ?? 0.0,
      label: json['label']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'event',
    );
  }
}

String markerKeyForKindAndLabel({
  required String kind,
  required String label,
}) {
  return '${kind.trim()}|${label.trim()}';
}

String markerKeyForMarker(TimeMarker marker) {
  return markerKeyForKindAndLabel(
    kind: marker.kind,
    label: marker.label,
  );
}

class FactorLevel {
  const FactorLevel({
    required this.name,
    this.markerKeys = const <String>{},
  });

  final String name;
  final Set<String> markerKeys;

  FactorLevel copyWith({
    String? name,
    Set<String>? markerKeys,
  }) {
    return FactorLevel(
      name: name ?? this.name,
      markerKeys: markerKeys ?? this.markerKeys,
    );
  }

  bool containsMarker(String markerKey) => markerKeys.contains(markerKey);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'markerKeys': markerKeys.toList(growable: false),
    };
  }

  static FactorLevel fromJson(Map<String, dynamic> json) {
    return FactorLevel(
      name: json['name']?.toString() ?? '',
      markerKeys: Set<String>.from(
        (json['markerKeys'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic value) => value.toString()),
      ),
    );
  }
}

class Factor {
  const Factor({
    required this.name,
    this.levels = const <FactorLevel>[],
  });

  final String name;
  final List<FactorLevel> levels;

  Factor copyWith({
    String? name,
    List<FactorLevel>? levels,
  }) {
    return Factor(
      name: name ?? this.name,
      levels: levels ?? this.levels,
    );
  }

  FactorLevel? levelForMarker(String markerKey) {
    for (final FactorLevel level in levels) {
      if (level.containsMarker(markerKey)) {
        return level;
      }
    }
    return null;
  }

  bool markerBelongsToMultipleLevels() {
    final Set<String> assignedMarkers = <String>{};
    for (final FactorLevel level in levels) {
      for (final String markerKey in level.markerKeys) {
        if (!assignedMarkers.add(markerKey)) {
          return true;
        }
      }
    }
    return false;
  }

  bool get isValid => !markerBelongsToMultipleLevels();

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'levels': levels
          .map((FactorLevel level) => level.toJson())
          .toList(growable: false),
    };
  }

  static Factor fromJson(Map<String, dynamic> json) {
    return Factor(
      name: json['name']?.toString() ?? '',
      levels: (json['levels'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(FactorLevel.fromJson)
          .toList(growable: false),
    );
  }
}

class TimeSeriesData {
  const TimeSeriesData({
    this.samples = const <double>[],
    this.channelSamples = const <List<double>>[],
    required this.sampleRate,
    this.channelLabels = const <String>[],
    this.markers = const <TimeMarker>[],
    this.factors = const <Factor>[],
    this.source = '',
  }) : assert(
          channelSamples.length == 0 || samples.length == 0,
          'Provide either samples or channelSamples, not both.',
        );

  final List<double> samples;
  final List<List<double>> channelSamples;
  final double sampleRate;
  final List<String> channelLabels;
  final List<TimeMarker> markers;
  final List<Factor> factors;
  final String source;

  List<List<double>> get channels {
    if (channelSamples.isNotEmpty) {
      return channelSamples;
    }
    if (samples.isEmpty) {
      return const <List<double>>[];
    }
    return <List<double>>[samples];
  }

  List<double> get primaryChannel {
    if (channelSamples.isNotEmpty) {
      return channelSamples.first;
    }
    return samples;
  }

  int get channelCount => channels.length;

  int get sampleCount => channels.isEmpty ? 0 : channels.first.length;

  TimeSeriesData copyWith({
    List<double>? samples,
    List<List<double>>? channelSamples,
    double? sampleRate,
    List<String>? channelLabels,
    List<TimeMarker>? markers,
    List<Factor>? factors,
    String? source,
  }) {
    return TimeSeriesData(
      samples: samples ?? (channelSamples == null ? this.samples : const <double>[]),
      channelSamples: channelSamples ?? this.channelSamples,
      sampleRate: sampleRate ?? this.sampleRate,
      channelLabels: channelLabels ?? this.channelLabels,
      markers: markers ?? this.markers,
      factors: factors ?? this.factors,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'samples': samples,
      'channelSamples': channelSamples,
      'sampleRate': sampleRate,
      'channelLabels': channelLabels,
      'markers': markers.map((TimeMarker marker) => marker.toJson()).toList(growable: false),
      'factors': factors.map((Factor factor) => factor.toJson()).toList(growable: false),
      'source': source,
    };
  }

  static TimeSeriesData fromJson(Map<String, dynamic> json) {
    return TimeSeriesData(
      samples: (json['samples'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      channelSamples: (json['channelSamples'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic row) => (row as List<dynamic>)
                .map((dynamic value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false),
      sampleRate: (json['sampleRate'] as num?)?.toDouble() ?? 0.0,
      channelLabels: (json['channelLabels'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toList(growable: false),
      markers: (json['markers'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TimeMarker.fromJson)
          .toList(growable: false),
      factors: (json['factors'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Factor.fromJson)
          .toList(growable: false),
      source: json['source']?.toString() ?? '',
    );
  }
}

class SignalSegmentData {
  const SignalSegmentData({
    required this.channelSamples,
    required this.startSeconds,
    required this.stopSeconds,
    this.label = '',
    this.kind = 'segment',
    this.anchorTimeSeconds,
    this.appliedShiftMs = 0.0,
  });

  final List<List<double>> channelSamples;
  final double startSeconds;
  final double stopSeconds;
  final String label;
  final String kind;
  final double? anchorTimeSeconds;
  final double appliedShiftMs;

  List<double> get primaryChannel =>
      channelSamples.isEmpty ? const <double>[] : channelSamples.first;

  int get sampleCount =>
      channelSamples.isEmpty ? 0 : channelSamples.first.length;

  SignalSegmentData copyWith({
    List<List<double>>? channelSamples,
    double? startSeconds,
    double? stopSeconds,
    String? label,
    String? kind,
    double? anchorTimeSeconds,
    bool clearAnchorTime = false,
    double? appliedShiftMs,
  }) {
    return SignalSegmentData(
      channelSamples: channelSamples ?? this.channelSamples,
      startSeconds: startSeconds ?? this.startSeconds,
      stopSeconds: stopSeconds ?? this.stopSeconds,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      anchorTimeSeconds: clearAnchorTime
          ? null
          : (anchorTimeSeconds ?? this.anchorTimeSeconds),
      appliedShiftMs: appliedShiftMs ?? this.appliedShiftMs,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'channelSamples': channelSamples,
      'startSeconds': startSeconds,
      'stopSeconds': stopSeconds,
      'label': label,
      'kind': kind,
      'anchorTimeSeconds': anchorTimeSeconds,
      'appliedShiftMs': appliedShiftMs,
    };
  }

  static SignalSegmentData fromJson(Map<String, dynamic> json) {
    return SignalSegmentData(
      channelSamples: (json['channelSamples'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic row) => (row as List<dynamic>)
                .map((dynamic value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false),
      startSeconds: (json['startSeconds'] as num?)?.toDouble() ?? 0.0,
      stopSeconds: (json['stopSeconds'] as num?)?.toDouble() ?? 0.0,
      label: json['label']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'segment',
      anchorTimeSeconds: (json['anchorTimeSeconds'] as num?)?.toDouble(),
      appliedShiftMs: (json['appliedShiftMs'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SegmentedTimeSeriesData {
  const SegmentedTimeSeriesData({
    required this.segments,
    required this.sampleRate,
    this.channelLabels = const <String>[],
    this.source = '',
  });

  final List<SignalSegmentData> segments;
  final double sampleRate;
  final List<String> channelLabels;
  final String source;

  int get segmentCount => segments.length;

  SegmentedTimeSeriesData copyWith({
    List<SignalSegmentData>? segments,
    double? sampleRate,
    List<String>? channelLabels,
    String? source,
  }) {
    return SegmentedTimeSeriesData(
      segments: segments ?? this.segments,
      sampleRate: sampleRate ?? this.sampleRate,
      channelLabels: channelLabels ?? this.channelLabels,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'segments': segments
          .map((SignalSegmentData segment) => segment.toJson())
          .toList(growable: false),
      'sampleRate': sampleRate,
      'channelLabels': channelLabels,
      'source': source,
    };
  }

  static SegmentedTimeSeriesData fromJson(Map<String, dynamic> json) {
    return SegmentedTimeSeriesData(
      segments: (json['segments'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(SignalSegmentData.fromJson)
          .toList(growable: false),
      sampleRate: (json['sampleRate'] as num?)?.toDouble() ?? 0.0,
      channelLabels: (json['channelLabels'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toList(growable: false),
      source: json['source']?.toString() ?? '',
    );
  }
}

class FrequencySpectrumData {
  const FrequencySpectrumData({
    required this.frequencies,
    required this.power,
    this.segmentCount = 1,
    this.source = '',
  });

  final List<double> frequencies;
  final List<double> power;
  final int segmentCount;
  final String source;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'frequencies': frequencies,
      'power': power,
      'segmentCount': segmentCount,
      'source': source,
    };
  }

  static FrequencySpectrumData fromJson(Map<String, dynamic> json) {
    return FrequencySpectrumData(
      frequencies: (json['frequencies'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      power: (json['power'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      segmentCount: (json['segmentCount'] as num?)?.toInt() ?? 1,
      source: json['source']?.toString() ?? '',
    );
  }
}

class TimeFrequencyData {
  const TimeFrequencyData({
    required this.times,
    required this.frequencies,
    required this.powerMatrix,
    this.source = '',
  });

  final List<double> times;
  final List<double> frequencies;
  final List<List<double>> powerMatrix;
  final String source;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'times': times,
      'frequencies': frequencies,
      'powerMatrix': powerMatrix,
      'source': source,
    };
  }

  static TimeFrequencyData fromJson(Map<String, dynamic> json) {
    return TimeFrequencyData(
      times: (json['times'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      frequencies: (json['frequencies'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      powerMatrix: (json['powerMatrix'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic row) => (row as List<dynamic>)
                .map((dynamic value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false),
      source: json['source']?.toString() ?? '',
    );
  }
}

class MatrixTransformationData {
  const MatrixTransformationData({
    required this.matrix,
    this.componentLabels = const <String>[],
    this.source = '',
  });

  final List<List<double>> matrix;
  final List<String> componentLabels;
  final String source;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'matrix': matrix,
      'componentLabels': componentLabels,
      'source': source,
    };
  }

  static MatrixTransformationData fromJson(Map<String, dynamic> json) {
    return MatrixTransformationData(
      matrix: (json['matrix'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic row) => (row as List<dynamic>)
                .map((dynamic value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false),
      componentLabels: (json['componentLabels'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toList(growable: false),
      source: json['source']?.toString() ?? '',
    );
  }
}
