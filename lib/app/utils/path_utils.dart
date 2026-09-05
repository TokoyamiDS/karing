// ignore_for_file: unused_catch_stack, empty_catches

import "dart:io";

import "package:karing/app/utils/app_utils.dart";
import "package:karing/app/utils/file_utils.dart";
import "package:path/path.dart" as path;
import "package:vpn_service/vpn_service.dart";

class PathUtils {
  static String _appAssetsDir = "";
  static String _profileDir = "";
  static bool _portableMode = false;
  static bool portableMode() {
    return _portableMode;
  }

  static String appAssetsDir() {
    if (_appAssetsDir.isNotEmpty) {
      return _appAssetsDir;
    }

    if (Platform.isIOS) {
      _appAssetsDir = frameworkDir();
      _appAssetsDir = path.join(_appAssetsDir, "App.framework");
    } else if (Platform.isMacOS) {
      _appAssetsDir = frameworkDir();
      _appAssetsDir = path.join(_appAssetsDir, "App.framework", "Resources");
    } else if (Platform.isAndroid) {
      _appAssetsDir = "";
    } else if (Platform.isLinux) {
      _appAssetsDir = frameworkDir();
      _appAssetsDir = path.join(_appAssetsDir, "data");
    } else if (Platform.isWindows) {
      _appAssetsDir = frameworkDir();
      _appAssetsDir = path.join(_appAssetsDir, "data");
    }
    return _appAssetsDir;
  }

  static String flutterAssetsDir() {
    return path.join(appAssetsDir(), "flutter_assets");
  }

  static String assetsDir() {
    return path.join(flutterAssetsDir(), "assets");
  }

  static String profileDirForPortableMode() {
    return path.join(exeDir(), "portable");
  }

  static Future<String> profileDirNonPortable() async {
    Directory? sharedDirectory = await FlutterVpnService.getAppGroupDirectory(
      AppUtils.getGroupId(),
    );
    if (sharedDirectory != null) {
      if (!await sharedDirectory.exists()) {
        await sharedDirectory.create(recursive: true);
      }

      return sharedDirectory.path;
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? "";
      if (appData.isNotEmpty) {
        final name = AppUtils.getName().toLowerCase();
        final dir = path.join(appData, name, name);
        await Directory(dir).create(recursive: true);
        return dir;
      }
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? "";
      if (home.isNotEmpty) {
        final name = AppUtils.getName().toLowerCase();
        final dir = path.join(home, ".config", name);
        await Directory(dir).create(recursive: true);
        return dir;
      }
    }
    return "";
  }

  static Future<String> profileDir() async {
    if (_profileDir.isNotEmpty) {
      return _profileDir;
    }
    // dev build: keep the profile OUTSIDE build/ so `flutter clean` and
    // full rebuilds never wipe subscriptions/settings. Marker: a `.dev`
    // file inside the exe-relative `portable` dir.
    if (Platform.isWindows) {
      try {
        final marker = File(
          path.join(profileDirForPortableMode(), ".dev"),
        );
        if (marker.existsSync()) {
          final localAppData = Platform.environment['LOCALAPPDATA'] ?? "";
          if (localAppData.isNotEmpty) {
            final dir = path.join(localAppData, "karing-dev");
            await Directory(dir).create(recursive: true);
            _profileDir = dir;
            _portableMode = true;
            return _profileDir;
          }
        }
      } catch (err, stacktrace) {}
    }
    if (Platform.isWindows) {
      try {
        String profileDir = profileDirForPortableMode();
        var file = Directory(profileDir);
        bool exist = await file.exists();
        if (exist) {
          var testDir = Directory(path.join(profileDir, "__test_dir__"));
          await testDir.create(recursive: true);
          await testDir.delete();
          _profileDir = profileDir;
          _portableMode = true;
          return _profileDir;
        }
      } catch (err, stacktrace) {}
    }

    _profileDir = await profileDirNonPortable();
    return _profileDir;
  }

  static Future<String> profilesDir() async {
    String dir = await profileDir();
    String cdir = path.join(dir, profilesName());
    await FileUtils.createDir(cdir);
    return cdir;
  }

  static String profilesName() {
    return "profiles";
  }

  static Future<String> profilePatchsDir() async {
    String dir = await profileDir();
    String cdir = path.join(dir, profilePatchsName());
    await FileUtils.createDir(cdir);
    return cdir;
  }

  static String profilePatchsName() {
    return "profilePatchs";
  }

  static Future<String> backupDir() async {
    String dir = await profileDir();
    String cdir = path.join(dir, "backup");
    await FileUtils.createDir(cdir);
    return cdir;
  }

  static Future<String> cacheDir() async {
    String dir = await profileDir();
    String cdir = path.join(dir, "cache");
    await FileUtils.createDir(cdir);
    return cdir;
  }

  static Future<String> webviewCacheDir() async {
    String dir = await profileDirNonPortable();
    String cdir = path.join(dir, "webviewCache");
    await FileUtils.createDir(cdir);
    return cdir;
  }

  static Future<String> profileDataDir() async {
    String dir = await profileDir();
    String cdir = path.join(dir, "datas");
    await FileUtils.createDir(cdir);
    return cdir;
  }

  static String exeDir() {
    String dir = path.dirname(Platform.resolvedExecutable);
    return dir;
  }

  static String frameworkDir() {
    String filepath = PathUtils.exeDir();
    if (Platform.isIOS) {
      filepath = path.join(filepath, "Frameworks");
    } else if (Platform.isMacOS) {
      filepath = path.dirname(filepath);
      filepath = path.join(filepath, "Frameworks");
    } else if (Platform.isWindows) {
    } else if (Platform.isAndroid) {
      return "";
    } else if (Platform.isLinux) {
    } else {
      throw "unsupport platform";
    }
    return filepath;
  }

  static String macosDir() {
    if (Platform.isMacOS) {
      String filepath = PathUtils.exeDir();
      filepath = path.dirname(filepath);
      filepath = path.join(filepath, "MacOS");
      return filepath;
    }
    return "";
  }

  static String getExeName() {
    if (Platform.isWindows) {
      return "karing.exe";
    }
    if (Platform.isMacOS) {
      return "Karing";
    }
    if (Platform.isLinux) {
      return "karing";
    }
    return "";
  }

  static String serviceExeName() {
    if (Platform.isLinux) {
      return "karingService";
    } else if (Platform.isWindows) {
      return "karingService.exe";
    }
    return "";
  }

  static String serviceExePath() {
    if (Platform.isLinux || Platform.isWindows) {
      String filePath = exeDir();
      return path.join(filePath, serviceExeName());
    }
    return "";
  }

  static String logFileName() {
    return "app.log";
  }

  static Future<String> logFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, logFileName());
  }

  static String serviceStdErrorFileName() {
    return "service_error.log";
  }

  static Future<String> serviceStdErrorFilePath() async {
    String filePath = await PathUtils.profileDir();
    return path.join(filePath, serviceStdErrorFileName());
  }

  static String serviceLogFileName() {
    return "service_core.log";
  }

  static Future<String> serviceLogFilePath() async {
    String filePath = await PathUtils.profileDir();
    return path.join(filePath, serviceLogFileName());
  }

  static String serviceConfigFileName() {
    return "service.json";
  }

  static Future<String> serviceConfigFilePath() async {
    String filePath = await PathUtils.profileDir();
    return path.join(filePath, serviceConfigFileName());
  }

  static String settingFileName() {
    return "setting.json";
  }

  static Future<String> diversionTemplateConfigFilePath() async {
    String filePath = await PathUtils.profileDir();
    return path.join(filePath, diversionTemplateFileName());
  }

  static Future<String> profilesConfigFilePath() async {
    String filePath = await PathUtils.profileDir();
    return path.join(filePath, profilesFileName());
  }

  static Future<String> profilePatchsConfigFilePath() async {
    String filePath = await PathUtils.profileDir();
    return path.join(filePath, profilePatchsFileName());
  }

  static String serviceCoreSettingFileName() {
    return "service_core_setting.json";
  }

  static Future<String> serviceCoreSettingFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, serviceCoreSettingFileName());
  }

  static String serviceCorePatchFinalFileName() {
    return "service_core_patch_final.json";
  }

  static Future<String> serviceCorePatchFinalPath() async {
    String filePath = await profileDir();
    return path.join(filePath, serviceCorePatchFinalFileName());
  }

  static String serviceCoreRuntimeProfileFileName() {
    return "service_core_runtime_profile.yaml";
  }

  static Future<String> serviceCoreRuntimeProfileFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, serviceCoreRuntimeProfileFileName());
  }

  static String profilesFileName() {
    return "profiles.json";
  }

  static String profilePatchsFileName() {
    return "profile_patchs.json";
  }

  static String diversionTemplateFileName() {
    return "diversion_template.json";
  }

  static Future<String> settingFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, settingFileName());
  }

  static String autoUpdateFileName() {
    return "auto_update.json";
  }

  static Future<String> autoUpdateFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, autoUpdateFileName());
  }

  static String remoteConfigFileName() {
    return "remote_config.json";
  }

  static Future<String> remoteConfigFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, remoteConfigFileName());
  }

  static String storageFileName() {
    return "storage.json";
  }

  static Future<String> storageFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, storageFileName());
  }

  static String providersConfigFileName() {
    return "providers.json";
  }

  static Future<String> providersConfigFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, providersConfigFileName());
  }

  static String boardSessionFileName() {
    return "board_sessions.json";
  }

  static Future<String> boardSessionFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, boardSessionFileName());
  }
  static Future<String> getAppSupportDir() async {
    return await profileDir();
  }

  static String subscribeFileName() {
    return "subscriptions.json";
  }

  static Future<String> subscribeFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, subscribeFileName());
  }

  static String subscribeUseFileName() {
    return "subscribe_use.json";
  }

  static Future<String> subscribeUseFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, subscribeUseFileName());
  }

  static String diversionGroupFileName() {
    return "diversion_groups.json";
  }

  static Future<String> diversionGroupFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, diversionGroupFileName());
  }

  static String noticeFileName() {
    return "notice.json";
  }

  static Future<String> noticeFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, noticeFileName());
  }

  static String providerNoticeFileName() {
    return "provider_notice.json";
  }

  static Future<String> providerNoticeFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, providerNoticeFileName());
  }

  static String remoteISPConfigFileName() {
    return "remote_isp_config.json";
  }

  static Future<String> remoteISPConfigFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, remoteISPConfigFileName());
  }

  static String serviceCoreConfigFileName() {
    return "core_config.json";
  }

  static Future<String> serviceCoreConfigFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, serviceCoreConfigFileName());
  }

  static String statisticsDBFileName() {
    return "statistics.db";
  }

  static Future<String> statisticsDBFilePath() async {
    String filePath = await profileDataDir();
    return path.join(filePath, statisticsDBFileName());
  }

  static String cacheDBFileName() {
    return "cache.db";
  }

  static Future<String> cacheDBFilePath() async {
    String filePath = await profileDataDir();
    return path.join(filePath, cacheDBFileName());
  }

  static String cloudflareWarpFileName() {
    return "cloudflare_warp.json";
  }

  static Future<String> cloudflareWarpFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, cloudflareWarpFileName());
  }

  static String ispNoticeFileName() {
    return "isp_notice.json";
  }

  static Future<String> ispNoticeFilePath() async {
    String filePath = await profileDir();
    return path.join(filePath, ispNoticeFileName());
  }

  static String geositeDirName() {
    return "geosite";
  }

  static Future<String> geositeDir() async {
    String filePath = await profileDir();
    return path.join(filePath, geositeDirName());
  }

  static String geoipDirName() {
    return "geoip";
  }

  static Future<String> geoipDir() async {
    String filePath = await profileDir();
    return path.join(filePath, geoipDirName());
  }

  static String aclDirName() {
    return "acl";
  }

  static Future<String> aclDir() async {
    String filePath = await profileDir();
    return path.join(filePath, aclDirName());
  }

  static Future<String> geoDataDir() async {
    return await profileDir();
  }
}