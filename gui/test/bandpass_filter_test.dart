import 'dart:math' as math;

import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/nodes/bandpass_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bandpass filtering is zero phase in the passband', () {
    const double sampleRate = 256.0;
    const double frequency = 10.0;
    final List<double> input = List<double>.generate(
      2048,
      (int index) => math.sin(2 * math.pi * frequency * index / sampleRate),
    );
    final List<double> output = applyBandpassFilter(
      input,
      sampleRate: sampleRate,
      lowCutHz: 1.0,
      highCutHz: 40.0,
      steepness: 0.5,
    );

    double inPhase = 0.0;
    double quadrature = 0.0;
    for (int index = 128; index < output.length - 128; index++) {
      final double angle = 2 * math.pi * frequency * index / sampleRate;
      inPhase += output[index] * math.sin(angle);
      quadrature += output[index] * math.cos(angle);
    }
    expect(quadrature.abs(), lessThan(inPhase.abs() * 1.0e-4));
  });

  test('bandpass filtering rejects an invalid passband', () {
    expect(
      () => applyBandpassFilter(
        <double>[0.0, 1.0, 0.0],
        sampleRate: 256.0,
        lowCutHz: 40.0,
        highCutHz: 20.0,
        steepness: 0.5,
      ),
      throwsArgumentError,
    );
  });

  test('bandpass filter defaults to standard steepness', () {
    expect(BandpassNodeType().defaultParams['steepness'], 0.5);
  });

  test(
    'bandpass filters continuous data and invalidates old segments',
    () async {
      final Dataset dataset = Dataset('continuous-filter');
      final TimeSeriesData source = TimeSeriesData(
        samples: List<double>.generate(
          512,
          (int index) => math.sin(2 * math.pi * 10.0 * index / 256.0),
        ),
        sampleRate: 256.0,
        source: 'test',
      );
      dataset.timeSeries = source;
      dataset.segmentedTimeSeries = SegmentedTimeSeriesData(
        segments: const <SignalSegmentData>[
          SignalSegmentData(
            startSeconds: 0,
            stopSeconds: 1,
            sourceStartSample: 0,
            sourceStopSampleExclusive: 256,
          ),
        ],
        sampleRate: 256.0,
        sourceTimeSeries: source,
      );

      await BandpassNodeType().run(dataset, BandpassNodeType().defaultParams);

      expect(dataset.timeSeries, isNotNull);
      expect(dataset.timeSeries!.sampleCount, 512);
      expect(dataset.segmentedTimeSeries, isNull);
    },
  );
}
