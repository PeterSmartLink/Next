import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next/features/workspace/workspace_controller.dart';
import 'package:next/features/workspace/workspace_overlay.dart';

void main() {
  final controller = WorkspaceController.instance;
  setUp(controller.closeAll);
  tearDown(controller.closeAll);

  test('starts empty and clears private content on session exit', () {
    expect(controller.isOpen, isFalse);
    controller.openText(title: 'Private', text: 'Owner data');
    controller.hide();
    expect(controller.isOpen, isFalse);
    expect(controller.activeAnalysisContext(), isNull);
    controller.restore();
    expect(controller.visibleItems.single.text, 'Owner data');
    controller.closeAll();
    expect(controller.items, isEmpty);
    controller.restore();
    expect(controller.isOpen, isFalse);
  });

  testWidgets('two reports display together, focus, hide and restore', (tester) async {
    controller.openText(title: 'First report', text: 'First report body');
    controller.openText(title: 'Second report', text: 'Second report body');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => WorkspacePanel(controller: controller),
    ))));
    expect(find.text('First report body'), findsOneWidget);
    expect(find.text('Second report body'), findsOneWidget);
    await tester.tap(find.byTooltip('Enlarge selected'));
    await tester.pump();
    expect(find.text('First report body'), findsNothing);
    expect(find.text('Second report body'), findsOneWidget);
    await tester.tap(find.byTooltip('Show together'));
    await tester.pump();
    expect(find.text('First report body'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide panels'));
    await tester.pump();
    expect(find.text('Second report body'), findsNothing);
    controller.restore();
    await tester.pump();
    expect(find.text('First report body'), findsOneWidget);
    await tester.tap(find.byTooltip('Close First report'));
    await tester.pump();
    expect(find.text('First report body'), findsNothing);
    expect(find.text('Second report body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('rejects credential-bearing web addresses', () {
    expect(() => controller.openWeb(Uri.parse('https://owner:secret@example.com')),
      throwsArgumentError);
  });
}
