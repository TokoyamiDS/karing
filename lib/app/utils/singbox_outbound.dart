import 'package:flutter/widgets.dart';

/// sing-box only implements the XTLS Vision flow. Xray/v2rayN links carry
/// other flow values — e.g. the `xtls-rprx-vision-udp443` UDP/443 variant or
/// legacy `xtls-rprx-direct`/`splice` modes — and the core aborts the whole
/// config with "unsupported flow" on anything it does not know. Map the
/// known alias to Vision and drop every other flow so one bad node can never
/// prevent the service from starting.
String normalizeVlessFlow(String? value) {
  final flow = (value ?? '').trim().toLowerCase();
  if (flow == 'xtls-rprx-vision' || flow == 'xtls-rprx-vision-udp443') {
    return 'xtls-rprx-vision';
  }
  return '';
}

/// sing-box outbound option models.
class SingboxOutboundType {
  static const String shadowsocks = "shadowsocks";
  static const String shadowsocksr = "shadowsocksr";
  static const String shadowtls = "shadowtls";
  static const String vmess = "vmess";
  static const String vless = "vless";
  static const String trojan = "trojan";
  static const String socks = "socks";
  static const String http = "http";
  static const String hysteria = "hysteria";
  static const String hysteria2 = "hysteria2";
  static const String wireguard = "wireguard";
  static const String tuic = "tuic";
  static const String tor = "tor";
  static const String ssh = "ssh";
  static const String anytls = "anytls";
  static const String mieru = "mieru";
  static const String naive = "naive";

  static List<String> getNames() {
    return [
      shadowsocks,
      shadowsocksr,
      shadowtls,
      vmess,
      vless,
      trojan,
      socks,
      http,
      hysteria,
      hysteria2,
      wireguard,
      tuic,
      tor,
      ssh,
      anytls,
      mieru,
      naive,
    ];
  }

  static String get vmess_name => vmess;
}

/// Base per-protocol options. Every protocol carries server/server_port
/// plus a list of required field names for the editor validation.
class SingboxOutboundProtocolBase {
  String? tag;
  String? server;
  int? server_port;

  /// fields that must be filled before save (editor validation).
  /// returns a message with missing field names, empty when valid.
  String getRequired() {
    final missing = <String>[];
    if (server == null || server!.isEmpty) {
      missing.add('server');
    }
    if (server_port == null || server_port! <= 0) {
      missing.add('server_port');
    }
    return missing.join(", ");
  }

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    if (tag != null && tag!.isNotEmpty) out['tag'] = tag;
    if (server != null && server!.isNotEmpty) out['server'] = server;
    if (server_port != null && server_port! > 0) {
      out['server_port'] = server_port;
    }
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    tag = map['tag']?.toString();
    server = map['server']?.toString();
    server_port = map['server_port'] is int
        ? map['server_port']
        : int.tryParse((map['server_port'] ?? '').toString());
  }
}

class SingboxOutboundShadowsocksOptions extends SingboxOutboundProtocolBase {
  String? method;
  String? password;

  @override
  @override
  String getRequired() {
    final missing = <String>[];
    if (method == null || method!.isEmpty) {
      missing.add('method');
    }
    if (password == null || password!.isEmpty) {
      missing.add('password');
    }
    return missing.isEmpty ? super.getRequired() : missing.join(", ");
  }

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    if (method != null) out['method'] = method;
    if (password != null) out['password'] = password;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    method = map['method']?.toString();
    password = map['password']?.toString();
  }
}

class SingboxOutboundShadowsocksROptions extends SingboxOutboundProtocolBase {
  String? method;
  String? password;
  String? protocol;
  String? protocol_param;
  String? obfs;
  String? obfs_param;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['method'] = method;
    out['password'] = password;
    out['protocol'] = protocol;
    out['protocol_param'] = protocol_param;
    out['obfs'] = obfs;
    out['obfs_param'] = obfs_param;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    method = map['method']?.toString();
    password = map['password']?.toString();
    protocol = map['protocol']?.toString();
    protocol_param = map['protocol_param']?.toString();
    obfs = map['obfs']?.toString();
    obfs_param = map['obfs_param']?.toString();
  }
}

class SingboxOutboundShadowTLSOptions extends SingboxOutboundProtocolBase {
  String? password;
  String? version;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['password'] = password;
    out['version'] = version;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    password = map['password']?.toString();
    version = map['version']?.toString();
  }
}

class SingboxOutboundVMessOptions extends SingboxOutboundProtocolBase {
  String? uuid;
  String? security;
  int? alter_id;

  @override
  @override
  String getRequired() {
    final missing = <String>[];
    if (uuid == null || uuid!.isEmpty) {
      missing.add('uuid');
    }
    return missing.isEmpty ? super.getRequired() : missing.join(", ");
  }

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['uuid'] = uuid;
    out['security'] = security ?? 'auto';
    out['alter_id'] = alter_id ?? 0;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    uuid = map['uuid']?.toString();
    security = map['security']?.toString();
    alter_id = map['alter_id'] is int ? map['alter_id'] : 0;
  }
}

class SingboxOutboundVLESSOptions extends SingboxOutboundProtocolBase {
  String? uuid;
  String? flow;

  @override
  @override
  String getRequired() {
    final missing = <String>[];
    if (uuid == null || uuid!.isEmpty) {
      missing.add('uuid');
    }
    return missing.isEmpty ? super.getRequired() : missing.join(", ");
  }

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['uuid'] = uuid;
    final normalizedFlow = normalizeVlessFlow(flow);
    if (normalizedFlow.isNotEmpty) out['flow'] = normalizedFlow;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    uuid = map['uuid']?.toString();
    flow = normalizeVlessFlow(map['flow']?.toString());
  }
}

class SingboxOutboundTrojanOptions extends SingboxOutboundProtocolBase {
  String? password;

  @override
  @override
  String getRequired() {
    final missing = <String>[];
    if (password == null || password!.isEmpty) {
      missing.add('password');
    }
    return missing.isEmpty ? super.getRequired() : missing.join(", ");
  }

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['password'] = password;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    password = map['password']?.toString();
  }
}

class SingboxOutboundSocksOptions extends SingboxOutboundProtocolBase {
  String? username;
  String? password;
  String? version;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['username'] = username;
    out['password'] = password;
    out['version'] = version ?? '5';
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    username = map['username']?.toString();
    password = map['password']?.toString();
    version = map['version']?.toString();
  }
}

class SingboxOutboundHTTPOptions extends SingboxOutboundProtocolBase {
  String? username;
  String? password;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['username'] = username;
    out['password'] = password;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    username = map['username']?.toString();
    password = map['password']?.toString();
  }
}

class SingboxOutboundHysteriaOptions extends SingboxOutboundProtocolBase {
  String? auth_str;
  String? up_mbps;
  String? down_mbps;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['auth_str'] = auth_str;
    out['up_mbps'] = up_mbps;
    out['down_mbps'] = down_mbps;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    auth_str = map['auth_str']?.toString();
    up_mbps = map['up_mbps']?.toString();
    down_mbps = map['down_mbps']?.toString();
  }
}

class SingboxOutboundHysteria2Options extends SingboxOutboundProtocolBase {
  String? password;
  String? up_mbps;
  String? down_mbps;
  String? obfs_password;

  @override
  @override
  String getRequired() {
    final missing = <String>[];
    if (password == null || password!.isEmpty) {
      missing.add('password');
    }
    return missing.isEmpty ? super.getRequired() : missing.join(", ");
  }

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['password'] = password;
    out['up_mbps'] = up_mbps;
    out['down_mbps'] = down_mbps;
    if (obfs_password != null && obfs_password!.isNotEmpty) {
      out['obfs'] = {'type': 'salamander', 'password': obfs_password};
    }
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    password = map['password']?.toString();
    up_mbps = map['up_mbps']?.toString();
    down_mbps = map['down_mbps']?.toString();
    if (map['obfs'] is Map) {
      obfs_password = map['obfs']['password']?.toString();
    }
  }
}

class SingboxOutboundWireGuardOptions extends SingboxOutboundProtocolBase {
  String? private_key;
  String? peer_public_key;
  String? reserved;
  String? local_address;

  @override
  @override
  String getRequired() {
    final missing = <String>[];
    if (private_key == null || private_key!.isEmpty) {
      missing.add('private_key');
    }
    if (peer_public_key == null || peer_public_key!.isEmpty) {
      missing.add('peer_public_key');
    }
    return missing.isEmpty ? super.getRequired() : missing.join(", ");
  }

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['private_key'] = private_key;
    out['peer_public_key'] = peer_public_key;
    out['reserved'] = reserved;
    out['local_address'] = local_address?.split(',');
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    private_key = map['private_key']?.toString();
    peer_public_key = map['peer_public_key']?.toString();
    reserved = map['reserved']?.toString();
    local_address = map['local_address'] is List
        ? (map['local_address'] as List).join(',')
        : map['local_address']?.toString();
  }
}

class SingboxOutboundTUICOptions extends SingboxOutboundProtocolBase {
  String? uuid;
  String? password;
  String? congestion_control;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['uuid'] = uuid;
    out['password'] = password;
    out['congestion_control'] = congestion_control ?? 'bbr';
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    uuid = map['uuid']?.toString();
    password = map['password']?.toString();
    congestion_control = map['congestion_control']?.toString();
  }
}

class SingboxOutboundTorOptions extends SingboxOutboundProtocolBase {}

class SingboxOutboundSSHOptions extends SingboxOutboundProtocolBase {
  String? user;
  String? private_key;
  String? password;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['user'] = user ?? 'root';
    out['private_key'] = private_key;
    out['password'] = password;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    user = map['user']?.toString();
    private_key = map['private_key']?.toString();
    password = map['password']?.toString();
  }
}

class SingboxOutboundAnyTlsOptions extends SingboxOutboundProtocolBase {
  String? password;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['password'] = password;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    password = map['password']?.toString();
  }
}

class SingboxOutboundMieruOptions extends SingboxOutboundProtocolBase {
  String? password;
  String? transport;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['password'] = password;
    out['transport'] = transport;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    password = map['password']?.toString();
    transport = map['transport']?.toString();
  }
}

class SingboxOutboundNaiveOptions extends SingboxOutboundProtocolBase {
  String? username;
  String? password;

  @override
  Map<String, dynamic> toJson() {
    final out = super.toJson();
    out['username'] = username;
    out['password'] = password;
    return out;
  }

  @override
  void fromJson(Map<String, dynamic>? map) {
    super.fromJson(map);
    if (map == null) return;
    username = map['username']?.toString();
    password = map['password']?.toString();
  }
}

class SingboxOutboundDialerOptions {
  String detour = "";
  bool tcpFastOpen = false;
  String tcpMultiPath = "";
  String bindInterface = "";
  String routingMark = "";
  String domainResolver = "";

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    if (detour.isNotEmpty) out['detour'] = detour;
    if (tcpFastOpen) out['tcp_fast_open'] = true;
    if (tcpMultiPath.isNotEmpty) out['tcp_multi_path'] = tcpMultiPath;
    if (bindInterface.isNotEmpty) out['bind_interface'] = bindInterface;
    if (routingMark.isNotEmpty) out['routing_mark'] = routingMark;
    if (domainResolver.isNotEmpty) out['domain_resolver'] = domainResolver;
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    detour = map['detour'] ?? "";
    tcpFastOpen = map['tcp_fast_open'] ?? false;
    tcpMultiPath = map['tcp_multi_path'] ?? "";
    bindInterface = map['bind_interface'] ?? "";
    routingMark = map['routing_mark'] ?? "";
    domainResolver = map['domain_resolver'] ?? "";
  }
}

class SingboxOutboundUTLSOptions {
  bool enabled = false;
  String fingerprint = "";

  Map<String, dynamic> toJson() {
    if (!enabled) return {};
    final out = <String, dynamic>{'enabled': true};
    if (fingerprint.isNotEmpty) out['fingerprint'] = fingerprint;
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    enabled = map['enabled'] ?? false;
    fingerprint = map['fingerprint'] ?? "";
  }
}

class SingboxOutboundRealityOptions {
  bool enabled = false;
  String publicKey = "";
  String shortId = "";

  /// sing-box decodes `public_key` as *unpadded* URL-safe base64 and requires
  /// exactly 32 bytes, so a usable key is 43 characters of [A-Za-z0-9_-].
  /// Anything else — an empty string, the standard base64 alphabet, padding, or
  /// a wrong length — makes the core fail with `invalid public_key` and refuse
  /// to start, taking every other outbound down with it. Verified against the
  /// bundled core with `sing-box check`.
  static final RegExp _publicKeyRe = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static bool isValidPublicKey(String key) => _publicKeyRe.hasMatch(key);

  Map<String, dynamic> toJson() {
    if (!enabled) return {};
    // Omit reality entirely when the key is unusable: publishing it with an
    // empty public_key aborts core startup (see isValidPublicKey), whereas
    // omitting it degrades the node to plain TLS and leaves the rest working.
    if (!isValidPublicKey(publicKey)) return {};
    return {
      'enabled': true,
      'public_key': publicKey,
      'short_id': shortId,
    };
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    enabled = map['enabled'] ?? false;
    publicKey = map['public_key'] ?? "";
    shortId = map['short_id'] ?? "";
  }
}

class SingboxOutboundTLSOptions {
  bool enabled = false;
  bool disableSni = false;
  String serverName = "";
  bool insecure = false;
  List<String> alpn = [];
  String minVersion = "";
  String maxVersion = "";
  List<String> cipherSuites = [];
  String certificate = "";
  String echConfig = "";
  bool echEnabled = false;
  bool fragment = false;
  String fragmentFallbackDelay = "";
  bool recordFragment = false;
  List<String> fragmentSizes = [];
  List<String> fragmentDelays = [];
  int fragmentMaxSplit = 0;
  SingboxOutboundUTLSOptions? utls;
  SingboxOutboundRealityOptions? reality;

  Map<String, dynamic> toJson() {
    if (!enabled) return {};
    final out = <String, dynamic>{
      'enabled': true,
      'server_name': serverName,
      'insecure': insecure,
    };
    if (disableSni) out['disable_sni'] = true;
    if (alpn.isNotEmpty) out['alpn'] = alpn;
    if (minVersion.isNotEmpty) out['min_version'] = minVersion;
    if (maxVersion.isNotEmpty) out['max_version'] = maxVersion;
    if (cipherSuites.isNotEmpty) out['cipher_suites'] = cipherSuites;
    if (certificate.isNotEmpty) out['certificate'] = certificate;
    if (echEnabled) {
      // A non-PEM ech.config makes the core abort startup entirely
      // ("FATAL initialize outbound[N]: invalid ECH configs pem"), so never emit one.
      // Empty config stays enabled: the core then resolves ECH from DNS, as before.
      final echIsPem = echConfig.contains('-----BEGIN');
      if (echIsPem || echConfig.isEmpty) {
        out['ech'] = {
          'enabled': true,
          if (echIsPem) 'config': echConfig
        };
      }
    }
    if (fragment) out['fragment'] = true;
    if (fragmentFallbackDelay.isNotEmpty) {
      out['fragment_fallback_delay'] = fragmentFallbackDelay;
    }
    if (recordFragment) out['record_fragment'] = true;
    if (fragmentSizes.isNotEmpty) out['fragment_sizes'] = fragmentSizes;
    if (fragmentDelays.isNotEmpty) out['fragment_delays'] = fragmentDelays;
    if (fragmentMaxSplit > 0) out['fragment_max_split'] = fragmentMaxSplit;
    final u = utls?.toJson();
    if (u != null && u.isNotEmpty) out['utls'] = u;
    final r = reality?.toJson();
    if (r != null && r.isNotEmpty) out['reality'] = r;
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    enabled = map['enabled'] ?? false;
    disableSni = map['disable_sni'] ?? false;
    serverName = map['server_name'] ?? "";
    insecure = map['insecure'] ?? false;
    alpn = List<String>.from(map['alpn'] ?? []);
    minVersion = map['min_version'] ?? "";
    maxVersion = map['max_version'] ?? "";
    cipherSuites = List<String>.from(map['cipher_suites'] ?? []);
    certificate = map['certificate'] ?? "";
    if (map['ech'] is Map) {
      final ech = map['ech'];
      echEnabled = ech['enabled'] ?? false;
      echConfig = ech['config'] ?? "";
    }
    fragment = map['fragment'] ?? false;
    fragmentFallbackDelay = map['fragment_fallback_delay'] ?? "";
    recordFragment = map['record_fragment'] ?? false;
    if (map['fragment_sizes'] is List) {
      fragmentSizes = List<String>.from(
          map['fragment_sizes'].map((e) => e.toString()));
    }
    if (map['fragment_delays'] is List) {
      fragmentDelays = List<String>.from(
          map['fragment_delays'].map((e) => e.toString()));
    }
    fragmentMaxSplit = map['fragment_max_split'] ?? 0;
    if (map['finalmask'] is Map) {
      // PattN finalmask JSON: extract tcp fragment lengths/delays
      try {
        final fm = map['finalmask'];
        final tcpList = fm['tcp'];
        if (tcpList is List && tcpList.isNotEmpty) {
          final settings = tcpList[0]['settings'];
          if (settings is Map) {
            final lengths = settings['lengths'];
            if (lengths is List && fragmentSizes.isEmpty) {
              fragmentSizes =
                  List<String>.from(lengths.map((e) => e.toString()));
            }
            final delays = settings['delays'];
            if (delays is List && fragmentDelays.isEmpty) {
              fragmentDelays =
                  List<String>.from(delays.map((e) => e.toString()));
            }
          }
        }
      } catch (_) {}
    }
    if (map['utls'] is Map) {
      utls = SingboxOutboundUTLSOptions()..fromJson(map['utls']);
    }
    if (map['reality'] is Map) {
      reality = SingboxOutboundRealityOptions()..fromJson(map['reality']);
    }
  }
}

class SingboxOutboundMultiplexBrutalOptions {
  bool enabled = false;
  int upMbps = 0;
  int downMbps = 0;

  Map<String, dynamic> toJson() {
    if (!enabled) return {};
    return {'enabled': true, 'up_mbps': upMbps, 'down_mbps': downMbps};
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    enabled = map['enabled'] ?? false;
    upMbps = map['up_mbps'] ?? 0;
    downMbps = map['down_mbps'] ?? 0;
  }

  static SingboxOutboundMultiplexBrutalOptions fromJsonStatic(
      Map<String, dynamic>? map) {
    final o = SingboxOutboundMultiplexBrutalOptions();
    o.fromJson(map);
    return o;
  }
}

class SingboxOutboundMultiplexOptions {
  bool enabled = false;
  String protocol = "h2mux";
  int maxConnections = 0;
  int minStreams = 0;
  int maxStreams = 0;
  bool padding = false;
  SingboxOutboundMultiplexBrutalOptions? brutal;

  Map<String, dynamic> toJson() {
    if (!enabled) return {};
    final out = <String, dynamic>{
      'enabled': true,
      'protocol': protocol,
      'padding': padding,
    };
    if (maxConnections > 0) out['max_connections'] = maxConnections;
    if (minStreams > 0) out['min_streams'] = minStreams;
    if (maxStreams > 0) out['max_streams'] = maxStreams;
    final b = brutal?.toJson();
    if (b != null && b.isNotEmpty) out['brutal'] = b;
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    enabled = map['enabled'] ?? false;
    protocol = map['protocol'] ?? "h2mux";
    maxConnections = map['max_connections'] ?? 0;
    minStreams = map['min_streams'] ?? 0;
    maxStreams = map['max_streams'] ?? 0;
    padding = map['padding'] ?? false;
    if (map['brutal'] is Map) {
      brutal = SingboxOutboundMultiplexBrutalOptions()
        ..fromJson(map['brutal']);
    }
  }
}

class SingboxOutboundTransportOptions {
  String type = "";
  String path = "";
  Map<String, String> headers = {};
  String serviceName = "";
  String method = "";
  String host = "";
  String idleTimeout = "";
  String earlyDataHeaderName = "";
  int maxEarlyData = 0;

  Map<String, dynamic> toJson() {
    if (type.isEmpty) return {};
    final out = <String, dynamic>{'type': type};
    if (type == 'ws') {
      if (path.isNotEmpty) out['path'] = path;
      if (headers.isNotEmpty) out['headers'] = headers;
      if (earlyDataHeaderName.isNotEmpty) {
        out['early_data_header_name'] = earlyDataHeaderName;
      }
      if (maxEarlyData > 0) out['max_early_data'] = maxEarlyData;
    } else if (type == 'grpc') {
      if (serviceName.isNotEmpty) out['service_name'] = serviceName;
    } else if (type == 'http') {
      if (host.isNotEmpty) {
        out['host'] = host.split(',').map((e) => e.trim()).toList();
      }
      if (path.isNotEmpty) out['path'] = path;
      if (method.isNotEmpty) out['method'] = method;
      if (headers.isNotEmpty) out['headers'] = headers;
      if (idleTimeout.isNotEmpty) out['idle_timeout'] = idleTimeout;
    } else if (type == 'httpupgrade') {
      if (path.isNotEmpty) out['path'] = path;
      if (host.isNotEmpty) out['host'] = host;
      if (headers.isNotEmpty) out['headers'] = headers;
    }
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    type = map['type'] ?? "";
    path = map['path'] ?? "";
    serviceName = map['service_name'] ?? "";
    method = map['method'] ?? "";
    host = map['host'] is List
        ? (map['host'] as List).join(',')
        : map['host'] ?? "";
    idleTimeout = map['idle_timeout'] ?? "";
    earlyDataHeaderName = map['early_data_header_name'] ?? "";
    maxEarlyData = map['max_early_data'] ?? 0;
    if (map['headers'] is Map) {
      headers = (map['headers'] as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    // sing-box ws transport has no `host` field (strict decode rejects it
    // since 1.11): fold legacy host values into the Host header.
    if (type == 'ws' && host.isNotEmpty) {
      final hasHost =
          headers.keys.any((k) => k.toLowerCase() == 'host');
      if (!hasHost) {
        headers['Host'] =
            host.split(',').map((e) => e.trim()).firstWhere((e) => e.isNotEmpty, orElse: () => host);
      }
      host = '';
    }
  }
}

/// Top level outbound options with per-protocol payloads.
class SingboxOutboundOptions {
  String type = "";
  String tag = "";
  String server = "";
  int serverPort = 0;
  int get server_port => serverPort;
  set server_port(int v) => serverPort = v;

  SingboxOutboundShadowsocksOptions? shadowsocks;
  SingboxOutboundShadowsocksROptions? shadowsocksr;
  SingboxOutboundShadowTLSOptions? shadowtls;
  SingboxOutboundVMessOptions? vmess;
  SingboxOutboundVLESSOptions? vless;
  SingboxOutboundTrojanOptions? trojan;
  SingboxOutboundSocksOptions? socks;
  SingboxOutboundHTTPOptions? http;
  SingboxOutboundHysteriaOptions? hysteria;
  SingboxOutboundHysteria2Options? hysteria2;
  SingboxOutboundWireGuardOptions? wg;
  SingboxOutboundTUICOptions? tuic;
  SingboxOutboundTorOptions? tor;
  SingboxOutboundSSHOptions? ssh;
  SingboxOutboundAnyTlsOptions? anytls;
  SingboxOutboundMieruOptions? mieru;
  SingboxOutboundNaiveOptions? naive;

  SingboxOutboundDialerOptions? dialer = SingboxOutboundDialerOptions();
  SingboxOutboundTLSOptions tls = SingboxOutboundTLSOptions();
  SingboxOutboundMultiplexOptions multiplex =
      SingboxOutboundMultiplexOptions();
  SingboxOutboundTransportOptions transport =
      SingboxOutboundTransportOptions();
  String packetEncoding = "";
  bool udpOverTcp = false;
  String outboundDetour = "";

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'type': type,
      'tag': tag,
      'server': server,
      'server_port': serverPort,
    };
    Map<String, dynamic>? proto;
    switch (type) {
      case SingboxOutboundType.shadowsocks:
        proto = shadowsocks?.toJson();
        break;
      case SingboxOutboundType.shadowsocksr:
        proto = shadowsocksr?.toJson();
        break;
      case SingboxOutboundType.shadowtls:
        proto = shadowtls?.toJson();
        break;
      case SingboxOutboundType.vmess:
        proto = vmess?.toJson();
        break;
      case SingboxOutboundType.vless:
        proto = vless?.toJson();
        break;
      case SingboxOutboundType.trojan:
        proto = trojan?.toJson();
        break;
      case SingboxOutboundType.socks:
        proto = socks?.toJson();
        break;
      case SingboxOutboundType.http:
        proto = http?.toJson();
        break;
      case SingboxOutboundType.hysteria:
        proto = hysteria?.toJson();
        break;
      case SingboxOutboundType.hysteria2:
        proto = hysteria2?.toJson();
        break;
      case SingboxOutboundType.wireguard:
        proto = wg?.toJson();
        break;
      case SingboxOutboundType.tuic:
        proto = tuic?.toJson();
        break;
      case SingboxOutboundType.tor:
        proto = tor?.toJson();
        break;
      case SingboxOutboundType.ssh:
        proto = ssh?.toJson();
        break;
      case SingboxOutboundType.anytls:
        proto = anytls?.toJson();
        break;
      case SingboxOutboundType.mieru:
        proto = mieru?.toJson();
        break;
      case SingboxOutboundType.naive:
        proto = naive?.toJson();
        break;
    }
    if (proto != null) {
      proto.remove('tag');
      out.addAll(proto);
    }
    final t = tls.toJson();
    if (t.isNotEmpty) out['tls'] = t;
    final m = multiplex.toJson();
    if (m.isNotEmpty) out['multiplex'] = m;
    final tr = transport.toJson();
    if (tr.isNotEmpty) out['transport'] = tr;
    final d = dialer?.toJson() ?? {};
    if (d.isNotEmpty) out['dialer'] = d;
    if (packetEncoding.isNotEmpty) out['packet_encoding'] = packetEncoding;
    if (udpOverTcp) out['udp_over_tcp'] = true;
    if (outboundDetour.isNotEmpty) out['detour'] = outboundDetour;
    return out;
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    type = map['type'] ?? "";
    tag = map['tag'] ?? "";
    server = map['server'] ?? "";
    serverPort = map['server_port'] is int
        ? map['server_port']
        : int.tryParse((map['server_port'] ?? '0').toString()) ?? 0;
    switch (type) {
      case SingboxOutboundType.shadowsocks:
        shadowsocks = SingboxOutboundShadowsocksOptions()..fromJson(map);
        break;
      case SingboxOutboundType.shadowsocksr:
        shadowsocksr = SingboxOutboundShadowsocksROptions()..fromJson(map);
        break;
      case SingboxOutboundType.shadowtls:
        shadowtls = SingboxOutboundShadowTLSOptions()..fromJson(map);
        break;
      case SingboxOutboundType.vmess:
        vmess = SingboxOutboundVMessOptions()..fromJson(map);
        break;
      case SingboxOutboundType.vless:
        vless = SingboxOutboundVLESSOptions()..fromJson(map);
        break;
      case SingboxOutboundType.trojan:
        trojan = SingboxOutboundTrojanOptions()..fromJson(map);
        break;
      case SingboxOutboundType.socks:
        socks = SingboxOutboundSocksOptions()..fromJson(map);
        break;
      case SingboxOutboundType.http:
        http = SingboxOutboundHTTPOptions()..fromJson(map);
        break;
      case SingboxOutboundType.hysteria:
        hysteria = SingboxOutboundHysteriaOptions()..fromJson(map);
        break;
      case SingboxOutboundType.hysteria2:
        hysteria2 = SingboxOutboundHysteria2Options()..fromJson(map);
        break;
      case SingboxOutboundType.wireguard:
        wg = SingboxOutboundWireGuardOptions()..fromJson(map);
        break;
      case SingboxOutboundType.tuic:
        tuic = SingboxOutboundTUICOptions()..fromJson(map);
        break;
      case SingboxOutboundType.tor:
        tor = SingboxOutboundTorOptions()..fromJson(map);
        break;
      case SingboxOutboundType.ssh:
        ssh = SingboxOutboundSSHOptions()..fromJson(map);
        break;
      case SingboxOutboundType.anytls:
        anytls = SingboxOutboundAnyTlsOptions()..fromJson(map);
        break;
      case SingboxOutboundType.mieru:
        mieru = SingboxOutboundMieruOptions()..fromJson(map);
        break;
      case SingboxOutboundType.naive:
        naive = SingboxOutboundNaiveOptions()..fromJson(map);
        break;
    }
    if (map['tls'] is Map) {
      tls = SingboxOutboundTLSOptions()..fromJson(map['tls']);
    }
    if (map['multiplex'] is Map) {
      multiplex = SingboxOutboundMultiplexOptions()..fromJson(map['multiplex']);
    }
    if (map['transport'] is Map) {
      transport =
          SingboxOutboundTransportOptions()..fromJson(map['transport']);
    }
    if (map['dialer'] is Map) {
      dialer = SingboxOutboundDialerOptions()..fromJson(map['dialer']);
    }
    packetEncoding = map['packet_encoding'] ?? "";
    udpOverTcp = map['udp_over_tcp'] ?? false;
    outboundDetour = map['detour'] ?? "";
  }
}

extension SingboxOutboundOptionsKaring on SingboxOutboundOptions {
}
extension SingboxOutboundOptionsKaring2 on SingboxOutboundOptions {
  bool isValid() {
    String? missing;
    switch (type) {
      case SingboxOutboundType.shadowsocks:
        missing = shadowsocks?.getRequired();
        break;
      case SingboxOutboundType.shadowsocksr:
        missing = shadowsocksr?.getRequired();
        break;
      case SingboxOutboundType.shadowtls:
        missing = shadowtls?.getRequired();
        break;
      case SingboxOutboundType.vmess:
        missing = vmess?.getRequired();
        break;
      case SingboxOutboundType.vless:
        missing = vless?.getRequired();
        break;
      case SingboxOutboundType.trojan:
        missing = trojan?.getRequired();
        break;
      case SingboxOutboundType.hysteria2:
        missing = hysteria2?.getRequired();
        break;
      default:
        missing = null;
    }
    return missing == null || missing.isEmpty;
  }
}
