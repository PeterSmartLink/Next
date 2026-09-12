import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:next/app/next_app.dart';

void main() {
  testWidgets('Next opens through the secure owner gate', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NextApp()));
    await tester.pump();

    expect(find.text('Next'), findsWidgets);
    expect(find.text('Your private OTYA intelligence'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Sign in to OTYA').evaluate().isNotEmpty ||
          find.text('Opening Next…').evaluate().isNotEmpty,
      isTrue,
    );
  });
}
