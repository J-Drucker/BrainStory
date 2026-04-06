import 'package:brainstory_gui/platform/brainstory_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aggregate engine bridge with fallback returns correct mean and spread', () {
    final AggregateSeriesStats? stats = computeAggregateSeriesStatsWithFallback(<List<double>>[
      <double>[1, 3, 5],
      <double>[3, 5, 7],
    ]);

    expect(stats, isNotNull);
    expect(stats!.mean, <double>[2, 4, 6]);
    expect(stats.standardDeviation[0], closeTo(1.0, 0.0001));
    expect(stats.standardDeviation[1], closeTo(1.0, 0.0001));
    expect(stats.standardDeviation[2], closeTo(1.0, 0.0001));
  });
}
