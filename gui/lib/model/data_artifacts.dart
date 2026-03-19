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

class TimeSeriesData {
  const TimeSeriesData({
    this.samples = const <double>[],
    this.channelSamples = const <List<double>>[],
    required this.sampleRate,
    this.channelLabels = const <String>[],
    this.markers = const <TimeMarker>[],
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
    String? source,
  }) {
    return TimeSeriesData(
      samples: samples ?? (channelSamples == null ? this.samples : const <double>[]),
      channelSamples: channelSamples ?? this.channelSamples,
      sampleRate: sampleRate ?? this.sampleRate,
      channelLabels: channelLabels ?? this.channelLabels,
      markers: markers ?? this.markers,
      source: source ?? this.source,
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
}
