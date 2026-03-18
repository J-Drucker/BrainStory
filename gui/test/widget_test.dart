import 'package:flutter_test/flutter_test.dart';

import 'package:brainstory_gui/main.dart';

void main() {
  testWidgets('BrainStory renders its workspace shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BrainStoryApp());

    expect(find.text('Nodes'), findsOneWidget);
    expect(find.text('Datasets'), findsOneWidget);
  });
}
