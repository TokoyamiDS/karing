import 'package:flutter/widgets.dart';

/// Accessibility helpers (stub: no screen reader announcements on desktop).
class AccessibilityUtils {
  static bool _enabled = false;

  static bool getAccessibilityEnabled() {
    return _enabled;
  }

  static void setAccessibilityEnabled(bool enable) {
    _enabled = enable;
  }

  static void announce(BuildContext context, String message) {}
}
