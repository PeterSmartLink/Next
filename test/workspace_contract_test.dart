import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace supports same-screen web, PDF, image, text, report, source and private Office surfaces', () {
    final overlay = File('lib/features/workspace/workspace_overlay.dart').readAsStringSync();
    final controller = File('lib/features/workspace/workspace_controller.dart').readAsStringSync();
    final office = File('lib/features/workspace/office_text_extractor.dart').readAsStringSync();
    final pdf = File('lib/features/workspace/pdf_text_extractor.dart').readAsStringSync();
    final api = File('lib/core/network/next_owner_api.dart').readAsStringSync();

    expect(overlay, contains('WebViewWidget'));
    expect(overlay, contains('PdfViewer.file'));
    expect(overlay, contains('Image.file'));
    expect(overlay, contains('SelectionArea'));
    expect(overlay, contains("uri.scheme != 'https' && uri.scheme != 'http'"));

    expect(controller, contains("'docx'"));
    expect(controller, contains("'xlsx'"));
    expect(controller, contains("'pptx'"));
    expect(controller, contains("'dart'"));
    expect(controller, contains("'kt'"));
    expect(controller, contains("'ts'"));
    expect(controller, contains("'py'"));
    expect(controller, contains("'sql'"));
    expect(controller, contains("'toml'"));
    expect(controller, contains("'properties'"));
    expect(controller, contains('OfficeTextExtractor.extract'));
    expect(controller, contains('PdfTextExtractor.extract'));
    expect(controller, contains("WorkspaceKind.pdf => 'local_pdf_text'"));
    expect(controller, contains("'local_source_file'"));
    expect(controller, contains('_redactSensitiveText'));
    expect(controller, contains('[private key redacted by Next]'));
    expect(controller, contains('local private preview'));
    expect(controller, contains('Nothing was uploaded to a document viewer'));
    expect(controller, isNot(contains('docs.google.com')));
    expect(controller, isNot(contains('view.officeapps.live.com')));
    expect(controller, contains('_maxTabs = 6'));

    expect(office, contains('word/document.xml'));
    expect(office, contains('ppt/slides/slide'));
    expect(office, contains('xl/worksheets/sheet'));
    expect(office, contains('maxExpandedBytes'));

    expect(pdf, contains('pdfrxFlutterInitialize'));
    expect(pdf, contains('PdfDocument.openFile'));
    expect(pdf, contains('page.loadText()'));
    expect(pdf, contains('await document.dispose()'));

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
