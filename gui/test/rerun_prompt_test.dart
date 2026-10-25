import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_state.dart';
import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/ui/canvas_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'completed nodes require confirmation before results are cleared',
    (WidgetTester tester) async {
      final CanvasLogic logic = CanvasLogic(runUiYieldsEnabled: false);
      final Dataset dataset = Dataset('dataset-1', label: 'Recording');
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      final node = logic.nodes.single;
      node.datasetStates[dataset.id] = DatasetState.done;

      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      final Future<bool> canceled = logic.promptClearCompletedResultsBeforeRun(
        context: context,
        node: node,
        datasetIds: <String>{dataset.id},
        update: () {},
      );
      await tester.pumpAndSettle();
      expect(find.text('Results are already current'), findsOneWidget);
      expect(find.text('Clear results and re-run'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await canceled, isFalse);
      expect(node.datasetStates[dataset.id], DatasetState.done);
    },
  );
}
