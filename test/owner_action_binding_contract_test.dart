import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Next binds owner approval to the exact action shown on this phone', () {
    final api = File('lib/core/network/next_owner_api.dart').readAsStringSync();
    final home = File('lib/features/home/home_screen.dart').readAsStringSync();

    expect(api, contains('_pendingOwnerAction'));
    expect(api, contains('/api/owner/ai/action/approve'));
    expect(api, contains('/api/owner/ai/action/cancel'));
    expect(api, contains("'approval_token': token"));
    expect(api, contains('There is no action currently displayed on this phone to approve.'));

    final approvalGuard = api.indexOf('if (_isApprovalIntent(normalized))');
    final genericChat = api.indexOf("'/api/owner/ai/chat'");
    expect(approvalGuard, greaterThanOrEqualTo(0));
    expect(genericChat, greaterThan(approvalGuard));

    final biometric = home.indexOf('OwnerBiometric.confirmSensitiveAction');
    final approvedSend = home.indexOf("_sendToNext('approve', confirmedApproval: true)");
    expect(biometric, greaterThanOrEqualTo(0));
    expect(approvedSend, greaterThan(biometric));
  });
}
