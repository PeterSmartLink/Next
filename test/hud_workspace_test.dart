import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next/features/workspace/workspace_controller.dart';
import 'package:next/features/workspace/workspace_overlay.dart';

void main() {
  testWidgets('HUD panel switches reports and closes the current tab', (tester) async {
    final controller = WorkspaceController.instance;
    controller.closeAll();
    addTearDown(controller.closeAll);
    controller.openText(title: 'First report', text: 'First report body');
    controller.openText(title: 'Second report', text: 'Second report body');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => WorkspacePanel(controller: controller),
    ))));
    expect(find.text('Second report body'), findsOneWidget);
    await tester.tap(find.text('First report'));
    await tester.pumpAndSettle();
    expect(find.text('First report body'), findsOneWidget);
    await tester.tap(find.byTooltip('Close current'));
    await tester.pumpAndSettle();
    expect(find.text('Second report body'), findsOneWidget);
  });
}
