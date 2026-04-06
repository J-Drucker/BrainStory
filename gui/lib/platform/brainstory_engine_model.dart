class AggregateSeriesStats {
  const AggregateSeriesStats({
    required this.mean,
    required this.standardDeviation,
  });

  final List<double> mean;
  final List<double> standardDeviation;
}
