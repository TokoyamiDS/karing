// ignore_for_file: empty_catches, unused_catch_stack

import 'dart:convert';
import 'dart:io';

import 'package:punycode_converter/punycode_converter.dart' as punycode;
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/emoji_utils.dart';
import 'package:tuple/tuple.dart';

class NetInterfacesInfo {
  InternetAddressType type = InternetAddressType.IPv4;
  String name = "";
  String address = "";
}

class NetworkUtils {
  static final RegExp _domainExp = RegExp(
    r"^(?=^.{3,255}$)[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+$",
  );
  static final RegExp _ipv4Exp = RegExp(
    r"^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$",
  );
  static final RegExp _ipv4ExpWithMask = RegExp(
    r"^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)(\/(\d|[1-2]\d|3[0-2]))?$",
  );
  static final RegExp _ipv6Exp = RegExp(
    r"^([\da-fA-F]{1,4}:){6}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^::([\da-fA-F]{1,4}:){0,4}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:):([\da-fA-F]{1,4}:){0,3}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){2}:([\da-fA-F]{1,4}:){0,2}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){3}:([\da-fA-F]{1,4}:){0,1}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){4}:((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}$|^:((:[\da-fA-F]{1,4}){1,6}|:)$|^[\da-fA-F]{1,4}:((:[\da-fA-F]{1,4}){1,5}|:)$|^([\da-fA-F]{1,4}:){2}((:[\da-fA-F]{1,4}){1,4}|:)$|^([\da-fA-F]{1,4}:){3}((:[\da-fA-F]{1,4}){1,3}|:)$|^([\da-fA-F]{1,4}:){4}((:[\da-fA-F]{1,4}){1,2}|:)$|^([\da-fA-F]{1,4}:){5}:([\da-fA-F]{1,4})?$|^([\da-fA-F]{1,4}:){6}:$^([\da-fA-F]{1,4}:){6}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^::([\da-fA-F]{1,4}:){0,4}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:):([\da-fA-F]{1,4}:){0,3}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){2}:([\da-fA-F]{1,4}:){0,2}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){3}:([\da-fA-F]{1,4}:){0,1}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){4}:((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$|^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}$|^:((:[\da-fA-F]{1,4}){1,6}|:)$|^[\da-fA-F]{1,4}:((:[\da-fA-F]{1,4}){1,5}|:)$|^([\da-fA-F]{1,4}:){2}((:[\da-fA-F]{1,4}){1,4}|:)$|^([\da-fA-F]{1,4}:){3}((:[\da-fA-F]{1,4}){1,3}|:)$|^([\da-fA-F]{1,4}:){4}((:[\da-fA-F]{1,4}){1,2}|:)$|^([\da-fA-F]{1,4}:){5}:([\da-fA-F]{1,4})?$|^([\da-fA-F]{1,4}:){6}:$",
  );
  static final RegExp _ipv6ExpWithMask = RegExp(
    r"^([\da-fA-F]{1,4}:){6}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^::([\da-fA-F]{1,4}:){0,4}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:):([\da-fA-F]{1,4}:){0,3}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){2}:([\da-fA-F]{1,4}:){0,2}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){3}:([\da-fA-F]{1,4}:){0,1}((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){4}:((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^:((:[\da-fA-F]{1,4}){1,6}|:)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^[\da-fA-F]{1,4}:((:[\da-fA-F]{1,4}){1,5}|:)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){2}((:[\da-fA-F]{1,4}){1,4}|:)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){3}((:[\da-fA-F]{1,4}){1,3}|:)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){4}((:[\da-fA-F]{1,4}){1,2}|:)(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){5}:([\da-fA-F]{1,4})?(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$|^([\da-fA-F]{1,4}:){6}:(\/([1-9]?\d|(1([0-1]\d|2[0-8]))))?$",
  );
  static bool isDomain(String text, bool allowIp) {
    text = text.toLowerCase();
    if (!allowIp) {
      if (isIpv4(text) || isIpv6(text)) {
        return false;
      }
    }
    text = getRealDomain(text) ?? text;
    return _domainExp.hasMatch(text);
  }

  static bool isIpv4(String text) {
    return _ipv4Exp.hasMatch(text);
  }

  static bool isIpv4WithMask(String text) {
    return _ipv4ExpWithMask.hasMatch(text);
  }

  static bool isIpv6(String text) {
    return _ipv6Exp.hasMatch(text);
  }

  static bool isIpv6WithMask(String text) {
    return _ipv6ExpWithMask.hasMatch(text);
  }

  static bool isPublicIp(String address) {
    final String ipText = address.split('/').first.trim();
    if (ipText.isEmpty) {
      return false;
    }

    final InternetAddress? ip = InternetAddress.tryParse(ipText);
    if (ip == null) {
      return false;
    }

    if (ip.type == InternetAddressType.IPv4) {
      return _isPublicIpv4(ip.rawAddress);
    }
    if (ip.type == InternetAddressType.IPv6) {
      return _isPublicIpv6(ip.rawAddress);
    }
    return false;
  }

  static bool _isPublicIpv4(List<int> raw) {
    if (raw.length != 4) {
      return false;
    }

    final int a = raw[0];
    final int b = raw[1];

    if (a == 0) return false; // 0.0.0.0/8
    if (a == 10) return false; // 10.0.0.0/8
    if (a == 127) return false; // 127.0.0.0/8
    if (a == 169 && b == 254) return false; // 169.254.0.0/16
    if (a == 172 && b >= 16 && b <= 31) return false; // 172.16.0.0/12
    if (a == 192 && b == 168) return false; // 192.168.0.0/16
    if (a == 100 && b >= 64 && b <= 127) return false; // 100.64.0.0/10
    if (a == 192 && b == 0 && raw[2] == 0) return false; // 192.0.0.0/24
    if (a == 192 && b == 0 && raw[2] == 2) return false; // 192.0.2.0/24
    if (a == 198 && (b == 18 || b == 19)) return false; // 198.18.0.0/15
    if (a == 198 && b == 51 && raw[2] == 100) return false; // 198.51.100.0/24
    if (a == 203 && b == 0 && raw[2] == 113) return false; // 203.0.113.0/24
    if (a >= 224) return false; // 224.0.0.0/4 and reserved
    if (a == 255 && b == 255 && raw[2] == 255 && raw[3] == 255) {
      return false;
    }

    return true;
  }

  static bool _isPublicIpv6(List<int> raw) {
    if (raw.length != 16) {
      return false;
    }

    bool isAllZero = true;
    for (final b in raw) {
      if (b != 0) {
        isAllZero = false;
        break;
      }
    }
    if (isAllZero) {
      return false; // ::/128
    }

    bool isLoopback = true;
    for (int i = 0; i < 15; i++) {
      if (raw[i] != 0) {
        isLoopback = false;
        break;
      }
    }
    if (isLoopback && raw[15] == 1) {
      return false; // ::1/128
    }

    if (_hasPrefix(raw, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff], 96)) {
      return false; // ::ffff:0:0/96 IPv4-mapped IPv6 addresses
    }
    if (_hasPrefix(raw, [0x00, 0x64, 0xff, 0x9b], 96)) {
      return false; // 64:ff9b::/96 IPv4/IPv6 translation
    }
    if (_hasPrefix(raw, [0x00, 0x64, 0xff, 0x9b, 0x00, 0x01], 48)) {
      return false; // 64:ff9b:1::/48 local-use translation
    }
    if (_hasPrefix(raw, [0x01, 0x00, 0, 0, 0, 0, 0, 0], 64)) {
      return false; // 100::/64 discard-only prefix
    }
    if (_hasPrefix(raw, [0xfc], 7)) return false; // fc00::/7
    if (_hasPrefix(raw, [0xfe, 0x80], 10)) return false; // fe80::/10
    if (_hasPrefix(raw, [0xff], 8)) return false; // ff00::/8
    if (_hasPrefix(raw, [0x20, 0x01, 0x00, 0x00], 32)) {
      return false; // 2001::/32 special-purpose range, including Teredo
    }
    if (_hasPrefix(raw, [0x20, 0x01, 0x00, 0x02, 0x00, 0x00], 48)) {
      return false; // 2001:2::/48 benchmarking
    }
    if (_hasPrefix(raw, [0x20, 0x01, 0x0d, 0xb8], 32)) {
      return false; // 2001:db8::/32 documentation range
    }
    if (_hasPrefix(raw, [0x20, 0x02], 16)) {
      return false; // 2002::/16 6to4
    }

    return true;
  }

  static bool _hasPrefix(List<int> raw, List<int> prefix, int prefixLength) {
    final int fullBytes = prefixLength ~/ 8;
    final int remainBits = prefixLength % 8;

    if (raw.length * 8 < prefixLength || prefix.length < fullBytes) {
      return false;
    }

    for (int i = 0; i < fullBytes; i++) {
      if (raw[i] != prefix[i]) {
        return false;
      }
    }

    if (remainBits == 0) {
      return true;
    }

    if (prefix.length <= fullBytes || raw.length <= fullBytes) {
      return false;
    }

    final int mask = (0xff << (8 - remainBits)) & 0xff;
    return (raw[fullBytes] & mask) == (prefix[fullBytes] & mask);
  }

  static String? getRealDomain(String text) {
    Uri? uri = Uri.tryParse(text);
    if (uri == null) {
      return null;
    }
    if (uri.host.isEmpty) {
      uri = Uri.tryParse("https://$text");
    }
    if (uri == null) {
      return null;
    }
    try {
      {
        uri = uri.punyEncoded;
      }
    } catch (err) {}
    if (uri == null) {
      return null;
    }
    return uri.host;
  }

  static Future<List<NetInterfacesInfo>> getInterfaces({
    InternetAddressType? addressType = InternetAddressType.IPv4,
    bool filter = true,
  }) async {
    List<NetInterfacesInfo> interfaces = [];
    try {
      List<NetworkInterface> list = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      for (var netinterface in list) {
        for (var address in netinterface.addresses) {
          if (addressType != null && address.type != addressType) {
            continue;
          }
          if (filter) {
            String name = netinterface.name.toLowerCase();
            if (name.startsWith("pdp_") ||
                name.startsWith("ipsec") ||
                name.startsWith("vmware") ||
                name.startsWith("vethernet") ||
                name.startsWith("utun") ||
                name.startsWith("tun") ||
                name.contains("wintun") ||
                name.contains(" tun ")) {
              continue;
            }
          }

          NetInterfacesInfo ni = NetInterfacesInfo();
          ni.name = netinterface.name;
          ni.type = address.type;
          ni.address = address.address;
          interfaces.add(ni);
        }
      }
    } catch (err) {}
    return interfaces..sort((a, b) {
      return a.name.compareTo(b.name);
    });
  }

  static Future<int> getAvaliablePort(List<int> exclude) async {
    final List<ServerSocket> sockets = [];
    int listenPort = 0;
    for (int i = 0; i < exclude.length + 4; ++i) {
      try {
        ServerSocket serverSocket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        sockets.add(serverSocket);
        if (exclude.contains(serverSocket.port)) {
          continue;
        }
        listenPort = serverSocket.port;
        break;
      } catch (err, stacktrace) {}
    }
    for (var sock in sockets) {
      try {
        await sock.close();
      } catch (err) {}
    }
    return listenPort;
  }

  static Future<int> getAvaliablePortNotCloseSocket(
    List<int> excludePorts,
    List<ServerSocket> sockets,
  ) async {
    for (int port = 20000; port < 40000; ++port) {
      if (excludePorts.contains(port)) {
        continue;
      }
      try {
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        sockets.add(socket);
        return port;
      } catch (_) {}
    }
    return 0;
  }

  /// Name fragments used by other tunnelling clients' adapters.
  ///
  /// Deliberately specific. A false positive refuses to start a perfectly good
  /// tunnel, so "Ethernet", "vEthernet" and the VMware adapters must not match.
  static const List<String> _foreignTunnelHints = [
    "tun",
    "tap",
    "wintun",
    "wireguard",
    "openvpn",
    "nebula",
    "zerotier",
    "tailscale",
    "radmin",
    "sing-box",
    "clash",
    "v2ray",
    "xray",
    "hiddify",
    "nekoray",
    "proton",
  ];

  /// The adapter this app's own core creates, so it is never mistaken for a
  /// foreign tunnel. Matches `SingboxInboundTunOptions.interfaceName`.
  static const String kOwnTunnelInterface = "karing";

  /// Whether [interfaceName] belongs to a foreign tunnelling client.
  ///
  /// Exposed so the heuristic can be tested: a false positive refuses to start
  /// a perfectly good tunnel, and a false negative lets two tunnels fight.
  static bool isForeignTunnelName(String interfaceName) {
    final name = interfaceName.toLowerCase();
    if (name == kOwnTunnelInterface) {
      return false;
    }
    return _foreignTunnelHints.any(name.contains);
  }

  /// Tunnel adapters belonging to **another** client, if any.
  ///
  /// Two full-tunnel clients each install their own default route and each
  /// rewrite DNS. Windows then decides connectivity is lost and resets the WLAN
  /// adapter — which is experienced as "the WiFi crashed and I had to wait for
  /// the driver to come back". Not adding a second tunnel is the only part of
  /// that we can control from inside the app.
  ///
  /// Only adapters that are actually up appear here, so a disconnected
  /// competitor is correctly ignored.
  static Future<List<String>> findForeignTunnels() async {
    final found = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );
      for (final item in interfaces) {
        if (isForeignTunnelName(item.name)) {
          found.add(item.name);
        }
      }
    } catch (err) {}
    return found;
  }

  static Future<bool> hasForeignTunnel() async =>
      (await findForeignTunnels()).isNotEmpty;

  /// Parses an exit-IP lookup body into `(ip, countryCode)`.
  ///
  /// Cloudflare's `cdn-cgi/trace` answers plain `ip=…` / `loc=…` lines; anything
  /// else is treated as the older JSON shape, and a bare address is taken as-is.
  /// Extracted so both shapes are covered by tests — a slip here silently blanks
  /// the location for every node, which reads as "the feature is broken" rather
  /// than as a parse bug.
  static Tuple2<String, String> parseOutletIpBody(String body) {
    final text = body.trim();
    if (text.isEmpty) {
      return const Tuple2("", "");
    }
    if (text.contains('ip=')) {
      var ip = "";
      var region = "";
      for (final line in text.split('\n')) {
        final split = line.indexOf('=');
        if (split <= 0) {
          continue;
        }
        final key = line.substring(0, split).trim();
        final value = line.substring(split + 1).trim();
        if (key == 'ip') {
          ip = value;
        } else if (key == 'loc') {
          region = value;
        }
      }
      return Tuple2(ip, region);
    }
    try {
      final geo = jsonDecode(text);
      if (geo is Map) {
        return Tuple2(
          geo["ip"]?.toString() ?? "",
          geo["country_code"]?.toString() ?? "",
        );
      }
    } catch (_) {}
    return Tuple2(text, "");
  }

  /// The inline exit-location label shared by the server list and the home
  /// widget, e.g. `🇩🇪 203.0.113.9 (320ms)`.
  ///
  /// [costMs] is how long the lookup took. While it is unknown the slot shows
  /// `(*)` rather than being omitted — the address is real, but a value whose
  /// cost was never measured must not be presented as measured.
  static String outletLabel(String region, String ip, int costMs) {
    final address = "${EmojiUtils.countryCodeToEmoji(region)} $ip".trim();
    if (address.isEmpty) {
      return "";
    }
    return "$address (${outletCost(costMs)})";
  }

  /// How long the exit-IP lookup took: `(*)` when it was never measured.
  static String outletCost(int costMs) {
    if (costMs <= 0) {
      return "*";
    }
    if (costMs < 1000) {
      return "${costMs}ms";
    }
    return "${(costMs / 1000).toStringAsFixed(1)}s";
  }

  static Future<Tuple2<IpInfo?, String>> getOutletIp(
    int? proxyPort, {
    int timeoutSeconds = 10,
  }) async {
    try {
      final client = HttpClient();
      if (proxyPort != null) {
        client.findProxy = (uri) => "PROXY 127.0.0.1:$proxyPort";
      }
      client.connectionTimeout = Duration(seconds: timeoutSeconds);
      final req = await client.getUrl(Uri.parse("https://api.ip.sb/geoip"));
      req.headers.set(HttpHeaders.userAgentHeader, "curl/8.0");
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode == 200) {
        final json = jsonDecode(body);
        return Tuple2(
          IpInfo(
            ip: json["ip"]?.toString() ?? "",
            countryCode: json["country_code"]?.toString() ?? "",
          ),
          json["country"]?.toString() ?? "",
        );
      }
      return Tuple2(null, "");
    } catch (err) {
      return Tuple2(null, "");
    }
  }

  static Future<List<String>> dnsLookup(
    String domain,
    bool preferIPv4,
  ) async {
    final out = <String>[];
    try {
      final results = await InternetAddress.lookup(
        domain,
        type: preferIPv4 ? InternetAddressType.IPv4 : InternetAddressType.any,
      );
      for (final r in results) {
        out.add(r.address);
      }
    } catch (_) {}
    return out;
  }
}


class IpInfo {
  final String ip;
  final String countryCode;
  IpInfo({required this.ip, required this.countryCode});
}