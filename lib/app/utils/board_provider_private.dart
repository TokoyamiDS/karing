import 'dart:convert';

import 'package:tuple/tuple.dart';

/// Builds board-provider integration request urls and bodies.
/// Personal build: the telemetry endpoints are disabled (empty urls short
/// circuit the callers' http requests, harmless).
class BoardProviderPrivate {
  static Tuple3<String, String, String> getBycodeUrlAndBody({
    required String app,
    required String version,
    required String did,
    required String code,
  }) {
    final body = jsonEncode({
      'app': app,
      'version': version,
      'did': did,
      'code': code,
    });
    return Tuple3("", "", body);
  }

  static Tuple3<String, String, String> getNotifyIntegrationUrlAndBody({
    required String app,
    required String version,
    required String did,
    required String url,
    required String type,
  }) {
    final body = jsonEncode({
      'app': app,
      'version': version,
      'did': did,
      'url': url,
      'type': type,
    });
    return Tuple3("", "", body);
  }

  static Tuple3<String, String, String> getNoticePushUrlAndBody({
    required String app,
    required String version,
    required String did,
    required String pid,
  }) {
    final body = jsonEncode({
      'app': app,
      'version': version,
      'did': did,
      'pid': pid,
    });
    return Tuple3("", "", body);
  }
}
