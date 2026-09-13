import 'package:pdfrx/pdfrx.dart';

class PdfTextExtraction {
  const PdfTextExtraction({
    required this.text,
    required this.pagesRead,
    required this.totalPages,
    required this.clipped,
  });

  final String text;
  final int pagesRead;
  final int totalPages;
  final bool clipped;
}

class PdfTextExtractor {
  static const int maxPages = 80;
  static const int maxOutputChars = 160000;

  static Future<PdfTextExtraction?> extract(String path) async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(
      path,
      useProgressiveLoading: false,
    );

    try {
      final totalPages = document.pages.length;
      final pageLimit = totalPages < maxPages ? totalPages : maxPages;
      final buffer = StringBuffer();
      var pagesRead = 0;
      var clipped = totalPages > maxPages;

      for (var index = 0; index < pageLimit; index++) {
        final page = document.pages[index];
        final raw = await page.loadText();
        final text = raw?.fullText.trim() ?? '';
        pagesRead++;
        if (text.isEmpty) continue;

        final label = 'Page ${index + 1}';
        final remaining = maxOutputChars - buffer.length;
        if (remaining <= label.length + 4) {
          clipped = true;
          break;
        }

        final pageBlock = '$label\n$text\n\n';
        if (pageBlock.length <= remaining) {
          buffer.write(pageBlock);
        } else {
          buffer.write(pageBlock.substring(0, remaining));
          clipped = true;
          break;
        }
      }

      final value = buffer.toString().trim();
      if (value.isEmpty) return null;
      return PdfTextExtraction(
        text: clipped ? '$value\n\n[PDF text preview clipped by Next]' : value,
        pagesRead: pagesRead,
        totalPages: totalPages,
        clipped: clipped,
      );
    } finally {
      await document.dispose();
    }
  }
}
