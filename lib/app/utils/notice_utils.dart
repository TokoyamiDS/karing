import 'dart:convert';

import 'package:karing/app/utils/karing_utils.dart' show RawNoticeItem;
import 'package:karing/app/utils/proxy_conf_utils.dart';

/// Parses remote notice payloads for boards.
class NoticeUtils {
  /// parses a notice json payload into a RawNoticeItem, null if not newer.
  static RawNoticeItem? parseNotice(String content) {
    if (content.isEmpty) {
      return null;
    }
    try {
      final json = const JsonDecoder().convert(content);
      if (json is Map) {
        final item = RawNoticeItem();
        item.fromJson(json.map((k, v) => MapEntry(k.toString(), v)));
        return item;
      }
    } catch (_) {}
    return null;
  }

  static bool isSubscriptionExpired(SubscriptionTraffic? traffic) {
    if (traffic == null) {
      return false;
    }
    if (traffic.expire <= 0) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch * 1000;
    return traffic.expire < now;
  }
}
