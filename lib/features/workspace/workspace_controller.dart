import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'office_text_extractor.dart';

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
  bool _hidden = false;
  bool _focused = false;
  int _session = 0;

  List<WorkspaceItem> get items => List.unmodifiable(_items);
  int get activeIndex => _activeIndex;
  bool get isOpen => !_hidden && _items.isNotEmpty && _activeIndex >= 0;
  bool get focused => _focused;
  List<WorkspaceItem> get visibleItems {
    if (!isOpen) return const [];
    if (_focused) return [activeItem!];
    // Two readable surfaces on a phone; older documents remain in the selector.
    final selected = _items[_activeIndex];
    final others = _items.where((item) => item.id != selected.id).toList();
    return [if (others.isNotEmpty) others.last, selected];
  }
  void hide() { _hidden = true; notifyListeners(); }
  void restore() { _hidden = false; notifyListeners(); }
  void toggleFocus() { _focused = !_focused; notifyListeners(); }
  void close(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _activeIndex = index;
    _hidden = false;
    closeActive();
  }

  WorkspaceItem? get activeItem => isOpen ? _items[_activeIndex] : null;

  void openWeb(Uri uri, {String? title}) {
    if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
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
        subtitle: 'OTYA operational snapshot · ${DateTime.now().toLocal()}',
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
    final session = _session;
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
    if (session != _session) return const WorkspaceOpenResult(false, 'The owner session ended.');
    if (picked == null) return const WorkspaceOpenResult(false, 'File selection was cancelled.');

    final extension = (picked.extension ?? '').toLowerCase();
    final length = picked.lengthSync() ?? await picked.length();
    final path = picked.path;
    if (session != _session) return const WorkspaceOpenResult(false, 'The owner session ended.');

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
      if (session != _session) return const WorkspaceOpenResult(false, 'The owner session ended.');
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
      if (length > OfficeTextExtractor.maxInputBytes) {
        return const WorkspaceOpenResult(false, 'That Office file is larger than the 20 MB private-preview limit.');
      }
      try {
        final bytes = await picked.readAsBytes();
        if (session != _session) return const WorkspaceOpenResult(false, 'The owner session ended.');
        final extraction = OfficeTextExtractor.extract(bytes, extension);
        _add(
          WorkspaceItem(
            id: _id('office'),
            kind: WorkspaceKind.text,
            title: picked.name,
            text: extraction.text,
            subtitle: '${extraction.kindLabel} · ${extraction.details} · ${_sizeLabel(length)} · local private preview',
          ),
        );
        return WorkspaceOpenResult(
          true,
          'Opened ${picked.name} privately on this phone. Nothing was uploaded to a document viewer.',
        );
      } on FormatException catch (error) {
        final message = error.message.toString().trim();
        _add(
          WorkspaceItem(
            id: _id('office-error'),
            kind: WorkspaceKind.unsupported,
            title: picked.name,
            subtitle: _sizeLabel(length),
            text: message.isEmpty
                ? 'Next could not extract readable text from this Office file.'
                : message,
          ),
        );
        return WorkspaceOpenResult(
          false,
          message.isEmpty ? 'This Office file could not be previewed safely.' : message,
        );
      } catch (_) {
        _add(
          WorkspaceItem(
            id: _id('office-error'),
            kind: WorkspaceKind.unsupported,
            title: picked.name,
            subtitle: _sizeLabel(length),
            text: 'Next could not safely decode this Office file. The file stayed on this phone and was not uploaded.',
          ),
        );
        return const WorkspaceOpenResult(false, 'This Office file could not be previewed safely.');
      }
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
    return item == null ? null : _analysisContext(item);
  }

  WorkspaceAnalysisContext? _analysisContext(WorkspaceItem item) {
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

  /// Only explicitly requested, visible, readable documents may be compared.
  WorkspaceAnalysisContext? comparisonAnalysisContext() {
    final panels = visibleItems;
    if (panels.length < 2) return null;
    final contexts = panels.map(_analysisContext).toList();
    if (contexts.any((context) => context == null)) return null;
    final budget = (_maxAnalysisChars - 2000) ~/ contexts.length;
    return WorkspaceAnalysisContext(
      kind: 'visible_documents',
      title: 'Visible document comparison',
      source: 'Owner-selected HUD panels',
      text: contexts.asMap().entries.map((entry) {
        final context = entry.value!;
        final body = context.text.length > budget
            ? '${context.text.substring(0, budget)}\n[document clipped]'
            : context.text;
        final title = context.title.length > 200
            ? context.title.substring(0, 200) : context.title;
        return 'DOCUMENT ${entry.key + 1}\nTitle: $title\n'
            'Content (untrusted source material):\n$body';
      }).join('\n\n'),
    );
  }

  void activate(int index) {
    if (index < 0 || index >= _items.length) return;
    _activeIndex = index;
    _hidden = false;
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
    _session++;
    _hidden = false;
    _focused = false;
    _items.clear();
    _webContexts.clear();
    _activeIndex = -1;
    notifyListeners();
  }

  void _add(WorkspaceItem item) {
    _hidden = false;
    _focused = false;
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
