import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/nodes/time_frequency_node.dart';
import 'package:brainstory_gui/ui/visualization_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wavelet node uses bounded defaults and validates Nyquist', () async {
    final TimeFrequencyNodeType node = TimeFrequencyNodeType();
    expect(node.defaultParams['frequencyBins'], 40);
    expect(node.defaultParams['timeBins'], 240);

    final Dataset dataset = Dataset('wavelet-dataset', label: 'Wavelet');
    dataset.timeSeries = TimeSeriesData(
      samples: const <double>[0.0, 1.0, 0.0, -1.0],
      sampleRate: 100.0,
    );

    expect(
      () => node.run(dataset, <String, dynamic>{
        ...node.defaultParams,
        'fLow': 60.0,
      }),
      throwsArgumentError,
    );
  });

  test('multi-channel wavelet artifacts survive persistence', () {
    const TimeFrequencyData original = TimeFrequencyData(
      times: <double>[0.0, 0.5],
      frequencies: <double>[4.0, 8.0],
      powerMatrix: <List<double>>[
        <double>[1.0, 2.0],
        <double>[3.0, 4.0],
      ],
      channelPowerMatrices: <List<List<double>>>[
        <List<double>>[
          <double>[1.0, 2.0],
          <double>[3.0, 4.0],
        ],
        <List<double>>[
          <double>[5.0, 6.0],
          <double>[7.0, 8.0],
        ],
      ],
      channelLabels: <String>['Fz', 'Pz'],
      source: 'test',
    );

    final TimeFrequencyData restored = TimeFrequencyData.fromJson(
      original.toJson(),
    );

    expect(restored.channelLabels, original.channelLabels);
    expect(restored.channelPowerMatrices, original.channelPowerMatrices);
    expect(restored.powerForChannel(1)[1][1], 8.0);
  });

  testWidgets('wavelet viewer renders only the selected channel', (
    WidgetTester tester,
  ) async {
    final Dataset dataset = Dataset('dataset-1', label: 'Oddball');
    dataset.timeFrequency = const TimeFrequencyData(
      times: <double>[0.0, 0.5, 1.0],
      frequencies: <double>[5.0, 10.0],
      powerMatrix: <List<double>>[
        <double>[1.0, 2.0, 1.0],
        <double>[2.0, 4.0, 2.0],
      ],
      channelPowerMatrices: <List<List<double>>>[
        <List<double>>[
          <double>[1.0, 2.0, 1.0],
          <double>[2.0, 4.0, 2.0],
        ],
        <List<double>>[
          <double>[2.0, 1.0, 2.0],
          <double>[4.0, 2.0, 4.0],
        ],
      ],
      channelLabels: <String>['Fz', 'Pz'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: TimeFrequencyChart(
              datasets: <Dataset>[dataset],
              activeDatasetId: dataset.id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('time-frequency-heatmap')),
      findsOneWidget,
    );
    expect(find.text('2 frequencies × 3 time bins'), findsOneWidget);
    expect(find.text('Fz'), findsOneWidget);
    expect(find.text('Pz'), findsNothing);

    await tester.tap(find.text('Fz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pz').last);
    await tester.pumpAndSettle();

    expect(find.text('Pz'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('time-frequency-heatmap')),
      findsOneWidget,
    );
  });
}
