import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

enum WorkspaceKind { web, pdf, image, text, report, unsupported }

class WorkspaceItem {
  const WorkspaceItem({
    required this.id,
    required this.kind,
    required this.title,
    this.uri,
    this.path,
    this.text,
    this.subtitle,
  });

  final String id;
  final WorkspaceKind kind;
  final String title;
  final Uri? uri;
  final String? path;
  final String? text;
  final String? subtitle;
}

class WorkspaceOpenResult {
  const WorkspaceOpenResult(this.ok, this.message);

  final bool ok;
  final String message;
}

class WorkspaceAnalysisContext {
  const WorkspaceAnalysisContext({
    required this.kind,
    required this.title,
    required this.source,
    required this.text,
  });

  final String kind;
  final String title;
  final String source;
  final String text;
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController._();

  static final WorkspaceController instance = WorkspaceController._();

  static const int _maxTabs = 6;
  static const int _maxTextBytes = 5 * 1024 * 1024;
  static const int _maxAnalysisChars = 18000;

  final List<WorkspaceItem> _items = [];
  final Map<String, WorkspaceAnalysisContext> _webContexts = {};
  int _activeIndex = -1;

  List<WorkspaceItem> get items => List.unmodifiable(_items);
  int get activeIndex => _activeIndex;
  bool get isOpen => _items.isNotEmpty && _activeIndex >= 0;
  WorkspaceItem? get activeItem => isOpen ? _items[_activeIndex] : null;

  void openWeb(Uri uri, {String? title}) {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw ArgumentError('Only http/https pages can open inside Next.');
    }
    _add(
      WorkspaceItem(
        id: _id('web'),
        kind: WorkspaceKind.web,
        title: (title?.trim().isNotEmpty ?? false) ? title!.trim() : (uri.host.isEmpty ? 'Web' : uri.host),
        uri: uri,
        subtitle: uri.toString(),
      ),
    );
  }

  void openReport(String title, Map<String, dynamic> report) {
    _add(
      WorkspaceItem(
        id: _id('report'),
        kind: WorkspaceKind.report,
        title: title.trim().isEmpty ? 'Report' : title.trim(),
        text: const JsonEncoder.withIndent('  ').convert(report),
        subtitle: 'Live OTYA operational data',
      ),
    );
  }

  void openText({required String title, required String text, String? subtitle}) {
    _add(
      WorkspaceItem(
        id: _id('text'),
        kind: WorkspaceKind.text,
        title: title,
        text: text,
        subtitle: subtitle,
      ),
    );
  }

  Future<WorkspaceOpenResult> pickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'txt',
        'md',
        'json',
        'log',
        'csv',
        'xml',
        'yaml',
        'yml',
        'docx',
        'xlsx',
        'pptx',
      ],
    );
    if (picked == null) return const WorkspaceOpenResult(false, 'File selection was cancelled.');

    final extension = (picked.extension ?? '').toLowerCase();
    final length = picked.lengthSync() ?? await picked.length();
    final path = picked.path;

    if (extension == 'pdf') {
      if (path == null || path.isEmpty) {
        return const WorkspaceOpenResult(false, 'Android could not provide a local PDF path for this file.');
      }
      _add(
        WorkspaceItem(
          id: _id('pdf'),
          kind: WorkspaceKind.pdf,
          title: picked.name,
          path: path,
          subtitle: _sizeLabel(length),
        ),
      );
      return WorkspaceOpenResult(true, 'Opened ${picked.name} in the Next workspace.');
    }

    if (const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)) {
      if (path == null || path.isEmpty) {
        return const WorkspaceOpenResult(false, 'Android could not provide a local image path for this file.');
      }
      _add(
        WorkspaceItem(
          id: _id('image'),
          kind: WorkspaceKind.image,
          title: picked.name,
          path: path,
          subtitle: _sizeLabel(length),
        ),
      );
      return WorkspaceOpenResult(true, 'Opened ${picked.name} in the Next workspace.');
    }

    if (const {'txt', 'md', 'json', 'log', 'csv', 'xml', 'yaml', 'yml'}.contains(extension)) {
      if (length > _maxTextBytes) {
        return const WorkspaceOpenResult(false, 'That text file is too large for the live workspace.');
      }
      final bytes = await picked.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      _add(
        WorkspaceItem(
          id: _id('text'),
          kind: WorkspaceKind.text,
          title: picked.name,
          text: text,
          subtitle: _sizeLabel(length),
        ),
      );
      return WorkspaceOpenResult(true, 'Opened ${picked.name} in the Next workspace.');
    }

    if (const {'docx', 'xlsx', 'pptx'}.contains(extension)) {
      _add(
        WorkspaceItem(
          id: _id('office'),
          kind: WorkspaceKind.unsupported,
          title: picked.name,
          subtitle: _sizeLabel(length),
          text: 'This Office file is private. Next will not upload it to a public document viewer. '
              'The private server-side Office preview pipeline is not connected yet, so the file is kept closed instead of leaking it to a third-party viewer.',
        ),
      );
      return WorkspaceOpenResult(
        false,
        '${picked.name} is recognized, but private Office preview is not connected yet.',
      );
    }

    return const WorkspaceOpenResult(false, 'That file type is not supported in the live workspace yet.');
  }

  void updateWebContext({
    required String itemId,
    required Uri uri,
    required String title,
    required String text,
  }) {
    if (!_items.any((item) => item.id == itemId && item.kind == WorkspaceKind.web)) return;
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      _webContexts.remove(itemId);
      return;
    }
    _webContexts[itemId] = WorkspaceAnalysisContext(
      kind: 'web_page',
      title: title.trim().isEmpty ? uri.host : title.trim(),
      source: uri.toString(),
      text: _clip(cleaned),
    );
  }

  WorkspaceAnalysisContext? activeAnalysisContext() {
    final item = activeItem;
    if (item == null) return null;
    if (item.kind == WorkspaceKind.web) return _webContexts[item.id];
    if (item.kind == WorkspaceKind.text || item.kind == WorkspaceKind.report) {
      final value = item.text?.trim() ?? '';
      if (value.isEmpty) return null;
      return WorkspaceAnalysisContext(
        kind: item.kind == WorkspaceKind.report ? 'otya_report' : 'local_text_file',
        title: item.title,
        source: item.subtitle ?? item.title,
        text: _clip(value),
      );
    }
    return null;
  }

  void activate(int index) {
    if (index < 0 || index >= _items.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void nextTab() {
    if (_items.length < 2) return;
    _activeIndex = (_activeIndex + 1) % _items.length;
    notifyListeners();
  }

  void previousTab() {
    if (_items.length < 2) return;
    _activeIndex = (_activeIndex - 1 + _items.length) % _items.length;
    notifyListeners();
  }

  void closeActive() {
    if (!isOpen) return;
    final removed = _items.removeAt(_activeIndex);
    _webContexts.remove(removed.id);
    if (_items.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= _items.length) {
      _activeIndex = _items.length - 1;
    }
    notifyListeners();
  }

  void closeAll() {
    if (_items.isEmpty) return;
    _items.clear();
    _webContexts.clear();
    _activeIndex = -1;
    notifyListeners();
  }

  void _add(WorkspaceItem item) {
    _items.add(item);
    while (_items.length > _maxTabs) {
      final removed = _items.removeAt(0);
      _webContexts.remove(removed.id);
    }
    _activeIndex = _items.length - 1;
    notifyListeners();
  }

  String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  static String _clip(String value) {
    if (value.length <= _maxAnalysisChars) return value;
    return '${value.substring(0, _maxAnalysisChars)}\n[content clipped by Next]';
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
