import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Next owner enrollment opens Telegram app challenge without web OAuth', () {
    final auth = File('lib/core/auth/owner_auth_service.dart').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/petersmartlink/next/MainActivity.kt',
    ).readAsStringSync();
    final gate = File('lib/features/auth/owner_gate.dart').readAsStringSync();

    expect(auth, contains("scheme: 'tg'"));
    expect(auth, contains("'domain': 'OtyaPlayerBot'"));
    expect(auth, contains(r"'start': 'owner_$value'"));
    expect(auth, isNot(contains('/api/auth/telegram/start')));
    expect(auth, contains('telegram_challenge'));

    expect(activity, contains('isAllowedTelegramOwnerLink'));
    expect(activity, contains('setPackage("org.telegram.messenger")'));
    expect(activity, contains(r'Regex("^owner_[A-Za-z0-9_-]{16,80}$")'.replaceAll(r'\"', '"')));

    expect(gate, contains('_telegramChallenge'));
    expect(gate, contains('No browser sign-in is required for this step.'));
  });
}
