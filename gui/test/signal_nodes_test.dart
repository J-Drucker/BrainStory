import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/nodes/bandpass_node.dart';
import 'package:brainstory_gui/nodes/export_edf_node.dart';
import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/nodes/psd_node.dart';
import 'package:brainstory_gui/nodes/resample_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseSignalText infers sample rate from a time column', () {
    const String contents = '''
time,value
0,0.10
10,0.20
20,0.15
30,0.18
''';

    final ParsedSignalData parsed = parseSignalText(
      contents,
      fallbackSampleRate: 128.0,
      sourceDescription: 'inline.csv',
    );

    expect(parsed.samples.length, 4);
    expect(parsed.sampleRate, closeTo(100.0, 0.01));
    expect(parsed.channelLabels, <String>['value']);
    expect(parsed.samples[1], closeTo(0.20, 0.0001));
  });

  test('parseSignalText parses multiple channels from a time series table', () {
    const String contents = '''
time,Fz,Cz
0,1.0,10.0
10,2.0,20.0
20,3.0,30.0
''';

    final ParsedSignalData parsed = parseSignalText(
      contents,
      fallbackSampleRate: 128.0,
      sourceDescription: 'multichannel.csv',
    );

    expect(parsed.channelSamples.length, 2);
    expect(parsed.channelLabels, <String>['Fz', 'Cz']);
    expect(parsed.channelSamples[1], <double>[10.0, 20.0, 30.0]);
  });

  test('resampleSignal updates the sample rate and output length', () {
    final List<double> input = List<double>.generate(
      200,
      (int i) => math.sin(2 * math.pi * 8 * (i / 200.0)),
    );

    final List<double> output = resampleSignal(
      input,
      sourceSampleRate: 200.0,
      targetSampleRate: 100.0,
      method: 'cubic_spline',
    );

    expect(output.length, 100);
    expect(output.first, closeTo(input.first, 0.05));
    expect(output[25], closeTo(0.0, 0.25));
  });

  test('suppressSpikes replaces isolated outliers with neighborhood median', () {
    final List<double> cleaned = suppressSpikes(<double>[
      0,
      0,
      0,
      25,
      0,
      0,
      0,
    ]);

    expect(cleaned[3], closeTo(0.0, 0.001));
  });

  test('parseSignalText falls back to the provided sample rate', () {
    const String contents = '''
1.2
0.8
0.4
-0.1
''';

    final ParsedSignalData parsed = parseSignalText(
      contents,
      fallbackSampleRate: 256.0,
      sourceDescription: 'single-column.txt',
    );

    expect(parsed.samples, <double>[1.2, 0.8, 0.4, -0.1]);
    expect(parsed.sampleRate, 256.0);
  });

  test('applyBandpassFilter changes the signal while preserving length', () {
    final List<double> input = List<double>.generate(
      512,
      (int i) => (i.isEven ? 1.0 : -1.0) + (i / 512.0),
    );

    final List<double> output = applyBandpassFilter(
      input,
      sampleRate: 256.0,
      lowCutHz: 1.0,
      highCutHz: 40.0,
      steepness: 0.8,
      notchHz: 60.0,
    );

    expect(output.length, input.length);
    expect(output.first, isNot(closeTo(input.first, 0.0001)));
  });

  test('computeSpectrum identifies the dominant frequency of a sine wave', () {
    const double sampleRate = 256.0;
    const double targetFrequency = 12.0;
    final List<double> samples = List<double>.generate(256, (int i) {
      final double t = i / sampleRate;
      return math.sin(2 * math.pi * targetFrequency * t);
    });

    final SpectrumResult spectrum = computeSpectrum(
      samples,
      sampleRate: sampleRate,
      fLow: 1.0,
      fHigh: 40.0,
      averageSegments: true,
    );

    final int peakIndex = spectrum.power.indexWhere(
      (double value) => value == spectrum.power.reduce(math.max),
    );
    expect(spectrum.freqs[peakIndex], closeTo(targetFrequency, 1.5));
  });

  test('loadDatasetSignal imports the sample EDF fixture', () async {
    final ParsedSignalData parsed = await loadDatasetSignal(
      '..\\tests\\Zhao_Alex_2024-09-24_16-47-37_highpass_Segment_0.edf',
      fallbackSampleRate: 256.0,
    );

    expect(parsed.samples, isNotEmpty);
    expect(parsed.sampleRate, greaterThan(0));
    expect(parsed.sourceDescription, contains('.edf'));
  });

  test('loadDatasetSignal imports the sample CSV fixture', () async {
    final ParsedSignalData parsed = await loadDatasetSignal(
      '..\\tests\\test_data.csv',
      fallbackSampleRate: 256.0,
    );

    expect(parsed.samples, isNotEmpty);
    expect(parsed.sampleRate, greaterThan(0));
  });

  test('buildSingleChannelEdfBytes round-trips through EDF parsing', () async {
    final List<double> samples = List<double>.generate(
      128,
      (int i) => math.sin(2 * math.pi * 8 * (i / 128.0)),
    );

    final List<int> bytes = buildSingleChannelEdfBytes(
      samples: samples,
      sampleRate: 128.0,
      label: 'RoundTrip',
    );
    final ParsedSignalData parsed = parseEdfBytes(
      Uint8List.fromList(bytes),
      sourceDescription: 'memory.edf',
    );

    expect(parsed.samples.length, samples.length);
    expect(parsed.sampleRate, closeTo(128.0, 0.001));
    expect(parsed.samples.first, closeTo(samples.first, 0.05));
  });

  test('buildEdfBytes round-trips multiple channels through EDF parsing', () async {
    final List<double> channelOne = List<double>.generate(
      64,
      (int i) => math.sin(2 * math.pi * 6 * (i / 128.0)),
    );
    final List<double> channelTwo = List<double>.generate(
      64,
      (int i) => math.cos(2 * math.pi * 10 * (i / 128.0)),
    );

    final List<int> bytes = buildEdfBytes(
      channelSamples: <List<double>>[channelOne, channelTwo],
      sampleRate: 128.0,
      labels: const <String>['Fz', 'Cz'],
    );
    final ParsedSignalData parsed = parseEdfBytes(
      Uint8List.fromList(bytes),
      sourceDescription: 'multichannel.edf',
    );

    expect(parsed.channelSamples.length, 2);
    expect(parsed.channelLabels, <String>['Fz', 'Cz']);
    expect(parsed.channelSamples.first.first, closeTo(channelOne.first, 0.05));
    expect(parsed.channelSamples.last.first, closeTo(channelTwo.first, 0.05));
  });

  test('resolveEdfExportFile builds a filename next to the source file', () {
    final Dataset dataset = Dataset(
      '1',
      label: 'My Signal',
      path: 'C:\\temp\\example.csv',
    );

    final File target = resolveEdfExportFile(
      dataset: dataset,
      outputDirectory: '',
      filenameSuffix: '_brainstory',
    );

    expect(target.path, 'C:\\temp\\example_brainstory.edf');
  });
}
