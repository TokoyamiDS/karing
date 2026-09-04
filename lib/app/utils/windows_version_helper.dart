import 'dart:io';

/// Detect windows version helpers.
class VersionHelper {
  static VersionHelper get instance => _instance;
  static final VersionHelper _instance = VersionHelper._();
  VersionHelper._();
  int majorVersion = 0;
  int minorVersion = 0;
  int buildNumber = 0;

  bool get isWindows10RS5OrGreater {
    return majorVersion > 10 ||
        (majorVersion == 10 && buildNumber >= 17763);
  }

  Future<void> init() async {
    try {
      final v = Platform.operatingSystemVersion;
      final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v);
      if (m != null) {
        majorVersion = int.tryParse(m.group(1)!) ?? 0;
        minorVersion = int.tryParse(m.group(2)!) ?? 0;
        buildNumber = int.tryParse(m.group(3)!) ?? 0;
      }
    } catch (_) {}
  }
}

class WindowsVersionHelper {
  static bool isWin11OrGreater() {
    try {
      final v = Platform.operatingSystemVersion;
      final m = RegExp(r'(\d+)\.').firstMatch(v);
      if (m != null) {
        final build = int.tryParse(m.group(1)!) ?? 0;
        return build >= 22000;
      }
    } catch (_) {}
    return false;
  }

  static bool isWin10OrGreater() {
    return true;
  }
}
