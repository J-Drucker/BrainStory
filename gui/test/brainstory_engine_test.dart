import 'package:brainstory_gui/platform/brainstory_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'aggregate engine bridge with fallback returns correct mean and spread',
    () {
      final AggregateSeriesStats? stats =
          computeAggregateSeriesStatsWithFallback(<List<double>>[
            <double>[1, 3, 5],
            <double>[3, 5, 7],
          ]);

      expect(stats, isNotNull);
      expect(stats!.mean, <double>[2, 4, 6]);
      expect(stats.standardDeviation[0], closeTo(1.0, 0.0001));
      expect(stats.standardDeviation[1], closeTo(1.0, 0.0001));
      expect(stats.standardDeviation[2], closeTo(1.0, 0.0001));
    },
  );

  test('ICA projection uses the typed native output buffer', () {
    final List<List<double>>? projected = applyIcaNative(
      const <List<double>>[
        <double>[1, 2, 3],
        <double>[10, 20, 30],
      ],
      unmixingMatrix: const <List<double>>[
        <double>[1, 0],
        <double>[0, 0.1],
      ],
      channelMeans: const <double>[1, 10],
    );

    expect(projected, isNotNull);
    expect(projected![0], <double>[0, 1, 2]);
    expect(projected[1][0], closeTo(0, 1.0e-12));
    expect(projected[1][1], closeTo(1, 1.0e-12));
    expect(projected[1][2], closeTo(2, 1.0e-12));
  });
}
