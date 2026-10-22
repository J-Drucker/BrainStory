import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/ui/bridge_viewer.dart';
import 'package:brainstory_gui/ui/viewer_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bridge viewer uses shared signal-viewer chrome', (
    WidgetTester tester,
  ) async {
    final Dataset dataset = _bridgeDataset();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 1100,
            height: 700,
            child: BridgeViewer(
              dataset: dataset,
              params: <String, dynamic>{},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ViewerTraceSurface), findsOneWidget);
    expect(find.byType(ViewerScaleCluster), findsNothing);
    expect(find.textContaining('Spacing'), findsNothing);
    expect(find.byType(ViewerTimeAxisBar), findsOneWidget);
    expect(find.byType(ViewerTimelineBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('bridge-butterfly-plot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-score-axis')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-color-legend')),
      findsOneWidget,
    );
    expect(find.text('Electrode distance'), findsOneWidget);
    expect(find.text('More\nsimilar'), findsOneWidget);
    final ViewerScalePillMenu<double> timeControl = tester.widget(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is ViewerScalePillMenu<double> && widget.label == 'Time',
      ),
    );
    expect(timeControl.currentValue, 4.0);
  });

  testWidgets('hovering a bridge trace reveals both channel names', (
    WidgetTester tester,
  ) async {
    final Dataset dataset = _bridgeDataset();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 1100,
            height: 700,
            child: BridgeViewer(
              dataset: dataset,
              params: <String, dynamic>{},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    final Finder region = find.byKey(
      const ValueKey<String>('bridge-trace-region'),
    );
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getTopLeft(region) + const Offset(20, 12));
    await tester.pump();

    expect(find.textContaining('Fz / Cz'), findsOneWidget);
  });

  testWidgets('bridge colors fall back to imported channel number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 1100,
            height: 700,
            child: BridgeViewer(
              dataset: _bridgeDataset(includeCoordinates: false),
              params: <String, dynamic>{},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mean channel number'), findsOneWidget);
  });

  testWidgets('bridge result retains coordinates without local signal', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 1100,
            height: 700,
            child: BridgeViewer(
              dataset: _bridgeDataset(coordinatesOnTimeSeries: false),
              params: <String, dynamic>{},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Electrode distance'), findsOneWidget);
  });

  testWidgets('partial coordinates retain distance coloring where possible', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 1100,
            height: 700,
            child: BridgeViewer(
              dataset: _bridgeDataset(omitPzCoordinate: true),
              params: <String, dynamic>{},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Electrode distance'), findsOneWidget);
    expect(find.text('2 pair(s) use channel number'), findsOneWidget);
  });

  testWidgets('distance mode shows electrical distance by spatial distance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 1100,
            height: 700,
            child: BridgeViewer(
              dataset: _bridgeDataset(),
              params: <String, dynamic>{'bridgeViewer.mode': 'scatter'},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('bridge-distance-scatter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bridge-regression-label')),
      findsOneWidget,
    );
    expect(find.textContaining('r = '), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('bridge-score-axis')),
      findsNothing,
    );
    expect(find.byType(ViewerTimeAxisBar), findsNothing);
    expect(find.byType(ViewerTimelineBar), findsNothing);
  });
}

Dataset _bridgeDataset({
  bool includeCoordinates = true,
  bool coordinatesOnTimeSeries = true,
  bool omitPzCoordinate = false,
}) {
  final Dataset dataset = Dataset('bridge', label: 'Bridge example');
  dataset.timeSeries = TimeSeriesData(
    channelSamples: <List<double>>[
      <double>[0, 1, 2, 3, 4, 5, 6, 7],
      <double>[0, 1, 2, 3, 4, 5, 6, 7],
      <double>[1, 2, 3, 4, 5, 6, 7, 8],
    ],
    sampleRate: 2,
    channelLabels: <String>['Fz', 'Cz', 'Pz'],
    channelCoordinates: includeCoordinates && coordinatesOnTimeSeries
        ? <String, ChannelCoordinate>{
            'Fz': ChannelCoordinate(label: 'Fz', x: 0, y: 0.5, z: 0.8),
            'Cz': ChannelCoordinate(label: 'Cz', x: 0, y: 0, z: 1),
            if (!omitPzCoordinate)
              'Pz': ChannelCoordinate(label: 'Pz', x: 0, y: -0.5, z: 0.8),
          }
        : const <String, ChannelCoordinate>{},
  );
  dataset.bridgeDetection = BridgeDetectionData(
    channelLabels: <String>['Fz', 'Cz', 'Pz'],
    epochSampleCount: 2,
    intervalSampleCount: 2,
    sampleRate: 2,
    frames: <BridgeEpochFrameData>[
      BridgeEpochFrameData(
        epochIndex: 0,
        startSample: 0,
        endSampleExclusive: 2,
        pairValues: <double>[10, 3, 5],
        pairElectricalDistances: <double>[0.10, 1.0, 0.50],
      ),
      BridgeEpochFrameData(
        epochIndex: 1,
        startSample: 2,
        endSampleExclusive: 4,
        pairValues: <double>[11, 4, 6],
        pairElectricalDistances: <double>[0.20, 1.1, 0.60],
      ),
    ],
    distanceNormalizedPairs: <bool>[true, true, true],
    channelCoordinates: includeCoordinates
        ? <String, ChannelCoordinate>{
            'Fz': const ChannelCoordinate(label: 'Fz', x: 0, y: 0.5, z: 0.8),
            'Cz': const ChannelCoordinate(label: 'Cz', x: 0, y: 0, z: 1),
            if (!omitPzCoordinate)
              'Pz': const ChannelCoordinate(label: 'Pz', x: 0, y: -0.5, z: 0.8),
          }
        : const <String, ChannelCoordinate>{},
  );
  return dataset;
}
