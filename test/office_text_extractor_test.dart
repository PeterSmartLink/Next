import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next/features/workspace/office_text_extractor.dart';

void main() {
  test('extracts DOCX paragraphs locally', () {
    final bytes = _zip({
      'word/document.xml': '''
<w:document xmlns:w="urn:test-word">
  <w:body>
    <w:p><w:r><w:t>Hello Next</w:t></w:r></w:p>
    <w:p><w:r><w:t>Private document</w:t></w:r></w:p>
  </w:body>
</w:document>
''',
    });

    final result = OfficeTextExtractor.extract(bytes, 'docx');
    expect(result.kindLabel, 'DOCX');
    expect(result.text, contains('Hello Next'));
    expect(result.text, contains('Private document'));
  });

  test('extracts PPTX slide text locally', () {
    final bytes = _zip({
      'ppt/slides/slide1.xml': '''
<p:sld xmlns:p="urn:test-presentation" xmlns:a="urn:test-drawing">
  <p:cSld><a:t>First slide</a:t><a:t>Important result</a:t></p:cSld>
</p:sld>
''',
    });

    final result = OfficeTextExtractor.extract(bytes, 'pptx');
    expect(result.kindLabel, 'PPTX');
    expect(result.text, contains('Slide 1'));
    expect(result.text, contains('Important result'));
  });

  test('resolves XLSX shared strings locally', () {
    final bytes = _zip({
      'xl/sharedStrings.xml': '''
<sst xmlns="urn:test-sheet">
  <si><t>Name</t></si>
  <si><t>OTYA</t></si>
</sst>
''',
      'xl/worksheets/sheet1.xml': '''
<worksheet xmlns="urn:test-sheet"><sheetData>
  <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
  <row r="2"><c r="A2"><v>42</v></c></row>
</sheetData></worksheet>
''',
    });

    final result = OfficeTextExtractor.extract(bytes, 'xlsx');
    expect(result.kindLabel, 'XLSX');
    expect(result.text, contains('Name\tOTYA'));
    expect(result.text, contains('42'));
  });
}

List<int> _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return ZipEncoder().encodeBytes(archive);
}
