import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace supports same-screen web, PDF, image, text and report surfaces', () {
    final overlay = File('lib/features/workspace/workspace_overlay.dart').readAsStringSync();
    final controller = File('lib/features/workspace/workspace_controller.dart').readAsStringSync();
    final api = File('lib/core/network/next_owner_api.dart').readAsStringSync();

    expect(overlay, contains('WebViewWidget'));
    expect(overlay, contains('PdfViewer.file'));
    expect(overlay, contains('Image.file'));
    expect(overlay, contains('SelectionArea'));
    expect(overlay, contains("uri.scheme != 'https' && uri.scheme != 'http'"));

    expect(controller, contains("'docx'"));
    expect(controller, contains("'xlsx'"));
    expect(controller, contains("'pptx'"));
    expect(controller, contains('will not upload it to a public document viewer'));
    expect(controller, contains('_maxTabs = 6'));

    expect(api, contains("tool: 'workspace_file'"));
    expect(api, contains("tool: 'workspace_report'"));
    expect(api, contains("tool: 'workspace_news'"));
    expect(api, contains("tool: 'workspace_web_search'"));
    expect(api, contains('news.google.com'));
  });

  test('embedded browser is isolated from OTYA owner credentials', () {
    final overlay = File('lib/features/workspace/workspace_overlay.dart').readAsStringSync();
    expect(overlay, isNot(contains('X-OTYA-Owner-Grant')));
    expect(overlay, isNot(contains('Authorization')));
    expect(overlay, isNot(contains('INTERNAL_SECRET')));
    expect(overlay, isNot(contains('file://')));
    expect(overlay, isNot(contains('javascript:')));
  });
}
