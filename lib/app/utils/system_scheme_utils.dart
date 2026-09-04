import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Registers / unregisters URL schemes on windows. On mobile the OS handles
/// schemes via the manifest / Info.plist, so these are no-ops there.
class SystemSchemeUtils {
  static const String karingScheme = "karing";
  static const String clashScheme = "clash";
  static const String singboxScheme = "sing-box";

  static String getKaringScheme() {
    return karingScheme;
  }

  static String getKaringSchemeWith([String url = ""]) {
    return "$karingScheme://install-config" +
        (url.isEmpty ? "" : "?url=$url");
  }

  static String getClashScheme() {
    return clashScheme;
  }

  static String getClashSchemeWith([String url = ""]) {
    return "$clashScheme://install-config" +
        (url.isEmpty ? "" : "?url=$url");
  }

  static String getSingboxScheme() {
    return singboxScheme;
  }

  static String getSingboxSchemeWith([String url = ""]) {
    return "$singboxScheme://import-remote-profile" +
        (url.isEmpty ? "" : "?url=$url");
  }

  static bool isRegistered(String scheme) {
    if (!Platform.isWindows) {
      return true;
    }
    final result = Process.runSync(
      'reg',
      ['query', 'HKCU\\Software\\Classes\\$scheme', '/ve'],
    );
    return result.exitCode == 0;
  }

  static Future<String?> register(String scheme) async {
    if (!Platform.isWindows) {
      return null;
    }
    final exe = Platform.resolvedExecutable;
    final result = await Process.run('reg', [
      'add',
      'HKCU\\Software\\Classes\\$scheme',
      '/ve',
      '/d',
      'URL:$scheme Protocol',
      '/f',
    ]);
    if (result.exitCode != 0) {
      return result.stderr.toString();
    }
    await Process.run('reg', [
      'add',
      'HKCU\\Software\\Classes\\$scheme\\DefaultIcon',
      '/ve',
      '/d',
      '"$exe",0',
      '/f',
    ]);
    final result2 = await Process.run('reg', [
      'add',
      'HKCU\\Software\\Classes\\$scheme\\shell\\open\\command',
      '/ve',
      '/d',
      '"$exe" "%1"',
      '/f',
    ]);
    if (result2.exitCode != 0) {
      return result2.stderr.toString();
    }
    return null;
  }

  static Future<String?> unregister(String scheme) async {
    if (!Platform.isWindows) {
      return null;
    }
    final result = await Process.run(
      'reg',
      ['delete', 'HKCU\\Software\\Classes\\$scheme', '/f'],
    );
    if (result.exitCode != 0) {
      return result.stderr.toString();
    }
    return null;
  }

  static Future<void> launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
