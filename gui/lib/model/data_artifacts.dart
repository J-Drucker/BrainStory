class MarkerType {
  static const String event = 'event';
  static const String window = 'window';
  static const String artifact = 'artifact';
  static const String segment = 'segment';
}

enum MarkerChangeType {
  add,
  remove,
  change,
}

class MarkerChangeEntry {
  const MarkerChangeEntry({
    required this.dataset,
    required this.changeType,
    this.oldLabel,
    this.oldOnsetMicros,
    this.oldDurationMicros,
    this.newLabel,
    this.newOnsetMicros,
    this.newDurationMicros,
  });

  final String dataset;
  final MarkerChangeType changeType;
  final String? oldLabel;
  final int? oldOnsetMicros;
  final int? oldDurationMicros;
  final String? newLabel;
  final int? newOnsetMicros;
  final int? newDurationMicros;

  MarkerChangeEntry copyWith({
    String? dataset,
    MarkerChangeType? changeType,
    String? oldLabel,
    int? oldOnsetMicros,
    int? oldDurationMicros,
    String? newLabel,
    int? newOnsetMicros,
    int? newDurationMicros,
  }) {
    return MarkerChangeEntry(
      dataset: dataset ?? this.dataset,
      changeType: changeType ?? this.changeType,
      oldLabel: oldLabel ?? this.oldLabel,
      oldOnsetMicros: oldOnsetMicros ?? this.oldOnsetMicros,
      oldDurationMicros: oldDurationMicros ?? this.oldDurationMicros,
      newLabel: newLabel ?? this.newLabel,
      newOnsetMicros: newOnsetMicros ?? this.newOnsetMicros,
      newDurationMicros: newDurationMicros ?? this.newDurationMicros,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'dataset': dataset,
      'changeType': changeType.name,
      'oldLabel': oldLabel,
      'oldOnsetMicros': oldOnsetMicros,
      'oldDurationMicros': oldDurationMicros,
      'newLabel': newLabel,
      'newOnsetMicros': newOnsetMicros,
      'newDurationMicros': newDurationMicros,
    };
  }

  static MarkerChangeEntry fromJson(Map<String, dynamic> json) {
    final String wireValue = json['changeType']?.toString() ?? MarkerChangeType.change.name;
    final MarkerChangeType changeType = MarkerChangeType.values.firstWhere(
      (MarkerChangeType candidate) => candidate.name == wireValue,
      orElse: () => MarkerChangeType.change,
    );
    return MarkerChangeEntry(
      dataset: json['dataset']?.toString() ?? '',
      changeType: changeType,
      oldLabel: json['oldLabel']?.toString(),
      oldOnsetMicros: (json['oldOnsetMicros'] as num?)?.round(),
      oldDurationMicros: (json['oldDurationMicros'] as num?)?.round(),
      newLabel: json['newLabel']?.toString(),
      newOnsetMicros: (json['newOnsetMicros'] as num?)?.round(),
      newDurationMicros: (json['newDurationMicros'] as num?)?.round(),
    );
  }
}

class MarkerChange {
  const MarkerChange({
    this.rows = const <MarkerChangeEntry>[],
  });

  final List<MarkerChangeEntry> rows;

  bool get isEmpty => rows.isEmpty;

  MarkerChange copyWith({
    List<MarkerChangeEntry>? rows,
  }) {
    return MarkerChange(
      rows: rows ?? this.rows,
    );
  }

  MarkerChange append(MarkerChangeEntry row) {
    return MarkerChange(
      rows: <MarkerChangeEntry>[...rows, row],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'rows': rows
          .map((MarkerChangeEntry row) => row.toJson())
          .toList(growable: false),
    };
  }

  static MarkerChange fromJson(Map<String, dynamic> json) {
    return MarkerChange(
      rows: (json['rows'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MarkerChangeEntry.fromJson)
          .toList(growable: false),
    );
  }
}

class TimeMarker {
  const TimeMarker({
    required this.onsetMicros,
    required this.label,
    this.durationMicros = 0,
    this.markerType = MarkerType.event,
    this.channelMask = const <int>[],
    this.attributes = const <String, dynamic>{},
  });

  final int onsetMicros;
  final int durationMicros;
  final String label;
  final String markerType;
  final List<int> channelMask;
  final Map<String, dynamic> attributes;

  double get timeSeconds => onsetMicros / 1000000.0;
  String get kind => markerType;

  int onsetSamples(double sampleRate) =>
      ((onsetMicros / 1000000.0) * sampleRate).round();

  int durationSamples(double sampleRate) =>
      ((durationMicros / 1000000.0) * sampleRate).round();

  List<int> applicableChannels(int channelCount) {
    if (channelMask.isEmpty) {
      return List<int>.filled(channelCount, 1, growable: false);
    }
    if (channelMask.length == channelCount) {
      return List<int>.from(channelMask, growable: false);
    }
    final List<int> normalized = List<int>.filled(channelCount, 1, growable: false);
    for (int index = 0; index < channelCount && index < channelMask.length; index++) {
      normalized[index] = channelMask[index];
    }
    return normalized;
  }

  TimeMarker copyWith({
    int? onsetMicros,
    int? durationMicros,
    String? label,
    String? markerType,
    List<int>? channelMask,
    Map<String, dynamic>? attributes,
  }) {
    return TimeMarker(
      onsetMicros: onsetMicros ?? this.onsetMicros,
      durationMicros: durationMicros ?? this.durationMicros,
      label: label ?? this.label,
      markerType: markerType ?? this.markerType,
      channelMask: channelMask ?? this.channelMask,
      attributes: attributes ?? this.attributes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'onsetMicros': onsetMicros,
      'durationMicros': durationMicros,
      'label': label,
      'markerType': markerType,
      'channelMask': channelMask,
      'attributes': attributes,
      // Legacy compatibility for older project files and node params.
      'timeSeconds': timeSeconds,
      'kind': markerType,
    };
  }

  static TimeMarker fromJson(Map<String, dynamic> json) {
    final String markerType =
        json['markerType']?.toString() ?? json['kind']?.toString() ?? MarkerType.event;
    final int onsetMicros = (json['onsetMicros'] as num?)?.round() ??
        (((json['timeSeconds'] as num?)?.toDouble() ?? 0.0) * 1000000.0).round();
    final int durationMicros = (json['durationMicros'] as num?)?.round() ??
        (markerType == MarkerType.event ? 0 : 0);
    return TimeMarker(
      onsetMicros: onsetMicros,
      durationMicros: durationMicros,
      label: json['label']?.toString() ?? '',
      markerType: markerType,
      channelMask: (json['channelMask'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toInt())
          .toList(growable: false),
      attributes: Map<String, dynamic>.from(
        json['attributes'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}

class MarkerLabelTrack {
  const MarkerLabelTrack({
    required this.label,
    required this.markerType,
    this.defaultDurationMicros,
    this.onsetMicros = const <int>[],
    this.durationMicros = const <int>[],
    this.channelMasks = const <List<int>>[],
  });

  final String label;
  final String markerType;
  final int? defaultDurationMicros;
  final List<int> onsetMicros;
  final List<int> durationMicros;
  final List<List<int>> channelMasks;

  List<TimeMarker> materialize() {
    return List<TimeMarker>.generate(onsetMicros.length, (int index) {
      final int duration = durationMicros.length > index
          ? durationMicros[index]
          : (defaultDurationMicros ?? 0);
      return TimeMarker(
        onsetMicros: onsetMicros[index],
        durationMicros: duration,
        label: label,
        markerType: markerType,
        channelMask: channelMasks.length > index ? channelMasks[index] : const <int>[],
      );
    }, growable: false);
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
    kind: marker.markerType,
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

  List<MarkerLabelTrack> get markerLabelTracks {
    final Map<String, List<TimeMarker>> grouped = <String, List<TimeMarker>>{};
    for (final TimeMarker marker in markers) {
      final String key = '${marker.markerType}|${marker.label}';
      grouped.putIfAbsent(key, () => <TimeMarker>[]).add(marker);
    }
    return grouped.values.map((List<TimeMarker> groupedMarkers) {
      final TimeMarker first = groupedMarkers.first;
      final Set<int> durations = groupedMarkers.map((TimeMarker marker) => marker.durationMicros).toSet();
      return MarkerLabelTrack(
        label: first.label,
        markerType: first.markerType,
        defaultDurationMicros: durations.length == 1 ? durations.first : null,
        onsetMicros: groupedMarkers.map((TimeMarker marker) => marker.onsetMicros).toList(growable: false),
        durationMicros: durations.length == 1
            ? const <int>[]
            : groupedMarkers.map((TimeMarker marker) => marker.durationMicros).toList(growable: false),
        channelMasks: groupedMarkers
            .map((TimeMarker marker) => marker.channelMask)
            .toList(growable: false),
      );
    }).toList(growable: false);
  }

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

class FooofPeakData {
  const FooofPeakData({
    required this.centerFrequencyHz,
    required this.amplitude,
    this.bandwidthHz = 0.0,
  });

  final double centerFrequencyHz;
  final double amplitude;
  final double bandwidthHz;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'centerFrequencyHz': centerFrequencyHz,
      'amplitude': amplitude,
      'bandwidthHz': bandwidthHz,
    };
  }

  static FooofPeakData fromJson(Map<String, dynamic> json) {
    return FooofPeakData(
      centerFrequencyHz: (json['centerFrequencyHz'] as num?)?.toDouble() ?? 0.0,
      amplitude: (json['amplitude'] as num?)?.toDouble() ?? 0.0,
      bandwidthHz: (json['bandwidthHz'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class FooofResultData {
  const FooofResultData({
    required this.intercept,
    required this.exponent,
    required this.peaks,
    this.fitFrequencies = const <double>[],
    this.aperiodicFit = const <double>[],
    this.residual = const <double>[],
    this.source = '',
  });

  final double intercept;
  final double exponent;
  final List<FooofPeakData> peaks;
  final List<double> fitFrequencies;
  final List<double> aperiodicFit;
  final List<double> residual;
  final String source;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'intercept': intercept,
      'exponent': exponent,
      'peaks': peaks.map((FooofPeakData peak) => peak.toJson()).toList(growable: false),
      'fitFrequencies': fitFrequencies,
      'aperiodicFit': aperiodicFit,
      'residual': residual,
      'source': source,
    };
  }

  static FooofResultData fromJson(Map<String, dynamic> json) {
    return FooofResultData(
      intercept: (json['intercept'] as num?)?.toDouble() ?? 0.0,
      exponent: (json['exponent'] as num?)?.toDouble() ?? 0.0,
      peaks: (json['peaks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(FooofPeakData.fromJson)
          .toList(growable: false),
      fitFrequencies: (json['fitFrequencies'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      aperiodicFit: (json['aperiodicFit'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      residual: (json['residual'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false),
      source: json['source']?.toString() ?? '',
    );
  }
}

class FeatureTableData {
  const FeatureTableData({
    required this.columns,
    required this.rows,
    this.source = '',
  });

  final List<String> columns;
  final List<Map<String, String>> rows;
  final String source;

  String toCsv() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(columns.map(_csvEscape).join(','));
    for (final Map<String, String> row in rows) {
      buffer.writeln(
        columns.map((String column) => _csvEscape(row[column] ?? '')).join(','),
      );
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'columns': columns,
      'rows': rows,
      'source': source,
    };
  }

  static FeatureTableData fromJson(Map<String, dynamic> json) {
    return FeatureTableData(
      columns: (json['columns'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toList(growable: false),
      rows: (json['rows'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic row) => Map<String, String>.from(
              (row as Map).map(
                (dynamic key, dynamic value) =>
                    MapEntry<String, String>(key.toString(), value.toString()),
              ),
            ),
          )
          .toList(growable: false),
      source: json['source']?.toString() ?? '',
    );
  }
}

class BridgeCorrelationFrameData {
  const BridgeCorrelationFrameData({
    required this.minuteIndex,
    required this.startSample,
    required this.endSampleExclusive,
    required this.correlationMatrix,
  });

  final int minuteIndex;
  final int startSample;
  final int endSampleExclusive;
  final List<List<double>> correlationMatrix;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'minuteIndex': minuteIndex,
      'startSample': startSample,
      'endSampleExclusive': endSampleExclusive,
      'correlationMatrix': correlationMatrix,
    };
  }

  static BridgeCorrelationFrameData fromJson(Map<String, dynamic> json) {
    return BridgeCorrelationFrameData(
      minuteIndex: (json['minuteIndex'] as num?)?.toInt() ?? 0,
      startSample: (json['startSample'] as num?)?.toInt() ?? 0,
      endSampleExclusive: (json['endSampleExclusive'] as num?)?.toInt() ?? 0,
      correlationMatrix:
          (json['correlationMatrix'] as List<dynamic>? ?? const <dynamic>[])
              .map(
                (dynamic row) => (row as List<dynamic>)
                    .map((dynamic value) => (value as num).toDouble())
                    .toList(growable: false),
              )
              .toList(growable: false),
    );
  }
}

class BridgeDetectionData {
  const BridgeDetectionData({
    required this.channelLabels,
    required this.windowSampleCount,
    required this.sampleRate,
    required this.frames,
    this.source = '',
  });

  final List<String> channelLabels;
  final int windowSampleCount;
  final double sampleRate;
  final List<BridgeCorrelationFrameData> frames;
  final String source;

  int get frameCount => frames.length;
  int get channelCount => channelLabels.length;
  int get valueCount => frames.fold<int>(
        0,
        (int total, BridgeCorrelationFrameData frame) =>
            total +
            frame.correlationMatrix.fold<int>(
              0,
              (int sum, List<double> row) => sum + row.length,
            ),
      );

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'channelLabels': channelLabels,
      'windowSampleCount': windowSampleCount,
      'sampleRate': sampleRate,
      'frames': frames
          .map((BridgeCorrelationFrameData frame) => frame.toJson())
          .toList(growable: false),
      'source': source,
    };
  }

  static BridgeDetectionData fromJson(Map<String, dynamic> json) {
    return BridgeDetectionData(
      channelLabels: (json['channelLabels'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toList(growable: false),
      windowSampleCount: (json['windowSampleCount'] as num?)?.toInt() ?? 0,
      sampleRate: (json['sampleRate'] as num?)?.toDouble() ?? 0.0,
      frames: (json['frames'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(BridgeCorrelationFrameData.fromJson)
          .toList(growable: false),
      source: json['source']?.toString() ?? '',
    );
  }
}

String _csvEscape(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
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
