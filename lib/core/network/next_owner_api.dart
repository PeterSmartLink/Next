import 'package:dio/dio.dart';

import '../auth/owner_auth_service.dart';

class OwnerAccessExpired implements Exception {
  const OwnerAccessExpired();
}

class NextChatReply {
  const NextChatReply({
    required this.answer,
    required this.conversationId,
    this.tool,
  });

  final String answer;
  final String conversationId;
  final String? tool;
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
    final id = data['conversation_id'];
    if (answer is! String || answer.trim().isEmpty || id is! String || id.isEmpty) {
      throw StateError('Next returned an incomplete response.');
    }
    return NextChatReply(
      answer: answer.trim(),
      conversationId: id,
      tool: data['tool'] is String ? data['tool'] as String : null,
    );
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
