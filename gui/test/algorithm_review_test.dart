import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_state.dart';
import 'package:brainstory_gui/nodes/algorithm_review.dart';
import 'package:brainstory_gui/nodes/bandpass_node.dart';
import 'package:brainstory_gui/nodes/gaussian_mixture_node.dart';
import 'package:brainstory_gui/nodes/ica_component_rejection_node.dart';
import 'package:brainstory_gui/nodes/matrix_transform_nodes.dart';
import 'package:brainstory_gui/nodes/node_type.dart';
import 'package:brainstory_gui/nodes/psd_node.dart';
import 'package:brainstory_gui/nodes/resample_node.dart';
import 'package:brainstory_gui/nodes/segmentation_node.dart';
import 'package:brainstory_gui/nodes/time_frequency_node.dart';

void main() {
  test('major numerical nodes expose auditable algorithm descriptions', () {
    final reviews = <AlgorithmReview?>[
      BandpassNodeType().algorithmReview,
      PSDNodeType().algorithmReview,
      TimeFrequencyNodeType().algorithmReview,
      ICANodeType().algorithmReview,
      IcaComponentRejectionNodeType().algorithmReview,
      SegmentationNodeType().algorithmReview,
      ResampleNodeType().algorithmReview,
      GaussianMixtureNodeType().algorithmReview,
    ];

    for (final review in reviews) {
      expect(review, isNotNull);
      expect(review!.summary, isNotEmpty);
      expect(review.procedure, isNotEmpty);
      expect(review.assumptions, isNotEmpty);
      expect(review.sourceFiles, isNotEmpty);
      expect(review.testFiles, isNotEmpty);
    }
  });

  test('review text discloses scientifically important limitations', () {
    expect(
      nodeAlgorithmReviews['PSD']!.assumptions.join(' '),
      contains('not a calibrated power spectral density per Hz'),
    );
    expect(
      nodeAlgorithmReviews['Resample']!.assumptions.join(' '),
      contains('No anti-alias low-pass filter'),
    );
    expect(
      nodeAlgorithmReviews['Segmentation']!.procedure.join(' '),
      contains('each segment and each channel'),
    );
  });

  testWidgets('node configuration exposes the algorithm review tab', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final BandpassNodeType node = BandpassNodeType();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: node.buildConfigWidget(
            node.defaultParams,
            (_) {},
            datasets: const <String, Dataset>{},
            availableDatasetIds: const <String>{},
            datasetSourceLabels: const <String, List<String>>{},
            processedDatasetStates: const <String, DatasetState>{},
            portStatusSummary: const NodePortStatusSummary(
              inputs: <NodePortDatasetSummary>[],
              outputs: <NodePortDatasetSummary>[],
            ),
            processingSteps: const <String>[],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Algorithm'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('node-algorithm-tab-content')),
      findsOneWidget,
    );
    expect(find.text('Assumptions and limitations'), findsOneWidget);
    expect(find.text('engine/src/filtering.rs'), findsAtLeastNWidgets(1));
  });
}
