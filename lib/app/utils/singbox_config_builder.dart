import 'package:tuple/tuple.dart';
import 'dart:convert';
import 'dart:io';

import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/app_utils.dart';
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
    return {
      'level': 'warn',
      'timestamp': true,
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
          return options.toJson();
        } catch (_) {}
      }
      return _outboundFromUrl(server);
    } else if (server.type == kOutboundTypeUrltest) {
      return {
        'type': 'urltest',
        'tag': server.tag,
        'outbounds': _selectorOutbounds(server),
        'tolerance': 50,
        'interrupt_exist_connections': true,
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
        'interrupt_exist_connections': true,
      };
    } else {
      if (server.raw == null || server.raw.isEmpty) {
        return null;
      }
      return Map<String, dynamic>.from(server.raw);
    }
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
          vless.flow = q['flow'];
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
    final tlsSetting = SettingManager.getConfig().tls;
    final isIr = SettingManager.getConfig().iranMode;
    tls.fragment = tlsSetting.enableFragment || isIr;
    tls.recordFragment = tls.fragment;
    tls.insecure = tls.insecure || tlsSetting.enableInsecure;
    if (tls.fragment) {
      if (isIr) {
        // Patt's exact fragment+fingerprint preset (t.me/patt_channel_x/91)
        tls.fragmentSizes = SettingConfigItemTLS.kFragmentSizesPatt;
        tls.fragmentDelays = SettingConfigItemTLS.kFragmentDelaysPatt;
        tls.fragmentMaxSplit = SettingConfigItemTLS.kFragmentMaxSplitPatt;
        tls.cipherSuites =
            SettingConfigItemTLS.kCipherSuitesPatt.split(':').toList();
        tls.utls ??= (SingboxOutboundUTLSOptions()
          ..enabled = true
          ..fingerprint = 'unsafe' == 'unsafe' ? 'chrome' : 'chrome');
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

    final servers = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];
    final dnsRuleSets = <Map<String, dynamic>>[];

    final resolverDns = setting.dns.getResolverDns(regionCode, tunMode);
    final remoteDns = resolveMode == SettingConfigItemDNSProxyResolveMode.fakeip
        ? setting.dns.getProxyDns(regionCode, tunMode)
        : setting.dns.getOutboundDns(regionCode, tunMode);
    final directDns = setting.dns.getDirectDns(regionCode, tunMode);

    int index = 1;
    final remoteServerTags = <String>[];
    for (final url in remoteDns) {
      final tag = "dns-remote-${index++}";
      remoteServerTags.add(tag);
      servers.add(_dnsServerFromUrl(tag, url, null));
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

    final resolverForBootstrap =
        directServerTags.isNotEmpty ? directServerTags.first : null;
    rules.add({
      'outbound': 'any',
      'server': resolverForBootstrap ?? remoteServerTags.first,
    });
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
    if (resolveMode == SettingConfigItemDNSProxyResolveMode.fakeip) {
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
    } else if (resolveMode == SettingConfigItemDNSProxyResolveMode.proxy) {
      rules.add({
        'inbound': ['tun-in'],
        'server': remoteServerTags.first,
      });
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

  static Map<String, dynamic> _dnsServerFromUrl(
      String tag, String url, String? addressResolver) {
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
    return inbounds;
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
        if (allOutboundsTags.contains(tag) && seenTags.add(tag)) {
          outbounds.add(ob);
          tags.add(tag);
        }
      }
    }
    // selector / urltest groups are prepended by the caller via specialOutbound
    final selector = <String, dynamic>{
      'type': 'selector',
      'tag': kOutboundTagProxy,
      'outbounds': [kOutboundTagAutoSelect, ...tags],
      'interrupt_exist_connections': true,
    };
    final urltest = <String, dynamic>{
      'type': 'urltest',
      'tag': kOutboundTagAutoSelect,
      'outbounds': tags,
      'tolerance': 50,
      'interrupt_exist_connections': true,
    };
    final tail = <Map<String, dynamic>>[
      {'type': 'direct', 'tag': kOutboundTagDirect},
      {'type': 'block', 'tag': kOutboundTagBlock},
      {'type': 'dns', 'tag': kOutboundTagDns},
    ];
    final tailTags = tail.map((e) => e['tag'] as String).toSet();
    outbounds.removeWhere((ob) => tailTags.contains(ob['tag']));
    final result = [
      selector,
      urltest,
      ...outbounds,
      ...tail,
    ];
    _applyPattFragment(result, type);
    return result;
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
      tls['fragment_sizes'] = SettingConfigItemTLS.kFragmentSizesPatt;
      tls['fragment_delays'] = SettingConfigItemTLS.kFragmentDelaysPatt;
      tls['fragment_max_split'] = SettingConfigItemTLS.kFragmentMaxSplitPatt;
      tls['cipher_suites'] = SettingConfigItemTLS.kCipherSuitesPatt.split(':');
      tls['utls'] = {
        'enabled': true,
        'fingerprint': 'chrome',
      };
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

    // hijack dns
    if (tunMode || setting.tun.hijackDns) {
      rules.add({
        'inbound': ['tun-in'],
        'protocol': 'dns',
        'outbound': kOutboundTagDns,
      });
    }
    rules.add({
      'protocol': 'dns',
      'outbound': kOutboundTagDns,
    });

    // Iran mode: domestic traffic direct, Iranian ads blocked. Runs before
    // user diversion groups so users can override per rule.
    if (setting.iranMode) {
      ruleSets.add(_buildInRuleSet("geosite", "category-ads-ir"));
      ruleSets.add(_buildInRuleSet("geoip", "ir"));
      ruleSets.add(_buildInRuleSet("geosite", "ir"));
      rules.add({
        'rule_set': [_ruleSetTag("category-ads-ir", "geosite")],
        'outbound': kOutboundTagBlock,
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
            r['outbound'] = kOutboundTagBlock;
            break;
          default:
            r['outbound'] = rule.outbound;
        }
        if (r.isNotEmpty && r.containsKey('outbound')) {
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
    if (dns != null && dns['servers'] is List && (dns['servers'] as List).isNotEmpty) {
      route['default_domain_resolver'] = {
        'server': (dns['servers'] as List).first['tag'],
      };
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
