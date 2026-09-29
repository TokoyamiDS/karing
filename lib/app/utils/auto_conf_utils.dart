import 'dart:convert';
import 'dart:io';

import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/http_utils.dart';
import 'package:tuple/tuple.dart';
import 'package:karing/app/utils/singbox_json_utils.dart';
import 'package:karing/app/utils/singbox_outbound.dart';

class AutoConfUtils {
  /// Detects the subscription/link type from content or url.
  static SubscriptionLinkType getLinkType(String content, String url) {
    if (content.startsWith('[') || content.startsWith('{')) {
      try {
        final json = jsonDecode(content);
        if (json is Map) {
          if (json['outbounds'] != null) {
            return SubscriptionLinkType.singbox;
          }
          if (json['proxies'] != null || json['proxy-groups'] != null) {
            return SubscriptionLinkType.clash;
          }
        }
      } catch (_) {}
    }
    final lower = url.toLowerCase();
    if (lower.contains('clash') || lower.contains('mihomo')) {
      return SubscriptionLinkType.clash;
    }
    return SubscriptionLinkType.unknown;
  }

  /// returns true if the content is a list of share links.
  static bool isShareLinks(String content) {
    final schemes = [
      'vless://',
      'vmess://',
      'trojan://',
      'ss://',
      'hysteria2://',
      'hy2://',
      'tuic://',
      'wireguard://',
      'socks://',
      'http://',
      'https://',
    ];
    for (final line in content.split(RegExp(r'[\r\n]+'))) {
      final l = line.trim();
      for (final scheme in schemes) {
        if (l.startsWith(scheme)) {
          return true;
        }
      }
    }
    return false;
  }

  static String? getScheme(String content) {
    for (final line in content.split(RegExp(r'[\r\n]+'))) {
      final l = line.trim();
      final m = RegExp(r'^([a-zA-Z0-9+.-]+)://').firstMatch(l);
      if (m != null) {
        return m.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  /// Main entry: converts a url/file path/content into a server group.
  static Future<ReturnResultError?> tryConvert(
    String urlOrPath,
    bool local,
    bool isAdd,
    ServerConfigGroupItem group,
    List<ServerDiversionGroupRuleSetItem> rulesetItems,
    ServerDiversionGroupItem? diversionGroupItem,
    RemoteContent? remoteContent,
  ) async {
    String content = remoteContent?.text ?? "";
    if (content.isEmpty) {
      try {
        if (local ||
            (!urlOrPath.startsWith('http://') &&
                !urlOrPath.startsWith('https://'))) {
          final file = File(urlOrPath);
          if (await file.exists()) {
            group.urlOrPath = urlOrPath;
            content = await file.readAsString();
          } else {
            content = urlOrPath;
          }
        } else {
          group.urlOrPath = urlOrPath;
          // official behavior: subscription downloads ride the proxy
          // (raw.githubusercontent.com etc. are blocked direct from Iran);
          // fall back to direct when the proxy is down or fails.
          final proxyPort = SettingManager.getConfig().proxy.mixedRulePort;
          final userAgent = await HttpUtils.getUserAgent(
            compatible: HttpUtils.getUserAgentsByUaString(group.userAgentCompatibles),
          );
          ReturnResult<Tuple2<int, String>> result =
              await HttpUtils.httpGetRequest(
            urlOrPath,
            await VPNService.getStarted() ? proxyPort : null,
            null,
            const Duration(seconds: 30),
            userAgent,
            null,
          );
          if (result.error != null || (result.data?.item2.isEmpty ?? true)) {
            final direct = await HttpUtils.httpGetRequest(
              urlOrPath,
              null,
              null,
              const Duration(seconds: 30),
              userAgent,
              null,
            );
            if (direct.error != null) {
              return ReturnResultError(
                result.error?.message ?? direct.error!.message,
              );
            }
            content = direct.data!.item2;
          } else {
            content = result.data!.item2;
          }
        }
      } catch (err) {
        return ReturnResultError(err.toString());
      }
    }
    if (content.isEmpty) {
      return ReturnResultError("empty content");
    }

    content = _maybeBase64Decode(content);

    final type = getLinkType(content, urlOrPath);
    switch (type) {
      case SubscriptionLinkType.singbox:
        return _convertSingbox(content, group);
      case SubscriptionLinkType.clash:
        return _convertClash(content, group);
      default:
        return _convertShareLinks(content, group);
    }
  }

  static String _maybeBase64Decode(String content) {
    final compact = content.replaceAll(RegExp(r'\s'), '');
    if (compact.contains('://') || compact.startsWith('{') || compact.startsWith('[')) {
      return content;
    }
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(compact)));
      if (decoded.contains('://') || decoded.startsWith('{') || decoded.startsWith('[')) {
        return decoded;
      }
    } catch (_) {}
    return content;
  }

  static ReturnResultError? _convertSingbox(
      String content, ServerConfigGroupItem group) {
    final err = SingboxJsonUtils.tryConvert(content, group, [], null);
    if (err.error != null) {
      return err.error;
    }
    return null;
  }

  static ReturnResultError? _convertClash(
      String content, ServerConfigGroupItem group) {
    dynamic json;
    try {
      json = jsonDecode(content);
    } catch (err) {
      return ReturnResultError("invalid clash yaml/json");
    }
    if (json is! Map) {
      return ReturnResultError("invalid clash config");
    }
    final proxies = json['proxies'];
    if (proxies is! List) {
      return ReturnResultError("no proxies in clash config");
    }
    for (final p in proxies) {
      if (p is! Map) continue;
      final proxy = ProxyConfig();
      proxy.groupid = group.groupid;
      proxy.type = kOutboundTypeServer;
      proxy.tag = (p['name'] ?? "proxy-${group.servers.length + 1}").toString();
      proxy.server = (p['server'] ?? "").toString();
      proxy.serverport = int.tryParse((p['port'] ?? '0').toString()) ?? 0;
      proxy.raw = Map<String, dynamic>.from(p);
      group.servers.add(proxy);
    }
    if (group.servers.isEmpty) {
      return ReturnResultError("no usable proxies in clash config");
    }
    return null;
  }

  static ReturnResultError? _convertShareLinks(
      String content, ServerConfigGroupItem group) {
    int count = 0;
    for (var line in content.split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      if (line.isEmpty) continue;
      final proxy = _convertShareLink(line, group);
      if (proxy != null) {
        group.servers.add(proxy);
        count++;
      }
    }
    if (count == 0) {
      return ReturnResultError("no share links found");
    }
    return null;
  }

  static ProxyConfig? _convertShareLink(String line, ServerConfigGroupItem group) {
    final proxy = ProxyConfig();
    proxy.groupid = group.groupid;
    proxy.type = kOutboundTypeServer;
    proxy.clipboardLink = line;

    if (line.startsWith('vmess://')) {
      return _convertVmess(line, proxy);
    }
    final schemeMatch = RegExp(r'^([a-zA-Z0-9+.-]+)://').firstMatch(line);
    if (schemeMatch == null) {
      return null;
    }
    final scheme = schemeMatch.group(1)!.toLowerCase();
    if (scheme != 'vless' &&
        scheme != 'trojan' &&
        scheme != 'ss' &&
        scheme != 'hysteria2' &&
        scheme != 'hy2' &&
        scheme != 'tuic') {
      return null;
    }
    final parsed = _parseUri(line);
    if (parsed == null) {
      return null;
    }
    final (scheme2, userInfo, host, port, params, remark) = parsed;
    final tls = _tlsFromParams(params);
    final transport = _transportFromParams(params);
    switch (scheme2) {
      case 'vless':
        {
          final out = <String, dynamic>{
            'type': 'vless',
            'server': host,
            'server_port': port,
            'uuid': userInfo,
          };
          final flow = normalizeVlessFlow(params['flow']);
          if (flow.isNotEmpty) {
            out['flow'] = flow;
          }
          if (tls.isNotEmpty) {
            out['tls'] = tls;
          }
          if (transport.isNotEmpty) {
            out['transport'] = transport;
          }
          proxy.raw = out;
          break;
        }
      case 'trojan':
        {
          final out = <String, dynamic>{
            'type': 'trojan',
            'server': host,
            'server_port': port,
            'password': userInfo,
          };
          if (tls.isNotEmpty) {
            out['tls'] = tls;
          }
          if (transport.isNotEmpty) {
            out['transport'] = transport;
          }
          proxy.raw = out;
          break;
        }
      case 'ss':
        {
          String method;
          String password;
          if (userInfo.contains(':')) {
            final idx = userInfo.indexOf(':');
            method = userInfo.substring(0, idx);
            password = userInfo.substring(idx + 1);
          } else {
            // legacy format: whole userinfo is base64(method:password)
            try {
              final decoded =
                  utf8.decode(base64.decode(base64.normalize(userInfo)));
              final idx = decoded.indexOf(':');
              if (idx <= 0) {
                return null;
              }
              method = decoded.substring(0, idx);
              password = decoded.substring(idx + 1);
            } catch (_) {
              return null;
            }
          }
          final out = <String, dynamic>{
            'type': 'shadowsocks',
            'server': host,
            'server_port': port,
            'method': method,
            'password': password,
          };
          final plugin = params['plugin'];
          if ((plugin ?? '').isNotEmpty) {
            var pluginName = plugin!;
            var pluginOpts = '';
            final semi = plugin.indexOf(';');
            if (semi > 0) {
              pluginName = plugin.substring(0, semi);
              pluginOpts = plugin.substring(semi + 1);
            }
            if (pluginName == 'simple-obfs') {
              pluginName = 'obfs-local';
            }
            out['plugin'] = pluginName;
            if (pluginOpts.isNotEmpty) {
              out['plugin_opts'] = pluginOpts;
            }
          }
          proxy.raw = out;
          break;
        }
      case 'hysteria2':
      case 'hy2':
        {
          final out = <String, dynamic>{
            'type': 'hysteria2',
            'server': host,
            'server_port': port,
            'password': userInfo,
          };
          final obfsPassword = params['obfs-password'];
          if ((obfsPassword ?? '').isNotEmpty) {
            out['obfs'] = {'type': 'salamander', 'password': obfsPassword};
          }
          final up = int.tryParse(params['up'] ?? '');
          final down = int.tryParse(params['down'] ?? '');
          if (up != null && up > 0) {
            out['up_mbps'] = up;
          }
          if (down != null && down > 0) {
            out['down_mbps'] = down;
          }
          if ((params['pinSHA256'] ?? '').isNotEmpty) {
            // providers pairing pinSHA256 with a self-signed cert expect the
            // fingerprint path, not user trust (same behavior as v2rayN)
            tls['insecure'] = true;
          }
          if (tls.isNotEmpty) {
            out['tls'] = tls;
          }
          proxy.raw = out;
          break;
        }
      case 'tuic':
        {
          final idx = userInfo.indexOf(':');
          final out = <String, dynamic>{
            'type': 'tuic',
            'server': host,
            'server_port': port,
          };
          if (idx > 0) {
            out['uuid'] = userInfo.substring(0, idx);
            out['password'] = userInfo.substring(idx + 1);
          }
          if ((params['congestion_control'] ?? '').isNotEmpty) {
            out['congestion_control'] = params['congestion_control'];
          }
          if ((params['udp_relay_mode'] ?? '').isNotEmpty) {
            out['udp_relay_mode'] = params['udp_relay_mode'];
          }
          if (tls.isNotEmpty) {
            out['tls'] = tls;
          }
          proxy.raw = out;
          break;
        }
      default:
        return null;
    }
    proxy.tag = remark.isEmpty ? "$host:$port" : remark;
    if (proxy.tag.length > kRemarkMaxLength) {
      proxy.tag = proxy.tag.substring(0, kRemarkMaxLength);
    }
    proxy.server = host;
    proxy.serverport = port;
    return proxy;
  }

  static Map<String, dynamic> _tlsFromParams(Map<String, String> params) {
    final security = params['security'] ?? 'tls';
    final tlsEnabled = security == 'tls' || security == 'reality';
    if (!tlsEnabled) {
      return {};
    }
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': params['sni'] ?? params['peer'] ?? "",
      'insecure': (params['allowInsecure'] ??
              params['insecure'] ??
              params['allow_insecure'] ??
              '0') ==
          '1',
    };
    if ((params['alpn'] ?? '').isNotEmpty) {
      tls['alpn'] = params['alpn']!
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if ((params['fp'] ?? '').isNotEmpty) {
      tls['utls'] = {
        'enabled': true,
        'fingerprint': params['fp'] == 'unsafe' ? 'chrome' : params['fp'],
      };
    }
    if ((params['cs'] ?? '').isNotEmpty) {
      tls['cipher_suites'] =
          params['cs']!.split(':').where((c) => c.isNotEmpty).toList();
    }
    if (security == 'reality') {
      tls['reality'] = {
        'enabled': true,
        'public_key': params['pbk'] ?? "",
        'short_id': params['sid'] ?? "",
      };
    }
    // sing-box requires ech.config to be a PEM ECHConfigList. Publishers sometimes put a
    // DNS URL in ech= (e.g. "ip.gs+udp://8.8.8.8"), and the core then refuses to start at
    // all: "FATAL initialize outbound[N]: invalid ECH configs pem". Only accept PEM.
    final echParam = params['ech'] ?? '';
    if (echParam.contains('-----BEGIN')) {
      tls['ech'] = {'enabled': true, 'config': echParam};
    }
    // PattN/karing share links: fm= carries a finalmask JSON (per-node TLS
    // fragmentation tuning) — lengths/delays override global settings.
    final fm = params['fm'] ?? '';
    var fmSizes = <String>[];
    var fmDelays = <String>[];
    if (fm.isNotEmpty) {
      try {
        final decoded = jsonDecode(_safeDecode(fm));
        if (decoded is Map && decoded['tcp'] is List && decoded['tcp'].isNotEmpty) {
          final settings = decoded['tcp'][0]['settings'];
          if (settings is Map) {
            if (settings['lengths'] is List) {
              fmSizes = List<String>.from(
                  settings['lengths'].map((e) => e.toString()));
            }
            if (settings['delays'] is List) {
              fmDelays = List<String>.from(
                  settings['delays'].map((e) => e.toString()));
            }
          }
        }
      } catch (_) {}
    }
    final tlsSetting = SettingManager.getConfig().tls;
    tls['insecure'] =
        (tls['insecure'] == true) || tlsSetting.enableInsecure;
    tls['fragment'] = tlsSetting.enableFragment || fmSizes.isNotEmpty;
    tls['record_fragment'] = tls['fragment'];
    if (tls['fragment']) {
      tls['fragment_sizes'] =
          fmSizes.isNotEmpty ? fmSizes : tlsSetting.fragmentSize.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      tls['fragment_delays'] =
          fmDelays.isNotEmpty ? fmDelays : tlsSetting.fragmentSleep.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return tls;
  }

  static Map<String, dynamic> _transportFromParams(
      Map<String, String> params) {
    // v2rayN-family shares: headerType=http on tcp transport = http obfs,
    // which sing-box models as a `http` transport.
    var type = params['type'] ?? 'tcp';
    if (type == 'tcp' && params['headerType'] == 'http') {
      type = 'http';
    }
    // When a share link omits `host`, the Host header defaults to the SNI. That
    // is what v2rayN/Xray do, and on a Cloudflare-fronted node it is not
    // cosmetic: Cloudflare routes by Host, so without it the WebSocket upgrade is
    // answered 403 and the node never connects — while the same link works fine
    // in v2rayN. Reproduced against a real link: Host = SNI gave 503 (the origin
    // was down, i.e. past Cloudflare), Host = the dialled IP gave 403.
    final host = (params['host'] ?? '').isNotEmpty
        ? params['host']!
        : (params['sni'] ?? params['peer'] ?? '');
    if (type == 'ws') {
      final tr = <String, dynamic>{'type': 'ws'};
      var path = params['path'] ?? '';
      if (path.isNotEmpty) tr['path'] = path;
      if (host.isNotEmpty) {
        tr['headers'] = {'Host': host};
      }
      if ((params['eh'] ?? '').isNotEmpty) {
        tr['early_data_header_name'] = params['eh']!;
      }
      final edMatch = RegExp(r'[?&]ed=(\d+)').firstMatch(path);
      final ed = int.tryParse(params['ed'] ?? '') ??
          (edMatch != null ? int.tryParse(edMatch.group(1)!) : null);
      if (ed != null && ed > 0) {
        tr['max_early_data'] = ed;
        tr.putIfAbsent(
            'early_data_header_name', () => 'Sec-WebSocket-Protocol');
        path = path.replaceAll(RegExp(r'[?&]ed=\d+'), '');
        if (path.isNotEmpty) {
          tr['path'] = path;
        } else {
          tr.remove('path');
        }
      }
      return tr;
    } else if (type == 'grpc') {
      final tr = <String, dynamic>{'type': 'grpc'};
      if ((params['serviceName'] ?? '').isNotEmpty) {
        tr['service_name'] = params['serviceName']!;
      }
      return tr;
    } else if (type == 'h2' || type == 'http') {
      final tr = <String, dynamic>{'type': 'http'};
      if ((params['path'] ?? '').isNotEmpty) tr['path'] = params['path'];
      if (host.isNotEmpty) {
        tr['host'] = host
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return tr;
    } else if (type == 'httpupgrade') {
      final tr = <String, dynamic>{'type': 'httpupgrade'};
      if ((params['path'] ?? '').isNotEmpty) tr['path'] = params['path'];
      if (host.isNotEmpty) tr['host'] = host;
      return tr;
    }
    return {};
  }

  static ProxyConfig? _convertVmess(String line, ProxyConfig proxy) {
    final b64 = line.substring('vmess://'.length).replaceAll(RegExp(r'\s'), '');
    try {
      final json = jsonDecode(utf8.decode(base64.decode(base64.normalize(b64))));
      if (json is! Map) {
        return null;
      }
      final tlsEnabled = (json['tls'] ?? '').toString() == 'tls';
      final out = <String, dynamic>{
        'type': 'vmess',
        'server': (json['add'] ?? "").toString(),
        'server_port': int.tryParse((json['port'] ?? '0').toString()) ?? 0,
        'uuid': (json['id'] ?? "").toString(),
        'security': ((json['scy'] ?? json['security']) ?? 'auto').toString(),
        'alter_id': int.tryParse((json['aid'] ?? '0').toString()) ?? 0,
      };
      if (tlsEnabled) {
      final tlsSetting = SettingManager.getConfig().tls;
      out['tls'] = {
        'enabled': true,
        'server_name': (json['sni'] ?? "").toString(),
        'insecure': (json['insecure'] ?? '0').toString() == '1' ||
            tlsSetting.enableInsecure,
        if ((json['alpn'] ?? '').toString().isNotEmpty)
          'alpn': (json['alpn'] ?? "").toString().split(','),
        'fragment': tlsSetting.enableFragment,
        'record_fragment': tlsSetting.enableFragment,
        if (tlsSetting.enableFragment) ...{
          'fragment_sizes': tlsSetting.fragmentSize
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          'fragment_delays': tlsSetting.fragmentSleep
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        },
      };
      }
      final net = (json['net'] ?? '').toString();
      final host = (json['host'] ?? "").toString();
      final path = (json['path'] ?? "").toString();
      if (net == 'ws') {
        final tr = <String, dynamic>{'type': 'ws'};
        if (path.isNotEmpty) tr['path'] = path;
        if (host.isNotEmpty) {
          tr['headers'] = {'Host': host};
        }
        out['transport'] = tr;
      } else if (net == 'grpc') {
        // vmess link shares carry the grpc service name in `path`
        if (path.isNotEmpty) out['transport'] = {'type': 'grpc', 'service_name': path};
      } else if (net == 'httpupgrade') {
        final tr = <String, dynamic>{'type': 'httpupgrade'};
        if (path.isNotEmpty) tr['path'] = path;
        if (host.isNotEmpty) tr['host'] = host;
        out['transport'] = tr;
      } else if (net == 'h2' || net == 'tcp') {
        if (json['type'].toString() == 'http' || net == 'h2') {
          final tr = <String, dynamic>{'type': 'http'};
          if (path.isNotEmpty) tr['path'] = path;
          if (host.isNotEmpty) {
            tr['host'] = host.split(',').where((e) => e.isNotEmpty).toList();
          }
          out['transport'] = tr;
        }
      }
      proxy.raw = out;
      proxy.tag = (json['ps'] ?? "").toString();
      if (proxy.tag.isEmpty) {
        proxy.tag = "${json['add']}:${json['port']}";
      }
      if (proxy.tag.length > kRemarkMaxLength) {
        proxy.tag = proxy.tag.substring(0, kRemarkMaxLength);
      }
      proxy.server = (json['add'] ?? "").toString();
      proxy.serverport = int.tryParse((json['port'] ?? '0').toString()) ?? 0;
      return proxy;
    } catch (_) {
      return null;
    }
  }

  /// Uri.decodeComponent throws on malformed percent sequences — Patt's
  /// fm= JSON params contain raw % signs. Fall back to the raw value.
  static String _safeDecode(String value) {
    if (!value.contains('%')) {
      return value;
    }
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  static (String, String, String, int, Map<String, String>, String)? _parseUri(
      String raw) {
    final schemeEnd = raw.indexOf('://');
    if (schemeEnd < 0) return null;
    final scheme = raw.substring(0, schemeEnd).toLowerCase();
    var rest = raw.substring(schemeEnd + 3);
    String remark = "";
    final hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      remark = _safeDecode(rest.substring(hashIdx + 1));
      rest = rest.substring(0, hashIdx);
    }
    Map<String, String> params = {};
    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) {
      final qs = rest.substring(qIdx + 1);
      rest = rest.substring(0, qIdx);
      for (final pair in qs.split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        if (eq < 0) {
          params[_safeDecode(pair)] = '';
        } else {
          params[_safeDecode(pair.substring(0, eq))] =
              _safeDecode(pair.substring(eq + 1));
        }
      }
    }
    String userinfo = "";
    final at = rest.lastIndexOf('@');
    if (at >= 0) {
      userinfo = _safeDecode(rest.substring(0, at));
      rest = rest.substring(at + 1);
    }
    String host;
    int port;
    if (rest.startsWith('[')) {
      final close = rest.indexOf(']');
      host = rest.substring(1, close);
      final colon = rest.indexOf(':', close);
      port = colon >= 0 ? int.tryParse(rest.substring(colon + 1)) ?? 443 : 443;
    } else {
      final colon = rest.lastIndexOf(':');
      if (colon >= 0) {
        host = rest.substring(0, colon);
        port = int.tryParse(rest.substring(colon + 1)) ?? 443;
      } else {
        host = rest;
        port = 443;
      }
    }
    if (host.isEmpty) {
      return null;
    }
    return (scheme, userinfo, host, port, params, remark);
  }
}
