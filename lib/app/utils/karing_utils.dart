import 'dart:convert';
import 'dart:io';

import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/http_utils.dart';
import 'package:karing/app/utils/path_utils.dart';

/// A remote notice item.
class RawNoticeItem {
  String title = "";
  String content = "";
  String url = "";
  String updateTime = "";
  String expireTime = "";

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'url': url,
        'update_time': updateTime,
        'expire_time': expireTime,
      };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    title = map['title'] ?? "";
    content = map['content'] ?? "";
    url = map['url'] ?? "";
    updateTime = map['update_time'] ?? "";
    expireTime = map['expire_time'] ?? "";
  }
}

/// Fetches the app notice from the remote config url.
class KaringUtils {
  static Future<ReturnResult<RawNoticeItem>> getNotice(
      String url, bool updateWhenConnected) async {
    try {
      final result = await HttpUtils.httpGetRequest(
        url,
        null,
        null,
        const Duration(seconds: 15),
        null,
        null,
      );
      if (result.error != null) {
        return ReturnResult(error: result.error);
      }
      final json = jsonDecode(result.data!.item2);
      final item = RawNoticeItem();
      if (json is Map) {
        item.fromJson(json.map((k, v) => MapEntry(k.toString(), v)));
      } else {
        item.content = result.data!.item2;
        item.title = "";
      }
      return ReturnResult(data: item);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<void> setNotice(String content) async {
    try {
      final path = await PathUtils.getAppSupportDir();
      final f = File('$path/notice.md');
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
    } catch (_) {}
  }

  static String versionToIntegerString(String version) {
    return version.split('.').map((e) => e.padLeft(4, '0')).join();
  }

  static bool isDeveloperMode() {
    return false;
  }

  static String encodeClipboard(String content) {
    return base64Encode(utf8.encode(content));
  }

  static String decodeClipboard(String content) {
    try {
      return utf8.decode(base64Decode(content));
    } catch (_) {
      return "";
    }
  }
}
