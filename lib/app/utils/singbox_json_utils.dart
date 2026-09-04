import 'dart:convert';

import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_outbound.dart';

/// Translation fallback for unsupported strings (used by importers).
class TransExceptionAndUnsupport {
  String exception(String what) => "exception: $what";
  String unsupport(String what) => "unsupported: $what";
}

/// Converts a raw sing-box profile json into karing server groups.
class SingboxJsonUtils {
  static ReturnResult<bool> tryConvert(
    String content,
    ServerConfigGroupItem proxyItem,
    List<ServerDiversionGroupRuleSetItem> rulesetItems,
    ServerConfigGroupItem? groupItem, [
    TransExceptionAndUnsupport? eu,
  ]) {
    dynamic json;
    try {
      json = jsonDecode(content);
    } catch (err) {
      return ReturnResult(error: ReturnResultError("not valid json"));
    }
    if (json is! Map) {
      return ReturnResult(error: ReturnResultError("config must be a json object"));
    }
    final outbounds = json['outbounds'];
    if (outbounds is! List || outbounds.isEmpty) {
      return ReturnResult(error: ReturnResultError("no outbounds in config"));
    }
    for (final ob in outbounds) {
      if (ob is! Map) {
        continue;
      }
      final type = ob['type']?.toString() ?? "";
      if (type == 'selector' ||
          type == 'urltest' ||
          type == 'direct' ||
          type == 'block' ||
          type == 'dns') {
        continue;
      }
      final proxy = ProxyConfig();
      proxy.groupid = proxyItem.groupid;
      proxy.type = kOutboundTypeServer;
      proxy.raw = Map<String, dynamic>.from(ob);
      proxy.url = "";
      try {
        final options = SingboxOutboundOptions();
        options.fromJson(Map<String, dynamic>.from(ob));
        proxy.tag =
            (options.tag.isNotEmpty ? options.tag : ob['tag']?.toString() ?? "")
                .trim();
        proxy.server = options.server;
        proxy.serverport = options.serverPort;
      } catch (_) {
        proxy.tag = ob['tag']?.toString() ?? "proxy-${proxyItem.servers.length}";
      }
      if (proxy.tag.isEmpty) {
        proxy.tag = "proxy-${proxyItem.servers.length + 1}";
      }
      proxyItem.servers.add(proxy);
    }
    if (proxyItem.servers.isEmpty) {
      return ReturnResult(error: ReturnResultError("no proxy outbounds found"));
    }
    return ReturnResult(data: true);
  }
}
