import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:next/app/next_app.dart';

void main() {
  testWidgets('Next owner surface renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NextApp()));
    await tester.pump();

    expect(find.text('Next'), findsWidgets);
    expect(find.text('Good to see you.'), findsOneWidget);
    expect(find.text('Pulse'), findsOneWidget);
    expect(find.text('Talk to Next…'), findsOneWidget);
  });
}
