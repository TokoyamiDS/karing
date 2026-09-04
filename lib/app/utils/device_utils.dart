import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceUtils {
  static Future<bool> disableOrientation() async {
    return false;
  }

  static Future<String> getDeviceModel() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return info.model;
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return info.productName;
      }
    } catch (_) {}
    return "";
  }
}
