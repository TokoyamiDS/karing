/// Sentry is not used in this personal build. All methods are no-ops so the
/// rest of the app keeps compiling unchanged.
import 'package:flutter/widgets.dart';

class _NullNavigatorObserver extends NavigatorObserver {}

class SentryUtils {
  static Future<void> init() async {}

  static void captureException(
    String message,
    List<String>? params,
    dynamic exception,
    dynamic stacktrace, {
    Map<String, String>? attachments,
  }) {}

  static void captureMessage(String message) {}

  static Future<void> feedback(String message) async {}

  static NavigatorObserver getOvserver() {
    return _NullNavigatorObserver();
  }

  static void setContext(String key, Map<String, dynamic>? value) {}
}


