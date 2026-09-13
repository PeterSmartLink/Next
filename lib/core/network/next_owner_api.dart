import 'package:dio/dio.dart';

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
    final local = await _tryLocalDeviceCommand(
      message,
      conversationId: conversationId,
    );
    if (local != null) return local;

    final response = await _dio.post<dynamic>(
      '/api/owner/ai/chat',
      data: {
        'message': message,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversation_id': conversationId,
      },
      options: Options(headers: await _auth.ownerHeaders()),
    );
    final data = _requireMap(response);
    final answer = data['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw StateError('Next returned an incomplete response.');
    }

    final rawAction = data['action'];
    final action = rawAction is Map<String, dynamic>
        ? rawAction
        : rawAction is Map
            ? Map<String, dynamic>.from(rawAction)
            : null;

    return NextChatReply(
      answer: answer.trim(),
      conversationId: data['conversation_id'] is String
          ? data['conversation_id'] as String
          : conversationId,
      tool: data['tool'] is String ? data['tool'] as String : null,
      approvalRequired: data['approval_required'] == true,
      action: action,
    );
  }

  Future<NextChatReply?> _tryLocalDeviceCommand(
    String message, {
    String? conversationId,
  }) async {
    final normalized = message
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');

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
