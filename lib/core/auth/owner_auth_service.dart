import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../platform/next_platform_bridge.dart';

class OwnerAuthException implements Exception {
  const OwnerAuthException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class OwnerLoginResult {
  const OwnerLoginResult({
    required this.ok,
    this.error,
    this.errorCode,
  });

  final bool ok;
  final String? error;
  final String? errorCode;

  bool get twoFactorRequired => errorCode == 'TWO_FACTOR_REQUIRED';
  bool get twoFactorInvalid => errorCode == 'TWO_FACTOR_INVALID';
}

class OwnerAuthService {
  OwnerAuthService._()
      : _dio = Dio(
          BaseOptions(
            baseUrl: const String.fromEnvironment(
              'OTYA_BASE_URL',
              defaultValue: 'https://petersmartlink.com',
            ),
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 15),
            responseType: ResponseType.json,
            headers: const {'Accept': 'application/json'},
            validateStatus: (_) => true,
          ),
        );

  static final OwnerAuthService instance = OwnerAuthService._();

  static const _accessKey = 'next_otya_access_token';
  static const _refreshKey = 'next_otya_refresh_token';
  static const _ownerGrantKey = 'next_owner_grant';
  static const _deviceIdKey = 'next_owner_device_id';

  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  String? _ownerGrant;
  String? _deviceId;
  bool _loaded = false;
  Future<void>? _loadInFlight;
  Future<String?>? _refreshInFlight;

  String? get ownerGrant => _ownerGrant;
  String? get deviceId => _deviceId;

  Future<void> initialize() => _ensureLoaded();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final existing = _loadInFlight;
    if (existing != null) return existing;

    final load = _load();
    _loadInFlight = load;
    try {
      await load;
    } finally {
      if (identical(_loadInFlight, load)) _loadInFlight = null;
    }
  }

  Future<void> _load() async {
    _accessToken = await _storage.read(key: _accessKey);
    _refreshToken = await _storage.read(key: _refreshKey);
    _ownerGrant = await _storage.read(key: _ownerGrantKey);
    _deviceId = await _storage.read(key: _deviceIdKey);
    if (_deviceId == null || _deviceId!.length < 20) {
      _deviceId = _newDeviceId();
      await _storage.write(key: _deviceIdKey, value: _deviceId);
    }
    _loaded = true;
  }

  String _newDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final encoded = base64UrlEncode(bytes).replaceAll('=', '');
    return 'next-$encoded';
  }

  bool _tokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) return true;
      final exp = payload['exp'];
      if (exp is! num) return true;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= exp.toInt() - 60;
    } catch (_) {
      return true;
    }
  }

  Future<bool> hasSignedInSession() async {
    await _ensureLoaded();
    final token = await getValidAccessToken();
    if (token != null) return true;
    // A temporary network failure is not a logout. If the securely stored
    // refresh token still exists, open Next in offline/degraded mode and let
    // the normal refresh path recover automatically when connectivity returns.
    return _refreshToken != null && _refreshToken!.isNotEmpty;
  }

  Future<String?> getValidAccessToken() async {
    await _ensureLoaded();
    final access = _accessToken;
    if (access != null && access.isNotEmpty && !_tokenExpired(access)) {
      return access;
    }

    final running = _refreshInFlight;
    if (running != null) return running;
    final refresh = _refreshAccessToken();
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<String?> _refreshAccessToken() async {
    await _ensureLoaded();
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return null;

    try {
      final response = await _dio.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = _map(response.data);
      final token = data?['access_token'];
      if (response.statusCode == 200 && token is String && token.isNotEmpty) {
        _accessToken = token;
        await _storage.write(key: _accessKey, value: token);
        return token;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        await clearLocalSession();
      }
    } catch (_) {
      // Keep the refresh token. Temporary network failure is not a logout.
    }
    return null;
  }

  Future<OwnerLoginResult> login(
    String email,
    String password, {
    String? totpCode,
    String? recoveryCode,
  }) async {
    await _ensureLoaded();
    try {
      final response = await _dio.post<dynamic>(
        '/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
          if (totpCode?.trim().isNotEmpty == true) 'totp_code': totpCode!.trim(),
          if (recoveryCode?.trim().isNotEmpty == true)
            'recovery_code': recoveryCode!.trim(),
        },
      );
      final data = _map(response.data);
      if (_successful(response, data)) {
        final access = data!['access_token'];
        final refresh = data['refresh_token'];
        final user = data['user'];
        if (access is! String ||
            access.isEmpty ||
            refresh is! String ||
            refresh.isEmpty ||
            user is! Map) {
          return const OwnerLoginResult(
            ok: false,
            error: 'OTYA returned incomplete session information.',
          );
        }
        await _storeSession(access, refresh);
        return const OwnerLoginResult(ok: true);
      }
      return OwnerLoginResult(
        ok: false,
        error: _error(data, 'Sign-in failed. Please try again.'),
        errorCode: data?['code'] is String ? data!['code'] as String : null,
      );
    } on DioException catch (_) {
      return const OwnerLoginResult(
        ok: false,
        error: 'Could not reach OTYA. Check your connection and try again.',
      );
    }
  }

  Future<void> _storeSession(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<Map<String, String>> _bearerHeaders() async {
    final token = await getValidAccessToken();
    if (token == null) {
      throw const OwnerAuthException('Your OTYA session is temporarily unavailable.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<Map<String, String>> _deviceHeaders() async {
    await _ensureLoaded();
    final id = _deviceId;
    if (id == null || id.length < 20) {
      throw const OwnerAuthException('Next could not establish this device identity.');
    }
    return {'X-OTYA-Device-ID': id};
  }

  Future<Map<String, String>> ownerHeaders() async {
    await _ensureLoaded();
    final grant = _ownerGrant;
    if (grant == null || grant.isEmpty) {
      throw const OwnerAuthException(
        'Owner device verification is required.',
        code: 'OWNER_REQUIRED',
      );
    }
    return {
      ...await _bearerHeaders(),
      ...await _deviceHeaders(),
      'X-OTYA-Owner-Grant': grant,
    };
  }

  Future<void> startOwnerVerification() async {
    final response = await _dio.post<dynamic>(
      '/auth/admin/start',
      data: const <String, dynamic>{},
      options: Options(headers: await _bearerHeaders()),
    );
    _requireOk(response, fallback: 'Could not start owner device enrollment.');
  }

  Future<String> verifyOwnerOtp(String otp) async {
    final response = await _dio.post<dynamic>(
      '/auth/admin/verify-otp',
      data: {'otp': otp.trim().toUpperCase()},
      options: Options(headers: await _bearerHeaders()),
    );
    final data = _map(response.data);
    if (!_successful(response, data)) {
      throw OwnerAuthException(
        _error(data, 'The verification code was not accepted.'),
        code: data?['code'] is String ? data!['code'] as String : null,
      );
    }
    final challenge = data?['telegram_challenge'];
    if (challenge is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,80}$').hasMatch(challenge)) {
      throw const OwnerAuthException(
        'OTYA did not return a valid Telegram enrollment challenge.',
      );
    }
    return challenge;
  }

  Future<void> startTelegramOwnerVerification(String challenge) async {
    final value = challenge.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{16,80}$').hasMatch(value)) {
      throw const OwnerAuthException('The Telegram enrollment challenge is invalid.');
    }
    final uri = Uri(
      scheme: 'tg',
      host: 'resolve',
      queryParameters: {
        'domain': 'OtyaPlayerBot',
        'start': 'owner_$value',
      },
    );
    await NextPlatformBridge.openUrl(uri.toString());
  }

  Future<void> completeOwnerVerification() async {
    final response = await _dio.post<dynamic>(
      '/auth/admin/mobile-grant',
      data: const <String, dynamic>{},
      options: Options(headers: {
        ...await _bearerHeaders(),
        ...await _deviceHeaders(),
      }),
    );
    final data = _map(response.data);
    if (!_successful(response, data)) {
      throw OwnerAuthException(
        _error(data, 'Complete Telegram verification first.'),
        code: response.statusCode == 401 ? 'TELEGRAM_PENDING' : null,
      );
    }
    final grant = data?['owner_grant'];
    if (grant is! String || grant.isEmpty) {
      throw const OwnerAuthException('OTYA did not return a trusted-device grant.');
    }
    _ownerGrant = grant;
    await _storage.write(key: _ownerGrantKey, value: grant);
  }

  Future<bool> hasValidOwnerGrant() async {
    await _ensureLoaded();
    if (_ownerGrant == null || _ownerGrant!.isEmpty) return false;
    try {
      final response = await _dio.post<dynamic>(
        '/auth/admin/verify-grant',
        data: const <String, dynamic>{},
        options: Options(headers: await ownerHeaders()),
      );
      final data = _map(response.data);
      if (_successful(response, data)) return true;
      if (response.statusCode == 401 || response.statusCode == 403) {
        await clearOwnerGrant();
        return false;
      }
      // Non-auth server errors must not turn into a fake logout.
      return true;
    } on DioException {
      // Keep trusted-device state during temporary connectivity loss.
      return true;
    } on OwnerAuthException {
      // If the account session itself is unavailable, preserve the trusted
      // device. The refresh path will recover when connectivity returns.
      return _ownerGrant != null && _ownerGrant!.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<void> clearOwnerGrant() async {
    _ownerGrant = null;
    await _storage.delete(key: _ownerGrantKey);
  }

  Future<void> logout() async {
    await _ensureLoaded();
    final refresh = _refreshToken;
    final access = await getValidAccessToken();
    final grant = _ownerGrant;
    final device = _deviceId;

    if (access != null && grant != null && device != null) {
      try {
        await _dio.post<dynamic>(
          '/auth/admin/revoke-grant',
          data: const <String, dynamic>{},
          options: Options(headers: {
            'Authorization': 'Bearer $access',
            'X-OTYA-Owner-Grant': grant,
            'X-OTYA-Device-ID': device,
          }),
        );
      } catch (_) {}
    }
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await _dio.post<dynamic>('/auth/logout', data: {'refresh_token': refresh});
      } catch (_) {}
    }

    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    _accessToken = null;
    _refreshToken = null;
    _ownerGrant = null;
    _loaded = true;
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _ownerGrantKey),
    ]);
    // Keep the stable private device identity across logout. It is useless on
    // its own because the server-side owner grant is revoked during logout.
  }

  Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  bool _successful(Response<dynamic> response, Map<String, dynamic>? data) {
    final status = response.statusCode ?? 0;
    return status >= 200 && status < 300 && data?['ok'] == true;
  }

  String _error(Map<String, dynamic>? data, String fallback) {
    final error = data?['error'];
    return error is String && error.trim().isNotEmpty ? error.trim() : fallback;
  }

  void _requireOk(Response<dynamic> response, {required String fallback}) {
    final data = _map(response.data);
    if (_successful(response, data)) return;
    throw OwnerAuthException(
      _error(data, fallback),
      code: data?['code'] is String ? data!['code'] as String : null,
    );
  }
}
