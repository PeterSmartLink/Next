import 'package:flutter/services.dart';

class NextPlatformBridge {
  NextPlatformBridge._();

  static const MethodChannel _channel = MethodChannel('com.petersmartlink.next/device');

  static Future<bool> isAssistantRoleAvailable() async {
    return await _channel.invokeMethod<bool>('isAssistantRoleAvailable') ?? false;
  }

  static Future<bool> isAssistantRoleHeld() async {
    return await _channel.invokeMethod<bool>('isAssistantRoleHeld') ?? false;
  }

  static Future<void> requestAssistantRole() async {
    await _channel.invokeMethod<void>('requestAssistantRole');
  }

  static Future<void> openApp(String packageName) async {
    await _channel.invokeMethod<void>('openApp', {'packageName': packageName});
  }

  static Future<Map<String, dynamic>> deviceSnapshot() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('deviceSnapshot');
    return raw ?? const <String, dynamic>{};
  }
}
