import 'package:flutter/services.dart';

/// Bridge for the native "channel_main_method" method channel used by the
/// android TileService / AutomationCommandReceiver to reach Dart code.
class MainChannelUtils {
  static final _onMethodCall = <String,
      Future<dynamic> Function(Map<String, dynamic> arguments)>{};

  static const MethodChannel _channel = MethodChannel('channel_main_method');

  static void registerCallback(String method,
      Future<dynamic> Function(Map<String, dynamic> arguments) callback) {
    _onMethodCall[method] = callback;
  }

  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      final callback = _onMethodCall[call.method];
      if (callback == null) {
        return null;
      }
      final args = call.arguments;
      if (args is Map) {
        return await callback(args.map((k, v) => MapEntry(k.toString(), v)));
      }
      return await callback({});
    });
  }

  static Future<void> uninit() async {
    _channel.setMethodCallHandler(null);
  }

  Future<dynamic> call(String method, [Map<String, dynamic>? arguments]) {
    return MainChannelUtils.invokeMethod(method, arguments);
  }

  static Future<dynamic> invokeMethod(String method,
      [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod(method, arguments);
    } catch (_) {
      return null;
    }
  }
}

/// alias used by biz.dart / home_screen.dart
class MainChannel {
  static Future<dynamic> call(String method,
      [Map<String, dynamic>? arguments]) {
    return MainChannelUtils.invokeMethod(method, arguments);
  }

  static void init() {
    MainChannelUtils.init();
  }

  static void uninit() {
    MainChannelUtils.uninit();
  }
}
