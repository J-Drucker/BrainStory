import 'dart:math' as math;

import 'package:brainstory_gui/nodes/psd_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PSD is invariant to a constant signal offset', () {
    const double sampleRate = 256.0;
    final List<double> centered = List<double>.generate(
      256,
      (int index) => math.sin(2 * math.pi * 12.0 * index / sampleRate),
    );
    final List<double> offset = centered
        .map((double sample) => sample + 10000.0)
        .toList(growable: false);

    final SpectrumResult centeredSpectrum = computeSpectrum(
      centered,
      sampleRate: sampleRate,
      fLow: 1.0,
      fHigh: 40.0,
      averageSegments: true,
    );
    final SpectrumResult offsetSpectrum = computeSpectrum(
      offset,
      sampleRate: sampleRate,
      fLow: 1.0,
      fHigh: 40.0,
      averageSegments: true,
    );

    expect(offsetSpectrum.freqs, centeredSpectrum.freqs);
    for (int index = 0; index < centeredSpectrum.power.length; index++) {
      expect(
        offsetSpectrum.power[index],
        closeTo(centeredSpectrum.power[index], 1.0e-8),
      );
    }
  });
}
