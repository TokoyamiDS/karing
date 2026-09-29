import 'package:tuple/tuple.dart';
import 'dart:convert';
import 'dart:io';

import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/app_utils.dart';
import 'package:karing/app/utils/log.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_outbound.dart';
import 'package:karing/app/utils/tag_gen.dart';

enum SingboxExportType {
  karing,
  karing_standalone,
  tvos,
  singbox,
  clash;

  static SingboxExportType fromString(String name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return SingboxExportType.karing;
  }
}



const String kOutboundTagProxy = "proxy";
const String kOutboundTagDirect = "direct";
const String kOutboundTagBlock = "block";
const String kOutboundTagUrltest = "urltest";
const String kOutboundTagAutoSelect = "AutoSelect";
const int kOutboundMaxCount = 100;

class SingboxInboundTunOptions {
  static const String ipv4Address = "172.19.0.1/30";
  static const String ipv6Address = "fdfe:dcba:9876::1/126";

  String type = "tun";
  String tag = "tun-in";
  String interfaceName = "karing";
  List<String> address = [ipv4Address, ipv6Address];
  int mtu = 4064;
  bool autoRoute = true;
  bool strictRoute = false;
  String stack = "gvisor";
  bool includeAllNetworks = false;
  bool excludeLocalNetworks = false;
  List<String> includePackage = [];
  List<String> excludePackage = [];
  bool hijackDns = true;
  int udpTimeout = 300;

  List<String> get include_package => includePackage;
  set include_package(List<String> v) => includePackage = v;
  List<String> get exclude_package => excludePackage;
  set exclude_package(List<String> v) => excludePackage = v;
  List<String> get address2 => address;
  set address2(List<String> v) => address = v;

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'type': type,
      'tag': tag,
      'interface_name': interfaceName,
      'address': address,
      'mtu': mtu,
      'auto_route': autoRoute,
      'strict_route': strictRoute,
      'stack': stack,
    };
    if (includePackage.isNotEmpty) out['include_package'] = includePackage;
    if (excludePackage.isNotEmpty) out['exclude_package'] = excludePackage;
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    address = List<String>.from(map['address'] ?? address);
    mtu = map['mtu'] ?? mtu;
    autoRoute = map['auto_route'] ?? true;
    strictRoute = map['strict_route'] ?? false;
    stack = map['stack'] ?? stack;
    includePackage = List<String>.from(map['include_package'] ?? []);
    excludePackage = List<String>.from(map['exclude_package'] ?? []);
  }
}

class SingboxInboundMixedOptions {
  static const String hostLocal = '127.0.0.1';

  String type = "mixed";
  String tag = "mixed-in";
  String listen = "127.0.0.1";
  int listen_port = 0;
  int get listenPort => listen_port;
  set listenPort(int v) => listen_port = v;

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'type': type,
      'tag': tag,
      'listen': listen,
      'listen_port': listen_port,
    };
    return out;
  }
}

class SingboxConfig {
  dynamic log;
  dynamic dns;
  dynamic ntp;
  List<dynamic> inbounds = [];
  List<dynamic> outbounds = [];
  dynamic route;
  dynamic experimental;

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    if (log != null) out['log'] = log;
    if (dns != null) out['dns'] = dns;
    if (ntp != null) out['ntp'] = ntp;
    if (inbounds.isNotEmpty) out['inbounds'] = inbounds;
    if (outbounds.isNotEmpty) out['outbounds'] = outbounds;
    if (route != null) out['route'] = route;
    if (experimental != null) out['experimental'] = experimental;
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    log = map['log'];
    dns = map['dns'];
    ntp = map['ntp'];
    inbounds = List.from(map['inbounds'] ?? []);
    outbounds = List.from(map['outbounds'] ?? []);
    route = map['route'];
    experimental = map['experimental'];
  }
}

class SingboxConfigBuilder {
  static const String kOutboundTagProxy = "proxy";
  static const String kOutboundTagDirect = "direct";
  static const String kOutboundTagBlock = "block";
  static const String kOutboundTagDns = "dns-out";
  static const String kOutboundTagUrltest = "urltest";
  static const String kOutboundTagAutoSelect = "AutoSelect";
  static const String kOutboundTagSpecial = "special";

  static dynamic log(SingboxExportType type) {
    // At `warn` the core stays silent about a failed delay test — all the app
    // ever sees is the Clash API's generic "An error occurred in the delay
    // test", with no reason attached. A diagnostic build asks for debug output.
    //
    // Point the core at its own log file rather than relying on the app
    // capturing its stdout/stderr: the core logs to **stderr**, and that capture
    // proved unreliable in practice — neither `service_core.log` nor
    // `service_error.log` was ever created. A file the core writes itself cannot
    // be lost that way. Only set when a writable directory has been probed,
    // because sing-box *fatal*s on an unwritable `log.output`.
    final coreLog = kDiagnosticLogging
        ? PathUtils.coreLogOutputPathIfProbed()
        : null;
    return {
      'level': kDiagnosticLogging ? 'debug' : 'warn',
      'timestamp': true,
      if (coreLog != null) 'output': coreLog,
    };
  }

  static dynamic experimental() {
    final setting = SettingManager.getConfig();
    return {
      'clash_api': {
        'external_controller': "127.0.0.1:${setting.proxy.controlPort}",
        'default_mode': 'Rule',
      },
      'cache_file': {
        'enabled': true,
        'store_fakeip': false,
      },
    };
  }

  static dynamic ntp() {
    final ntp = SettingManager.getConfig().ntp;
    if (!ntp.enable) {
      return null;
    }
    return {
      'enabled': true,
      'server': ntp.server,
      'port': ntp.port,
      'interval': '30m',
    };
  }

  static dynamic buildOutbound(ProxyConfig? server) {
    if (server == null) {
      return null;
    }
    if (server.type == kOutboundTypeServer) {
      final options = SingboxOutboundOptions();
      if (server.raw != null && server.raw.isNotEmpty) {
        try {
          options.fromJson(server.raw);
          options.tag = server.tag;
          return _normalizeOutboundCompatibility(options.toJson());
        } catch (_) {}
      }
      return _normalizeOutboundCompatibility(_outboundFromUrl(server));
    } else if (server.type == kOutboundTypeUrltest) {
      // Group outbounds are built with the same non-interrupting semantics as
      // the main `proxy` selector — see the comment there.
      return {
        'type': 'urltest',
        'tag': server.tag,
        'outbounds': _selectorOutbounds(server),
        'tolerance': 50,
        'interrupt_exist_connections': false,
      };
    } else if (server.type == kOutboundTypeDirect) {
      return {'type': 'direct', 'tag': server.tag};
    } else if (server.type == kOutboundTypeBlock) {
      return {'type': 'block', 'tag': server.tag};
    } else if (server.type == kOutboundTypeDns) {
      return {'type': 'dns', 'tag': server.tag};
    } else if (server.type == kOutboundTypeSelector) {
      return {
        'type': 'selector',
        'tag': server.tag,
        'outbounds': _selectorOutbounds(server),
        'interrupt_exist_connections': false,
      };
    } else {
      if (server.raw == null || server.raw.isEmpty) {
        return null;
      }
      return _normalizeOutboundCompatibility(server.raw);
    }
  }

  /// Normalizes values that are valid in Xray/v2rayN but rejected by the
  /// installed sing-box core. This final pass is intentionally performed at
  /// config emission time as well as during import: existing persisted
  /// profiles can contain legacy values and all enabled nodes are aggregated
  /// into the generated config.
  static dynamic _normalizeOutboundCompatibility(dynamic outbound) {
    if (outbound is! Map) {
      return outbound;
    }
    final result = Map<String, dynamic>.from(outbound);
    if (result['type']?.toString().toLowerCase() == 'vless' &&
        result['flow'] is String) {
      final flow = normalizeVlessFlow(result['flow'] as String);
      if (flow.isEmpty) {
        result.remove('flow');
      } else {
        result['flow'] = flow;
      }
    }
    return result;
  }

  /// Final safety net for imported/persisted profile data. Some profile paths
  /// keep raw outbound maps and later aggregate them without passing through
  /// the typed outbound model. Walk the generated config so the core never
  /// receives an Xray-only VLESS flow value.
  static dynamic normalizeConfigCompatibility(dynamic value) {
    if (value is List) {
      return value.map(normalizeConfigCompatibility).toList();
    }
    if (value is Map) {
      final result = <dynamic, dynamic>{};
      value.forEach((key, item) {
        result[key] = normalizeConfigCompatibility(item);
      });
      if (result['type']?.toString().toLowerCase() == 'vless' &&
          result['flow'] is String) {
        final flow = normalizeVlessFlow(result['flow'] as String);
        if (flow.isEmpty) {
          result.remove('flow');
        } else {
          result['flow'] = flow;
        }
      }
      // A share link that omits `host=` must send the SNI as the WebSocket Host.
      // That is what v2rayN/Xray do, and Cloudflare routes by Host, so without it
      // the upgrade is answered 403 and the node never connects.
      //
      // Done here as well as at parse time because this is the safety net for
      // already-persisted data: a node imported before that default existed keeps
      // its old raw forever, and re-importing a whole subscription to repair one
      // node is not something to ask of anyone.
      final transport = result['transport'];
      if (transport is Map && transport['type'] == 'ws') {
        final tls = result['tls'];
        final sni = tls is Map ? tls['server_name']?.toString() ?? '' : '';
        final headers = transport['headers'];
        if (sni.isNotEmpty && !(headers is Map && headers.containsKey('Host'))) {
          final merged = <dynamic, dynamic>{};
          if (headers is Map) {
            merged.addAll(headers);
          }
          merged['Host'] = sni;
          transport['headers'] = merged;
        }
      }
      return result;
    }
    return value;
  }

  static List<String> _selectorOutbounds(ProxyConfig server) {
    try {
      if (server.raw.isEmpty) {
        return [];
      }
      final outbounds = server.raw['outbounds'];
      if (outbounds is List) {
        return List<String>.from(outbounds);
      }
    } catch (_) {}
    return [];
  }

  static Map<String, dynamic>? _outboundFromUrl(ProxyConfig server) {
    if (server.url.isEmpty) {
      return null;
    }
    final link = server.url;
    if (link.startsWith('vmess://')) {
      return _outboundFromVmess(link, server.tag);
    }
    final options = SingboxOutboundOptions();
    final uri = Uri.tryParse(link);
    if (uri == null) {
      return null;
    }
    final q = uri.queryParameters;
    final tls = _tlsFromUrlParams(q);
    switch (uri.scheme.toLowerCase()) {
      case 'vless':
        {
          options.type = SingboxOutboundType.vless;
          final vless = SingboxOutboundVLESSOptions();
          vless.uuid = uri.userInfo;
           vless.flow = normalizeVlessFlow(q['flow']);
          options.vless = vless;
          break;
        }
      case 'trojan':
        {
          options.type = SingboxOutboundType.trojan;
          final trojan = SingboxOutboundTrojanOptions();
          trojan.password = uri.userInfo;
          options.trojan = trojan;
          break;
        }
      case 'ss':
        {
          options.type = SingboxOutboundType.shadowsocks;
          final ss = SingboxOutboundShadowsocksOptions();
          try {
            final userInfo = utf8.decode(base64Decode(uri.userInfo));
            final idx = userInfo.indexOf(':');
            ss.method = userInfo.substring(0, idx);
            ss.password = userInfo.substring(idx + 1);
          } catch (_) {
            final idx = uri.userInfo.indexOf(':');
            if (idx > 0) {
              ss.method = uri.userInfo.substring(0, idx);
              ss.password = uri.userInfo.substring(idx + 1);
            }
          }
          options.shadowsocks = ss;
          break;
        }
      case 'hysteria2':
      case 'hy2':
        {
          options.type = SingboxOutboundType.hysteria2;
          final hy2 = SingboxOutboundHysteria2Options();
          hy2.password = uri.userInfo;
          if ((q['obfs-password'] ?? '').isNotEmpty) {
            hy2.obfs_password = q['obfs-password'];
          }
          options.hysteria2 = hy2;
          break;
        }
      case 'tuic':
        {
          options.type = SingboxOutboundType.tuic;
          final tuic = SingboxOutboundTUICOptions();
          final idx = uri.userInfo.indexOf(':');
          if (idx > 0) {
            tuic.uuid = uri.userInfo.substring(0, idx);
            tuic.password = uri.userInfo.substring(idx + 1);
          }
          if ((q['congestion_control'] ?? '').isNotEmpty) {
            tuic.congestion_control = q['congestion_control'];
          }
          options.tuic = tuic;
          break;
        }
      default:
        return null;
    }
    options.tag = server.tag;
    options.server = uri.host;
    options.serverPort = uri.port == 0 ? 443 : uri.port;
    options.tls = tls;
    // v2rayN-family shares: headerType=http on tcp transport = http obfs,
    // which sing-box models as a `http` transport.
    var transportType = q['type'] ?? 'tcp';
    if (transportType == 'tcp' && q['headerType'] == 'http') {
      transportType = 'http';
    }
    if (transportType == 'h2') {
      transportType = 'http';
    }
    if (transportType != 'tcp' && transportType.isNotEmpty) {
      final tr = SingboxOutboundTransportOptions();
      tr.type = transportType;
      tr.path = q['path'] ?? "";
      if (transportType == 'httpupgrade' || transportType == 'http') {
        tr.host = q['host'] ?? "";
      } else if ((q['host'] ?? '').isNotEmpty) {
        tr.headers = {'Host': q['host']!};
      }
      if ((q['serviceName'] ?? '').isNotEmpty) {
        tr.serviceName = q['serviceName']!;
      }
      if ((q['eh'] ?? '').isNotEmpty) {
        tr.earlyDataHeaderName = q['eh']!;
      }
      final ed = int.tryParse(q['ed'] ?? '') ??
          _edFromPath(tr.path); // "?ed=2048" often rides in the ws path
      if (ed != null && ed > 0) {
        tr.maxEarlyData = ed;
        if (tr.earlyDataHeaderName.isEmpty) {
          tr.earlyDataHeaderName = 'Sec-WebSocket-Protocol';
        }
        tr.path = tr.path.replaceAll(RegExp(r'[?&]ed=\d+'), '');
      }
      options.transport = tr;
    }
    return options.toJson();
  }

  static int? _edFromPath(String path) {
    final m = RegExp(r'[?&]ed=(\d+)').firstMatch(path);
    if (m == null) {
      return null;
    }
    return int.tryParse(m.group(1)!);
  }

  static SingboxOutboundTLSOptions _tlsFromUrlParams(Map<String, String> q) {
    final security = (q['security'] ?? 'none').toLowerCase();
    final tls = SingboxOutboundTLSOptions();
    if (security != 'tls' && security != 'reality') {
      return tls;
    }
    tls.enabled = true;
    tls.serverName = q['sni'] ?? q['peer'] ?? "";
    tls.insecure = (q['allowInsecure'] ?? q['insecure'] ?? q['allow_insecure'] ?? '0') == '1';
    if ((q['alpn'] ?? '').isNotEmpty) {
      tls.alpn = q['alpn']!
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if ((q['fp'] ?? '').isNotEmpty) {
      tls.utls = SingboxOutboundUTLSOptions()
        ..enabled = true
        ..fingerprint = q['fp'] == 'unsafe' ? 'chrome' : q['fp']!;
    }
    if ((q['cs'] ?? '').isNotEmpty) {
      tls.cipherSuites =
          q['cs']!.split(':').where((c) => c.isNotEmpty).toList();
    }
    if (security == 'reality') {
      tls.reality = SingboxOutboundRealityOptions()
        ..enabled = true
        ..publicKey = q['pbk'] ?? ""
        ..shortId = q['sid'] ?? "";
    }
    // PattN/karing share links carry per-node TLS fragmentation tuning in `fm=`
    // (a finalmask JSON). The clash-side parser reads it (auto_conf_utils), but
    // this one did not — so a node lost the lengths its own publisher tuned and
    // was handed the generic preset instead. That is what made Cloudflare
    // Workers nodes, which all ship `fm=`, fail every delay test.
    final fm = q['fm'] ?? '';
    if (fm.isNotEmpty) {
      try {
        final decoded = jsonDecode(
          fm.contains('%') ? Uri.decodeComponent(fm) : fm,
        );
        if (decoded is Map &&
            decoded['tcp'] is List &&
            (decoded['tcp'] as List).isNotEmpty) {
          final settings = (decoded['tcp'] as List).first['settings'];
          if (settings is Map) {
            if (settings['lengths'] is List) {
              tls.fragmentSizes = List<String>.from(
                settings['lengths'].map((e) => e.toString()),
              );
            }
            if (settings['delays'] is List) {
              tls.fragmentDelays = List<String>.from(
                settings['delays'].map((e) => e.toString()),
              );
            }
          }
        }
      } catch (_) {}
    }
    final tlsSetting = SettingManager.getConfig().tls;
    final isIr = SettingManager.getConfig().iranMode;
    tls.fragment = tlsSetting.enableFragment || isIr;
    tls.recordFragment = tls.fragment;
    tls.insecure = tls.insecure || tlsSetting.enableInsecure;
    if (tls.fragment) {
      if (isIr) {
        // Patt's preset (t.me/patt_channel_x/91) is a FALLBACK here, not an
        // override. A share that carries its own `fm=` fragment lengths, or its
        // own cipher list, already knows what works against its own edge —
        // Cloudflare Workers links ship exactly that, and overwriting it is
        // what made every one of them fail its delay test.
        if (tls.fragmentSizes.isEmpty) {
          tls.fragmentSizes = SettingConfigItemTLS.kFragmentSizesPatt;
          tls.fragmentDelays = SettingConfigItemTLS.kFragmentDelaysPatt;
          tls.fragmentMaxSplit = SettingConfigItemTLS.kFragmentMaxSplitPatt;
        }
        if (tls.cipherSuites.isEmpty) {
          tls.cipherSuites =
              SettingConfigItemTLS.kCipherSuitesPatt.split(':').toList();
        }
        tls.utls ??= (SingboxOutboundUTLSOptions()
          ..enabled = true
          ..fingerprint = 'chrome');
      } else {
        tls.fragmentSizes = tlsSetting.fragmentSize
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        tls.fragmentDelays = tlsSetting.fragmentSleep
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return tls;
  }

  static Map<String, dynamic>? _outboundFromVmess(String link, String tag) {
    final b64 = link.substring('vmess://'.length).replaceAll(RegExp(r'\s'), '');
    try {
      final json = jsonDecode(utf8.decode(base64.decode(base64.normalize(b64))));
      if (json is! Map) {
        return null;
      }
      final options = SingboxOutboundOptions();
      options.type = SingboxOutboundType.vmess;
      final vmess = SingboxOutboundVMessOptions();
      vmess.uuid = (json['id'] ?? "").toString();
      vmess.security =
          ((json['scy'] ?? json['security']) ?? 'auto').toString();
      vmess.alter_id =
          int.tryParse((json['aid'] ?? '0').toString()) ?? 0;
      options.vmess = vmess;
      options.tag = tag;
      options.server = (json['add'] ?? "").toString();
      options.serverPort =
          int.tryParse((json['port'] ?? '0').toString()) ?? 0;
      final tlsEnabled = (json['tls'] ?? '').toString() == 'tls';
      if (tlsEnabled) {
        final tls = SingboxOutboundTLSOptions();
        tls.enabled = true;
        tls.serverName = (json['sni'] ?? "").toString();
        tls.insecure = (json['insecure'] ?? '0').toString() == '1';
        final tlsSetting = SettingManager.getConfig().tls;
        tls.fragment = tlsSetting.enableFragment;
        tls.recordFragment = tlsSetting.enableFragment;
        tls.insecure = tls.insecure || tlsSetting.enableInsecure;
        final alpn = (json['alpn'] ?? "").toString();
        if (alpn.isNotEmpty) {
          tls.alpn = alpn
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        final fp = (json['fp'] ?? "").toString();
        if (fp.isNotEmpty) {
          tls.utls = SingboxOutboundUTLSOptions()
            ..enabled = true
            ..fingerprint = fp == 'unsafe' ? 'chrome' : fp;
        }
        options.tls = tls;
      }
      final net = (json['net'] ?? '').toString();
      final vhost = (json['host'] ?? "").toString();
      final vpath = (json['path'] ?? "").toString();
      if (net == 'ws') {
        final tr = SingboxOutboundTransportOptions();
        tr.type = 'ws';
        tr.path = vpath;
        if (vhost.isNotEmpty) {
          tr.headers = {'Host': vhost};
        }
        options.transport = tr;
      } else if (net == 'grpc') {
        // vmess link shares carry the grpc service name in `path`
        if (vpath.isNotEmpty) {
          final tr = SingboxOutboundTransportOptions();
          tr.type = 'grpc';
          tr.serviceName = vpath;
          options.transport = tr;
        }
      } else if (net == 'httpupgrade') {
        final tr = SingboxOutboundTransportOptions();
        tr.type = 'httpupgrade';
        tr.path = vpath;
        tr.host = vhost;
        options.transport = tr;
      } else if (net == 'h2' || net == 'tcp') {
        if (json['type'].toString() == 'http' || net == 'h2') {
          final tr = SingboxOutboundTransportOptions();
          tr.type = 'http';
          tr.path = vpath;
          tr.host = vhost;
          options.transport = tr;
        }
      }
      return options.toJson();
    } catch (_) {
      return null;
    }
  }

  static ReturnResult<dynamic> dns(
      bool tunMode, SingboxExportType type, List<String>? rulesetUrls) {
    final setting = SettingManager.getConfig();
    final regionCode = setting.regionCode;
    final resolveMode = setting.dns.proxyResolveMode;
    // The consolidated Resolve Channel dropdown and the three per-purpose
    // switches that predate it are additive: either one can turn a behaviour
    // on and neither can turn it off, so the two controls can never end up
    // contradicting each other.
    final fakeIp = resolveMode == SettingConfigItemDNSProxyResolveMode.fakeip ||
        setting.dns.enableFakeIp;
    final resolveByProxy =
        resolveMode == SettingConfigItemDNSProxyResolveMode.proxy ||
            setting.dns.enableProxyResolveByProxy;

    final servers = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];
    final dnsRuleSets = <Map<String, dynamic>>[];

    final resolverDns = setting.dns.getResolverDns(regionCode, tunMode);
    final remoteDns = fakeIp
        ? setting.dns.getProxyDns(regionCode, tunMode)
        : setting.dns.getOutboundDns(regionCode, tunMode);
    final directDns = setting.dns.getDirectDns(regionCode, tunMode);

    // Resolving through the connected profile is supposed to mean the query
    // actually leaves at the exit; only picking a different resolver still
    // sends it out on the local network. Detour the remote servers so it is
    // resolved at the exit. Skipped in serverless mode, where the selector
    // has no real node behind it.
    // `enableFinalResolveByProxy` needs a detoured resolver available even
    // when the dropdown is not on `proxy`, otherwise "final through the
    // proxy" has nothing to point at.
    final remoteDetour =
        (resolveByProxy || setting.dns.enableFinalResolveByProxy) &&
                !setting.tls.enableServerless
            ? kOutboundTagProxy
            : null;

    int index = 1;
    final remoteServerTags = <String>[];
    for (final url in remoteDns) {
      final tag = "dns-remote-${index++}";
      remoteServerTags.add(tag);
      servers.add(_dnsServerFromUrl(tag, url, null, detour: remoteDetour));
    }
    final directServerTags = <String>[];
    for (final url in directDns) {
      final tag = "dns-direct-${index++}";
      directServerTags.add(tag);
      servers.add(_dnsServerFromUrl(tag, url, null));
    }
    for (final url in resolverDns) {
      final tag = "dns-resolver-${index++}";
      servers.add(
        _dnsServerFromUrl(
          tag,
          url,
          directServerTags.isNotEmpty ? directServerTags.first : null,
        ),
      );
    }

    // sing-box 1.12+: every server whose address is a domain needs an
    // explicit bootstrap resolver; pick an IP-addressed one (udp with a
    // literal IP) so initialization cannot recurse.
    String? ipBootstrap;
    for (final s in servers) {
      if (s is Map &&
          s['type'] == 'udp' &&
          s['server'] is String &&
          InternetAddress.tryParse(s['server'] as String) != null) {
        ipBootstrap = s['tag'] as String;
        break;
      }
    }
    if (ipBootstrap == null && directServerTags.isNotEmpty) {
      ipBootstrap = directServerTags.first;
    }
    if (ipBootstrap != null) {
      for (final s in servers) {
        if (s is Map && s['domain_resolver'] == null) {
          final serverAddr = (s['server'] ?? "").toString();
          final isDomain =
              serverAddr.isNotEmpty && InternetAddress.tryParse(serverAddr) == null;
          final needsResolver = (s['type'] == 'https' ||
                  s['type'] == 'tls' ||
                  s['type'] == 'quic' ||
                  s['type'] == 'dhcp') &&
              isDomain;
          if (needsResolver) {
            s['domain_resolver'] = ipBootstrap;
          }
        }
      }
    }

    // There used to be an `{'outbound': 'any', 'server': <direct>}` rule here.
    // sing-box 1.12 deprecated outbound DNS rule items and removes them in
    // 1.14; the same resolver is published as `route.default_domain_resolver`
    // instead, which route() picks with the identical preference.
    if (directServerTags.isNotEmpty) {
      dnsRuleSets.add(_buildInRuleSet("geosite", "ir"));
      rules.add({
        'rule_set': 'geosite-ir',
        'server': directServerTags.first,
      });
    }
    rules.add({
      'query_type': [
        64, 65, // https and svcb
      ],
      'server': directServerTags.isNotEmpty ? directServerTags.first : remoteServerTags.first,
    });

    final strategy = setting.ipStrategy.name;

    dynamic final_;
    if (fakeIp) {
      servers.add({
        'tag': 'dns-fakeip',
        'type': 'fakeip',
        'inet4_range': '198.18.0.0/15',
        'inet6_range': 'fc00::/18',
      });
      rules.add({
        'inbound': ['tun-in'],
        'server': 'dns-fakeip',
      });
      final_ = remoteServerTags.first;
    } else if (resolveByProxy) {
      rules.add({
        'inbound': ['tun-in'],
        'server': remoteServerTags.first,
      });
      final_ = remoteServerTags.first;
    } else if (setting.dns.enableFinalResolveByProxy &&
        remoteDetour != null &&
        remoteServerTags.isNotEmpty) {
      // "Resolve the final through the proxy" in its own right: the fallback
      // resolver has to be a detoured one, so reuse the remote list instead
      // of the direct one.
      final_ = remoteServerTags.first;
    } else {
      final_ = directServerTags.isNotEmpty ? directServerTags.first : remoteServerTags.first;
    }

    final dns = <String, dynamic>{
      'servers': servers,
      'rules': rules,
      'final': final_,
      'strategy': strategy,
      'independent_cache': true,
    };

    return ReturnResult(data: dns);
  }

  /// [detour] routes this server's queries through an outbound instead of
  /// dialling them directly. This is what makes "resolve via the connected
  /// profile" actually happen — without it, `proxyResolveMode: proxy` only
  /// picks a different resolver but still sends the query out on the local
  /// network, where it can be poisoned.
  static Map<String, dynamic> _dnsServerFromUrl(
      String tag, String url, String? addressResolver, {String? detour}) {
    String address = url;
    String type = "udp";
    String server = url;
    final schemeMatch =
        RegExp(r'^(udp|tcp|tls|https|h3|quic|dhcp|rcode|fakeip)://').firstMatch(url);
    if (schemeMatch != null) {
      type = schemeMatch.group(1)!;
      server = url.substring(schemeMatch.end);
    } else if (url.startsWith('local')) {
      type = 'local';
      server = "";
    }
    final out = <String, dynamic>{'tag': tag};
    if (type == 'dhcp') {
      out['type'] = 'dhcp';
    } else if (type == 'local') {
      out['type'] = 'local';
    } else if (type == 'fakeip' || type == 'rcode') {
      out['type'] = 'fakeip';
    } else {
      // udp / tcp / tls / https / h3 / quic all take server + server_port;
      // only https/h3 additionally take `path`
      out['type'] = type;
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        out['server'] = uri.host;
        if (uri.hasPort && uri.port != 0) {
          out['server_port'] = uri.port;
        }
        if ((type == 'https' || type == 'h3') &&
            uri.path.isNotEmpty &&
            uri.path != '/') {
          out['path'] = uri.path;
        }
      } else {
        out['server'] = server;
      }
    }
    if (addressResolver != null && addressResolver.isNotEmpty) {
      out['domain_resolver'] = addressResolver;
    }
    if (detour != null && detour.isNotEmpty) {
      out['detour'] = detour;
    }
    return out;
  }

  static List<dynamic> inbounds(bool includeTun, SingboxExportType type) {
    final setting = SettingManager.getConfig();
    final inbounds = <dynamic>[];
    if (includeTun) {
      final tun = SingboxInboundTunOptions();
      tun.stack = setting.tun.stack;
      tun.mtu = setting.tun.mtu;
      tun.autoRoute = setting.tun.autoRoute;
      tun.strictRoute = setting.tun.strictRoute;
      tun.address = [setting.tun.ipv4Address, setting.tun.ipv6Address];
      inbounds.add(tun);
    }
    final mixed = SingboxInboundMixedOptions();
    mixed.listen = setting.proxy.host;
    mixed.listenPort = setting.proxy.mixedRulePort;
    inbounds.add(mixed);
    final forward = SingboxInboundMixedOptions();
    forward.tag = "mixed-forward-in";
    forward.listen = setting.proxy.host;
    forward.listenPort = setting.proxy.mixedForwardPort;
    inbounds.add(forward);
    // Loopback-only inbound reserved for latency scanners: while the VPN is
    // up, scanner sockets dial it and get routed straight to the direct
    // outbound (physical NIC), so measurements are never taken through the
    // tunnel. Unreachable/unused while the VPN is off.
    final scan = SingboxInboundMixedOptions();
    scan.tag = "scan-in";
    scan.listen = SingboxInboundMixedOptions.hostLocal;
    scan.listenPort = setting.proxy.scanPort;
    inbounds.add(scan);
    return inbounds;
  }

  /// Tags that are structural (groups) and must never appear as group members.
  static const List<String> kGroupTags = [
    kOutboundTagProxy,
    kOutboundTagAutoSelect,
    kOutboundTagUrltest,
    kOutboundTagDirect,
    kOutboundTagBlock,
    kOutboundTagDns,
  ];

  /// Serverless mode (patterniha/Serverless-for-Iran) outbound tags. The
  /// outbounds are emitted by outbounds() and referenced by the rules and
  /// `final` of route() - both sides must agree on these tags.
  static const kServerlessTcpFragment = 'tcp-fragment';
  static const kServerlessTcpFragmentTls = 'tcp-fragment-tls';
  static const kServerlessUdpNoises = 'udp-noises';

  /// Networks v50 refuses to reach: DPI probe/honeypot ranges whose replies
  /// burn the client's IP into the blocklist of every other visitor.
  static const List<String> kServerlessBlockedCidrs = [
    '10.10.34.0/24',
    '2001:4188:2:600::/64',
  ];

  /// Direct outbounds carrying the fragment/noise masks (`finalmask` is a
  /// Karing sing-box extension, verified with `sing-box check`). The values
  /// are patterniha/Serverless-for-Iran v50, `Serverless-fragA.jsonc`.
  ///
  /// v50 masks the ClientHello twice - 6/98/1 byte pieces at 0 ms, then every
  /// following packet as 114/1 byte pieces at 1 ms. One direct outbound
  /// carries one mask in the patched core (a `packets` value containing "tls"
  /// stops after the hello), so only the SNI-critical stage stays here;
  /// fragB is the same mask with `0` in place of the first `6`.
  ///
  /// v50 routes nothing through tcp-fragment/udp-noises - both stay emitted
  /// but unreferenced, like upstream keeps them, as the aggressive variants:
  /// point the corresponding rule in route() at them to try one. The core
  /// splits at most 512 chunks per write, which the 1-byte length list of
  /// tcp-fragment outruns on writes bigger than that.
  static List<dynamic> serverlessOutbounds() {
    return [
      {
        'type': 'direct',
        'tag': kServerlessTcpFragmentTls,
        'finalmask': {
          'tcp_split': true,
          'packets': 'tlshello',
          'lengths': ["6", "98", "1"],
          'delays': ["0"],
          // v50's maxSplit 0; the core counts whole writes before it stops
          // fragmenting, and a tls mask stops at the hello either way.
          'max_split': 0,
        },
      },
      {
        'type': 'direct',
        'tag': kServerlessTcpFragment,
        'finalmask': {
          'tcp_split': true,
          'packets': '1-1',
          'lengths': ["1"],
          'delays': ["1"],
          'max_split': 201,
        },
      },
      {
        'type': 'direct',
        'tag': kServerlessUdpNoises,
        'finalmask': {
          'udp_noise': true,
          // v50 lists the same {rand: 1200-1230, delay: 10} noise 24 times
          'noise_rand': '1200-1230',
          'noise_delay': '10',
          'noise_reset': 28,
          'noise_count': 24,
        },
      },
    ];
  }

  static List<dynamic> outbounds(
      String unknownGroupTag,
      Set<String> allOutboundsTags,
      Map<String, String> replaceTags,
      dynamic selectOutbound,
      List<dynamic> allOutBounds,
      String? currentTag,
      Map<String, dynamic> urltests,
      SingboxExportType type) {
    final outbounds = <dynamic>[];
    final tags = <String>[];
    final seenTags = <String>{};
    for (final ob in allOutBounds) {
      if (ob is Map && ob['tag'] != null) {
        final tag = ob['tag'].toString();
        if (kGroupTags.contains(tag)) {
          continue;
        }
        if (allOutboundsTags.contains(tag) && seenTags.add(tag)) {
          outbounds.add(ob);
          tags.add(tag);
        }
      }
    }
    // selector / urltest groups are prepended by the caller via specialOutbound
    if (tags.isEmpty) {
      // sing-box refuses a selector/urltest without members
      // ("initialize outbound[0]: missing tags"), which happens in serverless
      // mode or with an empty profile.
      tags.add(kOutboundTagDirect);
    }
    // A selector with no `default` uses its FIRST member, and the first member
    // is AutoSelect — a URLTest group that re-picks the fastest node on its own.
    // That silently overrode the node chosen in the server list: `selectOutbound`
    // is the current selection, and it was passed in only to be ignored, so
    // every connection went through AutoSelect and the exit node changed
    // country by itself.
    final selectedTag =
        selectOutbound is Map ? selectOutbound['tag']?.toString() : null;
    // The URLTest group is re-tagged to AutoSelect just below, so selecting the
    // group itself has to be translated rather than copied.
    final selectorDefault =
        (selectedTag != null &&
            selectedTag != kOutboundTagUrltest &&
            tags.contains(selectedTag))
        ? selectedTag
        : kOutboundTagAutoSelect;
    // `interrupt_exist_connections: false` on both groups: switching node must
    // not tear down connections that are already running. AI assistants answer
    // over long-lived streaming connections, so interrupting on every switch is
    // what made them drop mid-answer and report a retry. With this off, a switch
    // only affects connections opened afterwards. The cost is that connections
    // to a node that has since died linger until they time out instead of being
    // cut immediately.
    final selector = <String, dynamic>{
      'type': 'selector',
      'tag': kOutboundTagProxy,
      'outbounds': [kOutboundTagAutoSelect, ...tags],
      'default': selectorDefault,
      'interrupt_exist_connections': false,
    };
    final urltest = <String, dynamic>{
      'type': 'urltest',
      'tag': kOutboundTagAutoSelect,
      'outbounds': tags,
      'tolerance': 50,
      'interrupt_exist_connections': false,
    };
    // `block` and `dns` are deliberately absent: sing-box 1.11 deprecated both
    // special outbounds in favour of the `reject` and `hijack-dns` rule
    // actions, and removes them in 1.13. Every use of them was a route-rule
    // target, so they migrate cleanly to actions. `direct` is an ordinary
    // outbound and stays.
    final tail = <Map<String, dynamic>>[
      {'type': 'direct', 'tag': kOutboundTagDirect},
    ];
    final tailTags = tail.map((e) => e['tag'] as String).toSet();
    outbounds.removeWhere((ob) => tailTags.contains(ob['tag']));
    final result = [
      selector,
      urltest,
      ...outbounds,
      ...tail,
    ];
    // Serverless mode (patterniha/Serverless-for-Iran): route() points `final`
    // and its fragment/noise rules at these, so they have to be emitted with
    // the rest of the outbounds instead of being appended to the (already
    // consumed) inbound list from route().
    if (SettingManager.getConfig().tls.enableServerless) {
      result.addAll(serverlessOutbounds());
    }
    _applyPattFragment(result, type);
    _applySniSpoofing(result);
    return result;
  }

  /// SNI-Spoofing (patterniha/SNI-Spoofing): for CDN-backed TLS outbounds
  /// (ws/grpc/httpupgrade transport), dial a clean Cloudflare IP instead of
  /// the configured address, present a whitelisted fake SNI, and keep the
  /// real domain in the Host header so the CDN still routes to the worker.
  static int _sniSpoofingIpIndex = 0;

  static void _applySniSpoofing(List<dynamic> outbounds) {
    final tlsSetting = SettingManager.getConfig().tls;
    if (!tlsSetting.enableSniSpoofing ||
        tlsSetting.sniSpoofingIps.isEmpty ||
        tlsSetting.sniSpoofingFakeSni.isEmpty) {
      return;
    }
    for (final ob in outbounds) {
      if (ob is! Map || ob['tls'] is! Map) {
        continue;
      }
      final tls = ob['tls'] as Map<String, dynamic>;
      if (tls['enabled'] != true || tls['reality'] != null) {
        continue;
      }
      // only CDN-backed transports: the Host header must carry the real
      // domain for routing — a bare tcp+tls node has no Host to preserve
      if (ob['transport'] is! Map) {
        continue;
      }
      final server = ob['server']?.toString() ?? "";
      if (server.isEmpty) {
        continue;
      }
      // rotate through the clean IPs — Patt: "put a healthy CF IP in the
      // address field", regardless of what the link carried
      final ip = tlsSetting
          .sniSpoofingIps[_sniSpoofingIpIndex++ % tlsSetting.sniSpoofingIps.length];
      ob['server'] = ip;
      tls['server_name'] = tlsSetting.sniSpoofingFakeSni;
      // the presented cert can never match the fake SNI — skip verification
      // (this is inherent to the method; PattNG does the same)
      tls['insecure'] = true;
      // ensure the real domain survives in the transport Host header.
      // NOTE: ws transport has no `host` field (sing-box 1.11+ rejects it
      // with "unknown field"), so always use `headers.Host` there.
      final tr = ob['transport'];
      if (tr is Map) {
        final type = tr['type']?.toString() ?? '';
        final headers = tr['headers'];
        if (headers is Map) {
          if (!headers.values.any(
              (v) => v.toString().toLowerCase() == server.toLowerCase())) {
            headers['Host'] = server;
          }
        } else if (type == 'ws') {
          tr['headers'] = {'Host': server};
        } else if (type == 'http' || type == 'httpupgrade') {
          if (tr['host'] == null || tr['host'].toString().isEmpty) {
            tr['host'] = server;
          }
        } else {
          // ws/grpc have no `host` field in sing-box 1.11+ — keep the
          // domain in the Host header instead.
          tr['headers'] = {'Host': server};
        }
      }
    }
  }

  /// Patt's fragment+fingerprint method (t.me/patt_channel_x/91): apply the
  /// two-stage fragment masks + cipher suites + unsafe fingerprint to every
  /// TLS-bearing outbound when Iran mode is on.
  static void _applyPattFragment(List<dynamic> outbounds, SingboxExportType type) {
    if (!SettingManager.getConfig().iranMode) {
      return;
    }
    for (final ob in outbounds) {
      if (ob is! Map || ob['tls'] is! Map) {
        continue;
      }
      final tls = ob['tls'] as Map<String, dynamic>;
      tls['fragment'] = true;
      tls['record_fragment'] = true;
      // Fill the gaps only. A config that ships its own fragment tuning keeps
      // it — replacing it with the preset is what broke every Cloudflare
      // Workers node, whose own `fm=` lengths are tuned for its edge.
      tls['fragment_sizes'] ??= SettingConfigItemTLS.kFragmentSizesPatt;
      tls['fragment_delays'] ??= SettingConfigItemTLS.kFragmentDelaysPatt;
      tls['fragment_max_split'] ??= SettingConfigItemTLS.kFragmentMaxSplitPatt;
      tls['cipher_suites'] ??= SettingConfigItemTLS.kCipherSuitesPatt.split(':');
      tls['utls'] ??= {
        'enabled': true,
        'fingerprint': 'chrome',
      };
      if (kDiagnosticLogging) {
        // Records what each node actually went out with. `sizes` is the
        // discriminator: the generic Patt preset means the node's own `fm=`
        // was never seen, which is the failure this was added to chase.
        Log.w(
          "tlsTuning type=$type tag=${ob['tag']} server=${ob['server']} "
          "sni=${tls['server_name']} sizes=${tls['fragment_sizes']}",
        );
      }
    }
  }

  static dynamic route(
      String regionCode,
      String geoSiteUrl,
      String geoIpUrl,
      String aclUrl,
      List<int> sitecodesHashCode,
      List<int> ipcodesHashCode,
      List<int> aclcodesHashCode,
      bool tunMode,
      List<dynamic> allOutBounds,
      Map<String, dynamic> urltests,
      String? blockDomainSetUrl,
      List<Tuple3<DiversionRulesGroup, ProxyConfig, List<String>>> diversionGroups,
      List<dynamic> inbounds,
      dynamic dns,
      String? customOutboundTag,
      List<String>? chainProxy,
      String groupid,
      SingboxExportType type) {
    final setting = SettingManager.getConfig();
    final rules = <dynamic>[];
    final ruleSets = <dynamic>[];

    // Scanner channel: everything arriving on the loopback scan inbound goes
    // straight out the direct outbound so probes measure the physical path,
    // not the tunnel. Must be the first rule so nothing diverts it.
    rules.add({
      'inbound': ['scan-in'],
      'outbound': kOutboundTagDirect,
    });

    // Sniff before any domain-based rule. In sing-box 1.11+ the inbound `sniff`
    // field is gone; the `sniff` action is the only way, and without it the
    // domain rules below can never match on a TUN inbound.
    //
    // This is what made Iran routing look broken under TUN. Through the mixed
    // port the client sends the hostname in the request, so `geosite-ir` matches
    // on the domain. TUN delivers raw IP packets — no hostname anywhere — so only
    // `geoip-ir` could match, and the moment DNS answered with a foreign address
    // (which "resolve through proxy" does for anything outside geosite-ir) the
    // traffic had nothing left to route it direct. Sniffing recovers the SNI.
    //
    // `sniff` is not a final action, so matching continues with the next rule.
    if (tunMode || setting.tls.enableServerless) {
      rules.add({
        'action': 'sniff',
        'sniffer': ['tls', 'http', 'quic'],
      });
    }

    // hijack dns — `hijack-dns` rule action replaces the legacy `dns` outbound
    // (sing-box 1.11; the outbound is removed in 1.13).
    if (tunMode || setting.tun.hijackDns) {
      rules.add({
        'inbound': ['tun-in'],
        'protocol': 'dns',
        'action': 'hijack-dns',
      });
    }
    rules.add({
      'protocol': 'dns',
      'action': 'hijack-dns',
    });

    // Iran mode: domestic traffic direct, Iranian ads blocked. Runs before
    // user diversion groups so users can override per rule.
    if (setting.iranMode) {
      ruleSets.add(_buildInRuleSet("geosite", "category-ads-ir"));
      ruleSets.add(_buildInRuleSet("geoip", "ir"));
      ruleSets.add(_buildInRuleSet("geosite", "ir"));
      rules.add({
        'rule_set': [_ruleSetTag("category-ads-ir", "geosite")],
        'action': 'reject',
      });
      rules.add({
        'rule_set': [
          _ruleSetTag("ir", "geosite"),
          _ruleSetTag("ir", "geoip"),
        ],
        'outbound': kOutboundTagDirect,
      });
    }

    // diversion groups
    for (final tuple in diversionGroups) {
      final rule = tuple.item1;
      {
        if (!rule.switch_) {
          continue;
        }
        final r = <String, dynamic>{};
        if (rule.ruleSetBuildIn.isNotEmpty) {
          final rs = <String>[];
          for (final code in rule.ruleSetBuildIn) {
            if (code.startsWith('geosite:')) {
              rs.add(_ruleSetTag(code.substring(8), "geosite"));
              ruleSets.add(_buildInRuleSet("geosite", code.substring(8)));
            } else if (code.startsWith('geoip:')) {
              rs.add(_ruleSetTag(code.substring(6), "geoip"));
              ruleSets.add(_buildInRuleSet("geoip", code.substring(6)));
            } else if (code.startsWith('acl:')) {
              rs.add(_ruleSetTag(code.substring(4), "acl"));
              ruleSets.add(_buildInRuleSet("acl", code.substring(4)));
            }
          }
          if (rs.isNotEmpty) r['rule_set'] = rs;
        }
        if (rule.domain.isNotEmpty) {
          r['domain_suffix'] = rule.domain;
        }
        if (rule.domainKeyword.isNotEmpty) {
          r['domain_keyword'] = rule.domainKeyword;
        }
        if (rule.ipCidr.isNotEmpty) {
          r['ip_cidr'] = rule.ipCidr;
        }
        if (rule.portRange.isNotEmpty) {
          r['port_range'] = rule.portRange;
        }
        if (rule.package.isNotEmpty) {
          r['package_name'] = rule.package;
        }
        if (rule.processName.isNotEmpty) {
          r['process_name'] = rule.processName;
        }
        switch (rule.outbound) {
          case 'direct':
            r['outbound'] = kOutboundTagDirect;
            break;
          case 'block':
            // A diversion rule that blocks becomes a `reject` action rather
            // than pointing at the legacy `block` outbound.
            r['action'] = 'reject';
            break;
          default:
            r['outbound'] = rule.outbound;
        }
        if (r.isNotEmpty &&
            (r.containsKey('outbound') || r.containsKey('action'))) {
          rules.add(r);
        }
      }
    }

    final route = <String, dynamic>{
      'rules': rules,
      'rule_set': ruleSets,
      'final': kOutboundTagProxy,
      'auto_detect_interface': true,
    };
    // Serverless mode (patterniha/Serverless-for-Iran v50): the ClientHello of
    // every TLS flow is fragmented on its way out, QUIC and UDP/443 are killed
    // so browsers fall back to TCP-443, the DPI honeypot ranges are refused,
    // and everything else leaves through the plain direct outbound. The mask
    // carriers come from serverlessOutbounds().
    //
    // These rules are appended after the diversion/user rules, so an Iranian
    // or LAN destination picked up by the region preset stays direct and
    // unmasked - the same split v50 makes with its ir/private tcp-direct rules.
    if (setting.tls.enableServerless) {
      // v50 sniffs the first packet of every flow (Xray does it on the
      // inbound); without it the protocol rules below never match. The sniff
      // action itself is added near the top of this list, so the domain rules
      // see it too — see the comment there.
      rules.add({
        'ip_cidr': kServerlessBlockedCidrs,
        'action': 'reject',
      });
      rules.add({
        'protocol': ['quic'],
        'network': 'udp',
        'action': 'reject',
      });
      rules.add({
        'port': [443],
        'network': 'udp',
        'action': 'reject',
      });
      rules.add({
        'protocol': ['tls'],
        'network': 'tcp',
        'outbound': kServerlessTcpFragmentTls,
      });
      rules.add({
        'port': [443],
        'network': 'tcp',
        'outbound': kServerlessTcpFragmentTls,
      });
      // v50's tcp-direct/udp-direct catch-alls, one sing-box `direct` is enough
      route['final'] = kOutboundTagDirect;
    }
    // dedupe rule-set definitions (Iran block + DNS rule + diversion groups
    // can reference the same code)
    final dedupedRuleSets = <Map<String, dynamic>>[];
    final seenRuleSetTags = <String>{};
    for (final rs in ruleSets) {
      if (rs is Map && seenRuleSetTags.add(rs['tag'].toString())) {
        dedupedRuleSets.add(Map<String, dynamic>.from(rs));
      }
    }
    route['rule_set'] = dedupedRuleSets;
    // This resolves the addresses of outbound servers, so it must never be a
    // detoured resolver: a node whose address is a domain would otherwise need
    // the proxy that is still being built. It also takes over the bootstrap
    // role of the removed `{'outbound': 'any'}` DNS rule, which sent those
    // lookups to the direct resolver — so an undetoured *direct* server wins
    // over an undetoured remote one, which only matters in FakeIP and Direct
    // modes where nothing is detoured at all.
    final dnsServers =
        (dns != null && dns['servers'] is List) ? dns['servers'] as List : const [];
    String? firstDirect;
    String? firstUndetoured;
    for (final s in dnsServers) {
      if (s is! Map || s['tag'] == null) continue;
      if (s['detour'] != null && (s['detour'] as String).isNotEmpty) continue;
      final tag = s['tag'].toString();
      firstUndetoured ??= tag;
      if (tag.startsWith('dns-direct-')) {
        firstDirect ??= tag;
      }
    }
    final bootstrapResolver = firstDirect ?? firstUndetoured;
    if (bootstrapResolver != null) {
      route['default_domain_resolver'] = {'server': bootstrapResolver};
    }

    return route;
  }

  static String _ruleSetTag(String code, String kind) {
    return "$kind-$code".replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '_');
  }

  /// Absolute directory where rule-set .srs files are extracted at runtime;
  /// set by VPNService before generating the core config.
  static String ruleSetBaseDir = "";

  static Map<String, dynamic> _buildInRuleSet(String kind, String code) {
    final out = <String, dynamic>{
      'type': 'local',
      'tag': _ruleSetTag(code, kind),
      'format': 'binary',
    };
    if (ruleSetBaseDir.isNotEmpty) {
      out['path'] = '$ruleSetBaseDir/$kind/$code.srs'.replaceAll('\\', '/');
    } else {
      out['path'] = '$kind/$code.srs';
    }
    return out;
  }
}
