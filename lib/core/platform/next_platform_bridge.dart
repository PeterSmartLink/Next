import 'package:flutter/services.dart';

class NextPlatformBridge {
  NextPlatformBridge._();

  static const MethodChannel _channel = MethodChannel('com.petersmartlink.next/device');
  static const EventChannel _voiceChannel = EventChannel('com.petersmartlink.next/voice');

  static Stream<Map<String, dynamic>>? _voiceEvents;

  static Stream<Map<String, dynamic>> get voiceEvents {
    return _voiceEvents ??= _voiceChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => Map<String, dynamic>.from(event as Map));
  }

  static Future<bool> isAssistantRoleAvailable() async {
    return await _channel.invokeMethod<bool>('isAssistantRoleAvailable') ?? false;
  }

  static Future<bool> isAssistantRoleHeld() async {
    return await _channel.invokeMethod<bool>('isAssistantRoleHeld') ?? false;
  }

  static Future<void> requestAssistantRole() async {
    await _channel.invokeMethod<void>('requestAssistantRole');
  }

  static Future<void> startVoiceListening() async {
    await _channel.invokeMethod<void>('startVoiceListening');
  }

  static Future<void> stopVoiceListening() async {
    await _channel.invokeMethod<void>('stopVoiceListening');
  }

  static Future<void> speak(String text) async {
    await _channel.invokeMethod<void>('speak', {'text': text});
  }

  static Future<void> stopSpeaking() async {
    await _channel.invokeMethod<void>('stopSpeaking');
  }

  static Future<bool> isSpeaking() async {
    return await _channel.invokeMethod<bool>('isSpeaking') ?? false;
  }

  static Future<void> openApp(String packageName) async {
    await _channel.invokeMethod<void>('openApp', {'packageName': packageName});
  }

  static Future<void> openUrl(String url) async {
    await _channel.invokeMethod<void>('openUrl', {'url': url});
  }

  static Future<void> openSystemPanel(String panel) async {
    await _channel.invokeMethod<void>('openSystemPanel', {'panel': panel});
  }

  static Future<Map<String, dynamic>> deviceSnapshot() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('deviceSnapshot');
    return raw ?? const <String, dynamic>{};
  }
}
