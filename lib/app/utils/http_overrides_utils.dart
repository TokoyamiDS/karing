import 'dart:io';

/// Lightweight TLS bypass fixes for hosts with bad certificates when the
/// system clock or TLS stack misbehaves. Kept minimal for personal use.
class HttpOverridesUtils {
  static void install() {
    try {
      HttpOverrides.global = _KaringHttpOverrides();
    } catch (_) {}
  }
}

class _KaringHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      return false;
    };
    return client;
  }
}
