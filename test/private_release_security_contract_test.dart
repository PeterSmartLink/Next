import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private release never falls back to Android debug signing', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final workflow =
        File('.github/workflows/private-release.yml').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(
      gradle,
      isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
    );
    expect(gradle, contains('privateRelease'));
    expect(gradle, contains('key.properties'));

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('NEXT_KEYSTORE_BASE64'));
    expect(workflow, contains('apksigner'));
    expect(workflow, contains('Remove signing material'));

    expect(gitignore, contains('/android/key.properties'));
    expect(gitignore, contains('/android/app/*.jks'));
  });
}
