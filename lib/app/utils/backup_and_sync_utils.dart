/// Backup & sync helpers. Cloud backends are stubs in this build.
import 'package:flutter/widgets.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/zip_utils.dart';

class BackupFileItem {
  String fileName = "";
  bool required = false;
  BackupFileItem(this.fileName, {this.required = false});
}

class BackupAndSyncUtils {
  static String get zipExtension => ".zip";

  static String getZipFileName() {
    return "karing-backup.zip";
  }

  static List<BackupFileItem> getZipFileNameList() {
    return [
      BackupFileItem("subscriptions.json", required: true),
      BackupFileItem("subscribe_use.json", required: true),
      BackupFileItem("diversion_groups.json", required: true),
      BackupFileItem("settings.json", required: true),
    ];
  }

  static Future<ReturnResultError?> validZip(String path) async {
    final list = await ZipUtils.list(path);
    if (list.isEmpty) {
      return ReturnResultError("invalid zip");
    }
    return null;
  }

  static Future<ReturnResultError?> backup(String path) async {
    return null;
  }

  static Future<ReturnResultError?> restore(String path) async {
    return null;
  }
}