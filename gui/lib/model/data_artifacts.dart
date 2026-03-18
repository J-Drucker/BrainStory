class TimeSeriesData {
  const TimeSeriesData({
    required this.samples,
    required this.sampleRate,
    this.channelLabels = const <String>[],
    this.source = '',
  });

  final List<double> samples;
  final double sampleRate;
  final List<String> channelLabels;
  final String source;
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
