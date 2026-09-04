import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/generated/build_time.dart' as build_time;

const List<String> ProxyBypassDoaminsDefault = [
  "localhost",
  "127.*",
  "10.*",
  "172.16.*",
  "172.17.*",
  "172.18.*",
  "172.19.*",
  "172.20.*",
  "172.21.*",
  "172.22.*",
  "172.23.*",
  "172.24.*",
  "172.25.*",
  "172.26.*",
  "172.27.*",
  "172.28.*",
  "172.29.*",
  "172.30.*",
  "172.31.*",
  "192.168.*",
  "<local>",
];

abstract final class AppUtils {
  static Future<String> getPackgetVersion() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return "${packageInfo.version}.${packageInfo.buildNumber}";
  }

  static String getName() {
    return "Karing";
  }

  static String getReleaseVersion() {
    List<String> v = getBuildinVersion().split(".");
    return "${v[0]}.${v[1]}.${v[2]}+${v[3]}";
  }

  static String getNextBuildinVersion() {
    List<String> v = getBuildinVersion().split(".");
    return "${v[0]}.${v[1]}.${v[2]}.${int.parse(v[3]) + 1}";
  }

  static String getBuildinVersion() {
    return build_time.buildVersion;
  }

  static DateTime getBuildinVersionDate() {
    return build_time.buildDateTime;
  }

  static String getId() {
    return "com.nebula.karing";
  }

  static String getGroupId() {
    return "group.com.nebula.karing";
  }

  static String getBundleId(bool systemExtension) {
    if (Platform.isIOS || Platform.isMacOS) {
      if (Platform.isMacOS && systemExtension) {
        return "com.nebula.karing.karingServiceSE";
      }
      return "com.nebula.karing.karingService";
    }
    return "";
  }

  static String getControlKind() {
    return "com.nebula.karing.karingWidget.ControlCenterToggle";
  }

  static String getTermsOfServiceUrl() {
    return "https://karing.app/terms/";
  }

  static String getPrivacyPolicyUrl() {
    return "https://karing.app/privacy/";
  }

  static String getCoreVersion() {
    return SettingConfig.kCoreVersion;
  }
}
