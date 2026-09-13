import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class OfficeTextExtraction {
  const OfficeTextExtraction({
    required this.text,
    required this.kindLabel,
    required this.details,
  });

  final String text;
  final String kindLabel;
  final String details;
}

class OfficeTextExtractor {
  static const int maxInputBytes = 20 * 1024 * 1024;
  static const int maxExpandedBytes = 80 * 1024 * 1024;
  static const int maxOutputChars = 240000;

  static OfficeTextExtraction extract(
    Uint8List bytes,
    String extension,
  ) {
    if (bytes.length > maxInputBytes) {
      throw const FormatException('Office file is larger than the 20 MB private-preview limit.');
    }

    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final expanded = archive.files.fold<int>(0, (sum, file) => sum + file.size);
    if (expanded > maxExpandedBytes) {
      archive.clearSync();
      throw const FormatException('Office file expands beyond the safe private-preview limit.');
    }

    try {
      return switch (extension.toLowerCase()) {
        'docx' => _docx(archive),
        'pptx' => _pptx(archive),
        'xlsx' => _xlsx(archive),
        _ => throw const FormatException('Unsupported Office file type.'),
      };
    } finally {
      archive.clearSync();
    }
  }

  static OfficeTextExtraction _docx(Archive archive) {
    final document = _xml(archive, 'word/document.xml');
    if (document == null) {
      throw const FormatException('This DOCX does not contain a readable document body.');
    }

    final lines = <String>[];
    for (final paragraph in document.descendantElements.where((e) => e.localName == 'p')) {
      final text = paragraph.descendantElements
          .where((e) => e.localName == 't')
          .map((e) => e.innerText)
          .join()
          .trim();
      if (text.isNotEmpty) lines.add(text);
    }

    return OfficeTextExtraction(
      text: _finish(lines.join('\n\n')),
      kindLabel: 'DOCX',
      details: '${lines.length} readable paragraph${lines.length == 1 ? '' : 's'}',
    );
  }

  static OfficeTextExtraction _pptx(Archive archive) {
    final slides = archive.files
        .where((file) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name))
        .toList()
      ..sort((a, b) => _numberIn(a.name).compareTo(_numberIn(b.name)));
    if (slides.isEmpty) {
      throw const FormatException('This PPTX does not contain readable slides.');
    }

    final output = <String>[];
    var readableSlides = 0;
    for (final slide in slides) {
      final document = _xmlFile(slide);
      if (document == null) continue;
      final parts = document.descendantElements
          .where((e) => e.localName == 't')
          .map((e) => e.innerText.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;
      readableSlides++;
      output.add('Slide ${_numberIn(slide.name)}\n${parts.join('\n')}');
    }

    return OfficeTextExtraction(
      text: _finish(output.join('\n\n')),
      kindLabel: 'PPTX',
      details: '$readableSlides readable slide${readableSlides == 1 ? '' : 's'}',
    );
  }

  static OfficeTextExtraction _xlsx(Archive archive) {
    final shared = _sharedStrings(archive);
    final sheets = archive.files
        .where((file) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name))
        .toList()
      ..sort((a, b) => _numberIn(a.name).compareTo(_numberIn(b.name)));
    if (sheets.isEmpty) {
      throw const FormatException('This XLSX does not contain readable worksheets.');
    }

    final output = <String>[];
    var readableSheets = 0;
    for (final sheet in sheets) {
      final document = _xmlFile(sheet);
      if (document == null) continue;
      final rows = <String>[];
      for (final row in document.descendantElements.where((e) => e.localName == 'row')) {
        final values = <String>[];
        for (final cell in row.childElements.where((e) => e.localName == 'c')) {
          final type = cell.getAttribute('t') ?? '';
          String value = '';
          if (type == 'inlineStr') {
            value = cell.descendantElements
                .where((e) => e.localName == 't')
                .map((e) => e.innerText)
                .join();
          } else {
            final raw = cell.descendantElements
                .where((e) => e.localName == 'v')
                .map((e) => e.innerText)
                .firstOrNull;
            if (raw != null) {
              if (type == 's') {
                final index = int.tryParse(raw);
                value = index != null && index >= 0 && index < shared.length
                    ? shared[index]
                    : raw;
              } else {
                value = raw;
              }
            }
          }
          values.add(value.trim());
        }
        if (values.any((value) => value.isNotEmpty)) rows.add(values.join('\t'));
      }
      if (rows.isEmpty) continue;
      readableSheets++;
      output.add('Sheet ${_numberIn(sheet.name)}\n${rows.join('\n')}');
    }

    return OfficeTextExtraction(
      text: _finish(output.join('\n\n')),
      kindLabel: 'XLSX',
      details: '$readableSheets readable sheet${readableSheets == 1 ? '' : 's'}',
    );
  }

  static List<String> _sharedStrings(Archive archive) {
    final document = _xml(archive, 'xl/sharedStrings.xml');
    if (document == null) return const [];
    return document.descendantElements
        .where((e) => e.localName == 'si')
        .map((item) => item.descendantElements
            .where((e) => e.localName == 't')
            .map((e) => e.innerText)
            .join())
        .toList(growable: false);
  }

  static XmlDocument? _xml(Archive archive, String name) {
    final file = archive.findFile(name);
    return file == null ? null : _xmlFile(file);
  }

  static XmlDocument? _xmlFile(ArchiveFile file) {
    final bytes = file.readBytes();
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  static int _numberIn(String value) {
    final match = RegExp(r'(\d+)').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static String _finish(String value) {
    final normalized = value
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
        .trim();
    if (normalized.isEmpty) {
      throw const FormatException('No readable text was found in this Office file.');
    }
    if (normalized.length <= maxOutputChars) return normalized;
    return '${normalized.substring(0, maxOutputChars)}\n\n[preview clipped by Next]';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
