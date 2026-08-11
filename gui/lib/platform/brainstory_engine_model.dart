class AggregateSeriesStats {
  const AggregateSeriesStats({
    required this.mean,
    required this.standardDeviation,
  });

  final List<double> mean;
  final List<double> standardDeviation;
}

class NativeSpectrumResult {
  const NativeSpectrumResult({required this.frequencies, required this.power});

  final List<double> frequencies;
  final List<double> power;
}
