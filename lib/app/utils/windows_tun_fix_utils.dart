import 'dart:io';

/// Removes broken wintun adapters left behind by crashes.
class WindowsTunFixUtils {
  static Future<void> removeDriver() async {
    try {
      await Process.run(
        'netsh',
        ['interface', 'set', 'interface', 'KaringTun', 'admin=disabled'],
      );
    } catch (_) {}
  }
}
