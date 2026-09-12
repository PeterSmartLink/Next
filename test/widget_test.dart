import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:next/app/next_app.dart';
import 'package:next/features/auth/owner_gate.dart';

void main() {
  testWidgets('Next opens through the secure owner gate', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NextApp()));

    expect(find.byType(OwnerGate), findsOneWidget);
    expect(find.text('Opening Next…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.text('Sign in to OTYA').evaluate().isNotEmpty ||
          find.text('Opening Next…').evaluate().isNotEmpty,
      isTrue,
    );
  });
}
