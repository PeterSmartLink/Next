import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'workspace_controller.dart';

class WorkspaceOverlayHost extends StatelessWidget {
  const WorkspaceOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = WorkspaceController.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (!controller.isOpen) return const SizedBox.shrink();
            final height = MediaQuery.sizeOf(context).height;
            return Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              height: height * 0.58,
              child: _WorkspacePanel(controller: controller),
            );
          },
        ),
      ],
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.activeItem;
    if (item == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Material(
          color: scheme.surface.withValues(alpha: 0.90),
          elevation: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                _WorkspaceHeader(controller: controller),
                const Divider(height: 1),
                Expanded(child: _WorkspaceBody(item: item)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.layers_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: controller.items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final item = controller.items[index];
                final selected = index == controller.activeIndex;
                return ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  avatar: Icon(_kindIcon(item.kind), size: 15),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onSelected: (_) => controller.activate(index),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Open file',
            onPressed: () async {
              await controller.pickFile();
            },
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Close current',
            onPressed: controller.closeActive,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({required this.item});

  final WorkspaceItem item;

  @override
  Widget build(BuildContext context) {
    return switch (item.kind) {
      WorkspaceKind.web => _WebPane(
          key: ValueKey(item.id),
          itemId: item.id,
          uri: item.uri!,
        ),
      WorkspaceKind.pdf => _PdfPane(path: item.path!),
      WorkspaceKind.image => _ImagePane(path: item.path!),
      WorkspaceKind.text || WorkspaceKind.report => _TextPane(item: item),
      WorkspaceKind.unsupported => _UnsupportedPane(item: item),
    };
  }
}

class _WebPane extends StatefulWidget {
  const _WebPane({
    super.key,
    required this.itemId,
    required this.uri,
  });

  final String itemId;
  final Uri uri;

  @override
  State<_WebPane> createState() => _WebPaneState();
}

class _WebPaneState extends State<_WebPane> {
  late final WebViewController _controller;
  bool _loading = true;
  String _host = '';

  @override
  void initState() {
    super.initState();
    _host = widget.uri.host;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            final uri = Uri.tryParse(url);
            if (!mounted) return;
            setState(() {
              _loading = true;
              _host = uri?.host ?? _host;
            });
          },
          onPageFinished: (url) {
            final uri = Uri.tryParse(url);
            if (!mounted) return;
            setState(() {
              _loading = false;
              _host = uri?.host ?? _host;
            });
            unawaited(_capturePageContext(url));
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  Future<void> _capturePageContext(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    try {
      final titleValue = await _controller.runJavaScriptReturningResult(
        'document.title || ""',
      );
      final textValue = await _controller.runJavaScriptReturningResult(
        'document.body ? document.body.innerText : ""',
      );
      WorkspaceController.instance.updateWebContext(
        itemId: widget.itemId,
        uri: uri,
        title: _decodeJavaScriptString(titleValue),
        text: _decodeJavaScriptString(textValue),
      );
    } catch (_) {
      // Some pages disallow extraction. Browsing remains available; Next simply
      // refuses to claim it can analyze page content it could not read.
    }
  }

  String _decodeJavaScriptString(Object value) {
    final raw = value.toString();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) return decoded;
    } catch (_) {}
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Back',
                onPressed: () async {
                  if (await _controller.canGoBack()) await _controller.goBack();
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Forward',
                onPressed: () async {
                  if (await _controller.canGoForward()) await _controller.goForward();
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh',
                onPressed: _controller.reload,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 13),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _host.isEmpty ? 'Web' : _host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    );
  }
}

class _PdfPane extends StatelessWidget {
  const _PdfPane({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return PdfViewer.file(path);
  }
}

class _ImagePane extends StatelessWidget {
  const _ImagePane({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.04),
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _TextPane extends StatelessWidget {
  const _TextPane({required this.item});

  final WorkspaceItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.subtitle?.isNotEmpty == true) ...[
              Text(
                item.subtitle!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              item.text ?? '',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedPane extends StatelessWidget {
  const _UnsupportedPane({required this.item});

  final WorkspaceItem item;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 38),
              const SizedBox(height: 14),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Text(
                item.text ?? 'This file cannot be previewed safely yet.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _kindIcon(WorkspaceKind kind) {
  return switch (kind) {
    WorkspaceKind.web => Icons.public_rounded,
    WorkspaceKind.pdf => Icons.picture_as_pdf_outlined,
    WorkspaceKind.image => Icons.image_outlined,
    WorkspaceKind.text => Icons.description_outlined,
    WorkspaceKind.report => Icons.analytics_outlined,
    WorkspaceKind.unsupported => Icons.shield_outlined,
  };
}
