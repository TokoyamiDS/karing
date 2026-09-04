import 'dart:io';

/// System utils: route table for the network check screen.
class SystemUtils {
  static Future<String> getRouteTable() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('route', ['print', '-4']);
        if (result.exitCode == 0) {
          return result.stdout.toString();
        }
      } else if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('netstat', ['-rn']);
        if (result.exitCode == 0) {
          return result.stdout.toString();
        }
      }
    } catch (_) {}
    return "";
  }
}
