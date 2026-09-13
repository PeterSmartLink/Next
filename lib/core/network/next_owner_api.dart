import 'package:dio/dio.dart';

import '../../features/workspace/workspace_controller.dart';
import '../auth/owner_auth_service.dart';
import '../platform/next_platform_bridge.dart';

class OwnerAccessExpired implements Exception {
  const OwnerAccessExpired();
}

class NextChatReply {
  const NextChatReply({
    required this.answer,
    this.conversationId,
    this.tool,
    this.approvalRequired = false,
    this.action,
  });

  final String answer;
  final String? conversationId;
  final String? tool;
  final bool approvalRequired;
  final Map<String, dynamic>? action;
}

class NextOwnerApi {
  NextOwnerApi(this._auth)
      : _dio = Dio(
          BaseOptions(
            baseUrl: const String.fromEnvironment(
              'OTYA_BASE_URL',
              defaultValue: 'https://petersmartlink.com',
            ),
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 45),
            sendTimeout: const Duration(seconds: 20),
            responseType: ResponseType.json,
            headers: const {'Accept': 'application/json'},
            validateStatus: (_) => true,
          ),
        );

  final OwnerAuthService _auth;
  final Dio _dio;
  Map<String, dynamic>? _pendingOwnerAction;

  static const Map<String, ({String label, String packageName})> _localApps = {
    'whatsapp': (label: 'WhatsApp', packageName: 'com.whatsapp'),
    'telegram': (label: 'Telegram', packageName: 'org.telegram.messenger'),
    'youtube': (label: 'YouTube', packageName: 'com.google.android.youtube'),
    'spotify': (label: 'Spotify', packageName: 'com.spotify.music'),
    'gmail': (label: 'Gmail', packageName: 'com.google.android.gm'),
    'maps': (label: 'Google Maps', packageName: 'com.google.android.apps.maps'),
    'google maps': (label: 'Google Maps', packageName: 'com.google.android.apps.maps'),
  };

  Future<Map<String, dynamic>> report() async {
    final response = await _dio.get<dynamic>(
      '/api/owner/ai/report',
      options: Options(headers: await _auth.ownerHeaders()),
    );
    final data = _requireMap(response);
    final report = data['report'];
    if (report is Map<String, dynamic>) return report;
    if (report is Map) return Map<String, dynamic>.from(report);
    throw StateError('Next returned an invalid operational report.');
  }

  Future<Map<String, dynamic>> status() async {
    final response = await _dio.get<dynamic>(
      '/api/owner/ai/status',
      options: Options(headers: await _auth.ownerHeaders()),
    );
    final data = _requireMap(response);
    final status = data['status'];
    if (status is Map<String, dynamic>) return status;
    if (status is Map) return Map<String, dynamic>.from(status);
    throw StateError('Next returned an invalid system status.');
  }

  Future<NextChatReply> chat(
    String message, {
    String? conversationId,
  }) async {
    final normalized = _normalizeCommand(message);
    if (_isApprovalIntent(normalized)) {
      final pending = _pendingOwnerAction;
      if (pending == null) {
        return NextChatReply(
          answer: 'There is no action currently displayed on this phone to approve.',
          conversationId: conversationId,
          tool: 'owner_action_guard',
        );
      }
      return _completeOwnerAction(
        pending,
        approve: true,
        conversationId: conversationId,
      );
    }
    if (_isCancellationIntent(normalized)) {
      final pending = _pendingOwnerAction;
      if (pending == null) {
        return NextChatReply(
          answer: 'There is no pending owner action on this phone to cancel.',
          conversationId: conversationId,
          tool: 'owner_action_guard',
        );
      }
      return _completeOwnerAction(
        pending,
        approve: false,
        conversationId: conversationId,
      );
    }

    final local = await _tryLocalDeviceCommand(
      message,
      conversationId: conversationId,
    );
    if (local != null) return local;

    final comparesWorkspace = RegExp(
      r'\bcompare (?:these|both|the two|the visible|the open)\b|\bcompare.*on screen\b',
    ).hasMatch(normalized);
    final referencesWorkspace = comparesWorkspace || _referencesWorkspace(normalized);
    final workspaceContext = referencesWorkspace
        ? (comparesWorkspace
            ? WorkspaceController.instance.comparisonAnalysisContext()
            : WorkspaceController.instance.activeAnalysisContext())
        : null;
    if (referencesWorkspace &&
        (comparesWorkspace || WorkspaceController.instance.isOpen) &&
        workspaceContext == null) {
      return NextChatReply(
        answer: comparesWorkspace
            ? 'Show two readable documents together first. I need text from both before I can compare them.'
            : 'That view has not exposed readable text for analysis yet.',
        conversationId: conversationId,
        tool: 'workspace_context_unavailable',
      );
    }

    final response = await _dio.post<dynamic>(
      '/api/owner/ai/chat',
      data: {
        'message': message,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversation_id': conversationId,
        if (workspaceContext != null)
          'workspace_context': {
            'kind': workspaceContext.kind,
            'title': workspaceContext.title,
            'source': workspaceContext.source,
            'text': workspaceContext.text,
          },
      },
      options: Options(headers: await _auth.ownerHeaders()),
    );
    final data = _requireMap(response);
    final answer = data['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw StateError('Next returned an incomplete response.');
    }

    final action = _actionMap(data['action']);
    final approvalRequired = data['approval_required'] == true;
    if (approvalRequired && action != null) {
      _pendingOwnerAction = Map<String, dynamic>.from(action);
    } else if (action != null && _isTerminalAction(action)) {
      _clearMatchingPending(action);
    }

    return NextChatReply(
      answer: answer.trim(),
      conversationId: data['conversation_id'] is String
          ? data['conversation_id'] as String
          : conversationId,
      tool: data['tool'] is String ? data['tool'] as String : null,
      approvalRequired: approvalRequired,
      action: action,
    );
  }

  String _normalizeCommand(String message) {
    return message
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isApprovalIntent(String normalized) {
    return RegExp(
      r'^(approve|approve it|yes approve|yes, approve|go ahead|send it|post it|publish it|do it|confirm|confirm it)$',
    ).hasMatch(normalized);
  }

  bool _isCancellationIntent(String normalized) {
    return RegExp(
      r"^(cancel|cancel it|stop|don't send it|do not send it|don't post it|do not post it)$",
    ).hasMatch(normalized);
  }

  bool _referencesWorkspace(String normalized) {
    return RegExp(
      r'\b(this page|this article|this file|this document|this report|what i am looking at|what i\x27m looking at|on screen)\b',
    ).hasMatch(normalized) ||
        RegExp(r'^(analyze|analyse|summarize|summarise|explain|review) this$')
            .hasMatch(normalized);
  }

  Future<NextChatReply> _completeOwnerAction(
    Map<String, dynamic> pending, {
    required bool approve,
    String? conversationId,
  }) async {
    final id = pending['id']?.toString().trim() ?? '';
    final token = pending['approval_token']?.toString().trim() ?? '';
    if (id.isEmpty || (approve && token.isEmpty)) {
      _pendingOwnerAction = null;
      return NextChatReply(
        answer: 'That approval is no longer valid. Ask Next to prepare the action again.',
        conversationId: conversationId,
        tool: 'owner_action_guard',
      );
    }

    final response = await _dio.post<dynamic>(
      approve
          ? '/api/owner/ai/action/approve'
          : '/api/owner/ai/action/cancel',
      data: {
        'id': id,
        if (approve) 'approval_token': token,
      },
      options: Options(headers: await _auth.ownerHeaders()),
    );
    final data = _requireMap(response);
    final action = _actionMap(data['action']);
    if (action != null) _clearMatchingPending(action);

    final summary = (action?['summary'] ?? pending['summary'] ?? 'The owner action')
        .toString()
        .trim();
    final status = action?['status']?.toString().trim() ?? '';
    final answer = approve
        ? status == 'completed'
            ? 'Done. $summary was executed and verified.'
            : '$summary returned status ${status.isEmpty ? 'unknown' : status}.'
        : status == 'cancelled' || status == 'not_found'
            ? 'Cancelled. $summary will not be executed.'
            : 'The cancellation returned status ${status.isEmpty ? 'unknown' : status}.';

    return NextChatReply(
      answer: answer,
      conversationId: conversationId,
      tool: approve ? 'owner_action_approve' : 'owner_action_cancel',
      action: action,
    );
  }

  Map<String, dynamic>? _actionMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  bool _isTerminalAction(Map<String, dynamic> action) {
    final status = action['status']?.toString();
    return status == 'completed' ||
        status == 'cancelled' ||
        status == 'failed' ||
        status == 'not_found';
  }

  void _clearMatchingPending(Map<String, dynamic> action) {
    final current = _pendingOwnerAction;
    if (current == null) return;
    final currentId = current['id']?.toString();
    final actionId = action['id']?.toString();
    if (currentId == null || actionId == null || currentId == actionId) {
      _pendingOwnerAction = null;
    }
  }

  Future<NextChatReply?> _tryLocalDeviceCommand(
    String message, {
    String? conversationId,
  }) async {
    final normalized = _normalizeCommand(message);
    final workspace = WorkspaceController.instance;

    if (RegExp(r'^(?:please )?(?:open|choose|pick|browse) (?:a )?file$|^open files$').hasMatch(normalized)) {
      final result = await workspace.pickFile();
      return NextChatReply(
        answer: result.message,
        conversationId: conversationId,
        tool: 'workspace_file',
      );
    }

    if (RegExp(r'^(?:close|hide) (?:the )?(?:workspace|browser|file|document|report)$').hasMatch(normalized)) {
      workspace.closeActive();
      return NextChatReply(
        answer: 'Closed the current workspace panel.',
        conversationId: conversationId,
        tool: 'workspace_close',
      );
    }

    if (RegExp(r'^(?:close|clear) all (?:workspace|workspace tabs|tabs|documents)$').hasMatch(normalized)) {
      workspace.closeAll();
      return NextChatReply(
        answer: 'Cleared the workspace.',
        conversationId: conversationId,
        tool: 'workspace_close_all',
      );
    }

    if (RegExp(r'^(?:next|switch to next) (?:workspace )?tab$').hasMatch(normalized)) {
      workspace.nextTab();
      return NextChatReply(
        answer: 'Switched to the next workspace tab.',
        conversationId: conversationId,
        tool: 'workspace_tab',
      );
    }

    if (RegExp(r'^(?:previous|switch to previous) (?:workspace )?tab$').hasMatch(normalized)) {
      workspace.previousTab();
      return NextChatReply(
        answer: 'Switched to the previous workspace tab.',
        conversationId: conversationId,
        tool: 'workspace_tab',
      );
    }

    if (RegExp(
      r'^(?:show|open) (?:the )?(?:system|company|operational|full) report$',
    ).hasMatch(normalized)) {
      final operational = await report();
      workspace.openReport('OTYA operational report', operational);
      return NextChatReply(
        answer: 'I opened the live OTYA operational report on this screen.',
        conversationId: conversationId,
        tool: 'workspace_report',
      );
    }

    final newsMatch = RegExp(
      r'^(?:show|open|find|search) (?:the )?(?:latest )?news (?:about|on|for) (.+)$|^(?:latest )?news (?:about|on) (.+)$',
    ).firstMatch(normalized);
    if (newsMatch != null) {
      final query = (newsMatch.group(1) ?? newsMatch.group(2) ?? '').trim();
      if (query.isNotEmpty) {
        final uri = Uri.https('news.google.com', '/search', {'q': query});
        workspace.openWeb(uri, title: 'News · $query');
        return NextChatReply(
          answer: 'I opened live news about $query in the workspace.',
          conversationId: conversationId,
          tool: 'workspace_news',
        );
      }
    }

    final webSearchMatch = RegExp(
      r'^(?:search|look up|find) (?:the )?(?:web|internet) (?:for )?(.+)$|^web search (.+)$',
    ).firstMatch(normalized);
    if (webSearchMatch != null) {
      final query = (webSearchMatch.group(1) ?? webSearchMatch.group(2) ?? '').trim();
      if (query.isNotEmpty) {
        final uri = Uri.https('www.google.com', '/search', {'q': query});
        workspace.openWeb(uri, title: 'Web · $query');
        return NextChatReply(
          answer: 'I opened web results for $query on this screen.',
          conversationId: conversationId,
          tool: 'workspace_web_search',
        );
      }
    }

    if (RegExp(r'^(?:please )?open (?:the )?(?:web )?browser$').hasMatch(normalized)) {
      workspace.openWeb(Uri.parse('https://www.google.com/'), title: 'Web');
      return NextChatReply(
        answer: 'Browser opened inside Next.',
        conversationId: conversationId,
        tool: 'workspace_browser',
      );
    }

    final websiteMatch = RegExp(r'^(?:open|show) (?:website|site) (.+)$').firstMatch(normalized);
    if (websiteMatch != null) {
      var raw = websiteMatch.group(1)?.trim() ?? '';
      if (raw.isNotEmpty) {
        if (!raw.startsWith('http://') && !raw.startsWith('https://')) raw = 'https://$raw';
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.host.isNotEmpty && (uri.scheme == 'https' || uri.scheme == 'http')) {
          workspace.openWeb(uri, title: uri.host);
          return NextChatReply(
            answer: 'Opened ${uri.host} inside Next.',
            conversationId: conversationId,
            tool: 'workspace_browser',
          );
        }
      }
    }

    final openMatch = RegExp(r'^(?:please )?open (.+?)(?: app)?$').firstMatch(normalized);
    if (openMatch != null) {
      final requested = openMatch.group(1)?.trim() ?? '';
      final app = _localApps[requested];
      if (app != null) {
        try {
          await NextPlatformBridge.openApp(app.packageName);
          return NextChatReply(
            answer: 'Opening ${app.label}.',
            conversationId: conversationId,
            tool: 'device_open_app',
          );
        } catch (_) {
          return NextChatReply(
            answer: '${app.label} is not installed or Android would not let me open it.',
            conversationId: conversationId,
            tool: 'device_open_app',
          );
        }
      }
    }

    String? panel;
    String? panelAnswer;
    if (RegExp(
      r'^(?:please )?(?:open )?(?:wifi|wi-fi|internet)(?: settings| controls)?$|^(?:turn|switch) (?:on|off) (?:wifi|wi-fi)$',
    ).hasMatch(normalized)) {
      panel = 'internet';
      panelAnswer = 'Opening Android Internet controls. Confirm the network change there.';
    } else if (RegExp(
      r'^(?:please )?(?:open )?bluetooth(?: settings| controls)?$|^(?:turn|switch) (?:on|off) bluetooth$',
    ).hasMatch(normalized)) {
      panel = 'bluetooth';
      panelAnswer = 'Opening Bluetooth settings. Android keeps the final radio change under your control.';
    } else if (RegExp(
      r'^(?:please )?(?:open |manage )?(?:next )?notification settings$|^manage next notifications$',
    ).hasMatch(normalized)) {
      panel = 'notifications';
      panelAnswer = 'Opening Next notification settings.';
    } else if (RegExp(
      r'^(?:please )?(?:open )?(?:next |app )?settings$|^open next app settings$',
    ).hasMatch(normalized)) {
      panel = 'app';
      panelAnswer = 'Opening Next app settings.';
    }

    if (panel != null && panelAnswer != null) {
      try {
        await NextPlatformBridge.openSystemPanel(panel);
        return NextChatReply(
          answer: panelAnswer,
          conversationId: conversationId,
          tool: 'device_system_panel',
        );
      } catch (_) {
        return NextChatReply(
          answer: 'Android could not open that settings control on this phone.',
          conversationId: conversationId,
          tool: 'device_system_panel',
        );
      }
    }

    final asksDeviceStatus = RegExp(
      r'^(what phone am i on|what phone is this|device status|phone status|tell me about this phone)$',
    ).hasMatch(normalized);
    if (asksDeviceStatus) {
      try {
        final snapshot = await NextPlatformBridge.deviceSnapshot();
        final manufacturer = snapshot['manufacturer']?.toString().trim() ?? '';
        final model = snapshot['model']?.toString().trim() ?? '';
        final android = snapshot['release']?.toString().trim() ?? '';
        final assistantHeld = snapshot['assistantRoleHeld'] == true;
        final speechReady = snapshot['speechRecognitionAvailable'] == true;
        final name = [manufacturer, model]
            .where((value) => value.isNotEmpty)
            .join(' ')
            .trim();
        return NextChatReply(
          answer: [
            if (name.isNotEmpty) 'This is a $name.',
            if (android.isNotEmpty) 'It is running Android $android.',
            assistantHeld
                ? 'Next is selected as the phone assistant.'
                : 'Next is not yet selected as the phone assistant.',
            speechReady
                ? 'Live speech recognition is available.'
                : 'Live speech recognition is unavailable on this device.',
          ].join(' '),
          conversationId: conversationId,
          tool: 'device_snapshot',
        );
      } catch (_) {
        return NextChatReply(
          answer: 'I could not read the phone status right now.',
          conversationId: conversationId,
          tool: 'device_snapshot',
        );
      }
    }

    final asksForAssistantRole = RegExp(
      r'^(make next my assistant|set next as my assistant|make you my assistant|become my phone assistant)$',
    ).hasMatch(normalized);
    if (asksForAssistantRole) {
      try {
        await NextPlatformBridge.requestAssistantRole();
        return NextChatReply(
          answer: 'Android opened the assistant selector. Choose Next once and I will use that role from then on.',
          conversationId: conversationId,
          tool: 'device_assistant_role',
        );
      } catch (_) {
        return NextChatReply(
          answer: 'Android could not open the assistant selector on this phone.',
          conversationId: conversationId,
          tool: 'device_assistant_role',
        );
      }
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> conversations() async {
    final response = await _dio.get<dynamic>(
      '/api/owner/ai/conversations',
      options: Options(headers: await _auth.ownerHeaders()),
    );
    final data = _requireMap(response);
    final rows = data['conversations'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Map<String, dynamic> _requireMap(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) throw const OwnerAccessExpired();
    final raw = response.data;
    final data = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : null;
    if (status < 200 || status >= 300) {
      final detail = data?['detail'] ?? data?['error'];
      throw StateError(
        detail is String && detail.trim().isNotEmpty
            ? detail.trim()
            : 'Next request failed (HTTP $status).',
      );
    }
    if (data == null) throw StateError('Next returned an invalid response.');
    return data;
  }
}
