import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Next device controls stay narrow and permission-free', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/petersmartlink/next/MainActivity.kt',
    ).readAsStringSync();
    final api = File('lib/core/network/next_owner_api.dart').readAsStringSync();

    for (final permission in [
      'android.permission.CALL_PHONE',
      'android.permission.READ_CONTACTS',
      'android.permission.SEND_SMS',
      'android.permission.SYSTEM_ALERT_WINDOW',
      'android.permission.ACCESS_FINE_LOCATION',
    ]) {
      expect(manifest, isNot(contains(permission)));
    }

    expect(activity, contains('openSystemPanel'));
    expect(activity, contains('ACTION_INTERNET_CONNECTIVITY'));
    expect(activity, contains('ACTION_BLUETOOTH_SETTINGS'));
    expect(activity, contains('ACTION_APP_NOTIFICATION_SETTINGS'));
    expect(activity, contains('ACTION_APPLICATION_DETAILS_SETTINGS'));
    expect(activity, contains('blocked_panel'));

    expect(api, contains('device_system_panel'));
    expect(api, contains('Android keeps the final radio change under your control.'));
  });
}
