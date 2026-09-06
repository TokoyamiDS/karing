// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Official Cloudflare CIDR ranges (https://www.cloudflare.com/ips/),
/// pinned at build time. IPv6 ranges are only used for classification of
/// literal addresses; the scanner samples IPv4 ranges only.
class CloudflareRanges {
  static const List<String> ipv4 = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ];

  static const List<String> ipv6 = [
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ];

  static final List<(_Net4, int)> _v4Nets = ipv4.map((cidr) {
    final parts = cidr.split("/");
    return (_parseIp4(parts[0]), int.parse(parts[1]));
  }).toList();

  static final List<(_Net6, int)> _v6Nets = ipv6.map((cidr) {
    final parts = cidr.split("/");
    final net = _parseIp6(parts[0]);
    return (net!, int.parse(parts[1]));
  }).toList();

  /// True when [host] is a literal IP inside a Cloudflare range.
  static bool isCloudflareLiteral(String host) {
    final h = host.trim();
    if (h.isEmpty) {
      return false;
    }
    if (h.contains(":")) {
      final addr = _parseIp6(h);
      if (addr == null) {
        return false;
      }
      for (final (net, prefix) in _v6Nets) {
        if (_prefixMatch6(addr, net, prefix)) {
          return true;
        }
      }
      return false;
    }
    final addr = _parseIp4(h);
    if (addr == null) {
      return false;
    }
    for (final (net, prefix) in _v4Nets) {
      if (_prefixMatch4(addr, net, prefix)) {
        return true;
      }
    }
    return false;
  }

  /// Parses "173.245.48.0/20" style entries from user config.
  static List<(_Net4, int)> parseCidr4(Iterable<String> cidrs) {
    final out = <(_Net4, int)>[];
    for (final c in cidrs) {
      final parts = c.split("/");
      final ip = _parseIp4(parts[0]);
      if (ip == null) {
        continue;
      }
      out.add((ip, parts.length > 1 ? int.tryParse(parts[1]) ?? 32 : 32));
    }
    return out;
  }

  /// One uniformly random IPv4 address inside the CF ranges.
  static String randomIp(Random? rng) {
    final r = rng ?? Random();
    final (net, prefix) = _v4Nets[r.nextInt(_v4Nets.length)];
    final hostBits = 32 - prefix;
    final host = r.nextBigInteger(hostBits);
    return _formatIp4(net + host);
  }

  /// Samples [count] unique random IPs across the CF ranges.
  static List<String> sampleIps(int count, {int? seed}) {
    final r = seed == null ? Random() : Random(seed);
    final seen = <int>{};
    final out = <String>[];
    var guard = 0;
    while (out.length < count && guard < count * 10) {
      guard++;
      final (net, prefix) = _v4Nets[r.nextInt(_v4Nets.length)];
      final hostBits = 32 - prefix;
      final addr = net + r.nextBigInteger(hostBits);
      if (!seen.add(addr)) {
        continue;
      }
      out.add(_formatIp4(addr));
    }
    return out;
  }
}

typedef _Net4 = int;
typedef _Net6 = List<int>; // 8 x 16-bit groups

int _parseIp4(String s) {
  final parts = s.trim().split(".");
  if (parts.length != 4) {
    return -1;
  }
  int v = 0;
  for (final p in parts) {
    final o = int.tryParse(p);
    if (o == null || o < 0 || o > 255) {
      return -1;
    }
    v = (v << 8) | o;
  }
  return v;
}

String _formatIp4(int v) {
  return "${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}";
}

bool _prefixMatch4(int addr, int net, int prefix) {
  if (prefix <= 0) {
    return true;
  }
  if (prefix >= 32) {
    return addr == net;
  }
  final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  return (addr & mask) == (net & mask);
}

_Net6? _parseIp6(String s) {
  // Expand "::" shorthand, then parse 16-bit hex groups.
  var str = s.trim();
  if (str.startsWith("[")) {
    str = str.substring(1, str.length - 1);
  }
  final dcolon = str.split("::");
  if (dcolon.length > 2) {
    return null;
  }
  List<String> head, tail;
  if (dcolon.length == 2) {
    head = dcolon[0].isEmpty ? [] : dcolon[0].split(":");
    tail = dcolon[1].isEmpty ? [] : dcolon[1].split(":");
    final missing = 8 - head.length - tail.length;
    if (missing < 0) {
      return null;
    }
    // Each IPv4-embedded tail group counts as two 16-bit groups.
    final groups = <String>[...head];
    for (int i = 0; i < missing; i++) {
      groups.add("0");
    }
    groups.addAll(tail);
    if (groups.length != 8) {
      return null;
    }
    final out = List<int>.filled(8, 0);
    for (int i = 0; i < 8; i++) {
      final g = int.tryParse(groups[i], radix: 16);
      if (g == null || g < 0 || g > 0xFFFF) {
        return null;
      }
      out[i] = g;
    }
    return out;
  }
  final raw = str.split(":");
  if (raw.length != 8) {
    return null;
  }
  final out = List<int>.filled(8, 0);
  for (int i = 0; i < 8; i++) {
    final g = int.tryParse(raw[i], radix: 16);
    if (g == null || g < 0 || g > 0xFFFF) {
      return null;
    }
    out[i] = g;
  }
  return out;
}

bool _prefixMatch6(List<int> addr, List<int> net, int prefix) {
  int remaining = prefix;
  for (int i = 0; i < 8 && remaining > 0; i++) {
    final bits = remaining >= 16 ? 16 : remaining;
    final mask = bits >= 16 ? 0xFFFF : (0xFFFF << (16 - bits)) & 0xFFFF;
    if ((addr[i] & mask) != (net[i] & mask)) {
      return false;
    }
    remaining -= bits;
  }
  return true;
}

extension on Random {
  /// Non-negative integer with [bits] random bits (supports > 32).
  int nextBigInteger(int bits) {
    if (bits <= 0) {
      return 0;
    }
    if (bits <= 32) {
      return _nextBits(this, bits);
    }
    var v = _nextBits(this, 31);
    var left = bits - 31;
    while (left > 0) {
      final take = left >= 31 ? 31 : left;
      v = (v << take) | _nextBits(this, take);
      left -= take;
    }
    return v;
  }

  static int _nextBits(Random r, int bits) {
    var v = 0;
    for (int i = 0; i < bits; i++) {
      v = (v << 1) | (r.nextBool() ? 1 : 0);
    }
    return v;
  }
}

/// DNS-backed classification for domains. Resolves [host] and reports whether
/// any address lives inside a Cloudflare range. Results are cached for the
/// process lifetime (CF membership is effectively stable).
class CloudflareDetector {
  static final Map<String, bool> _cache = {};
  static final Set<String> _pending = {};
  static final List<void Function(String host, bool isCf)> _listeners = [];

  static void addListener(void Function(String host, bool isCf) cb) {
    _listeners.add(cb);
  }

  static void removeListener(void Function(String host, bool isCf) cb) {
    _listeners.remove(cb);
  }

  /// Cached verdict for [host]; null when not yet known.
  static bool? cached(String host) {
    final h = host.trim();
    if (CloudflareRanges.isCloudflareLiteral(h)) {
      return true;
    }
    return _cache[h];
  }

  /// Synchronous best-effort check: literal IPs are answered from ranges;
  /// domains only when a cached verdict exists.
  static bool? checkSync(String host) => cached(host);

  /// Full check: resolves domains (through the system resolver) and tests
  /// every address against the CF ranges. Never throws; returns null when
  /// the host cannot be resolved.
  static Future<bool?> check(String host) async {
    final h = host.trim();
    if (h.isEmpty) {
      return null;
    }
    if (CloudflareRanges.isCloudflareLiteral(h)) {
      return true;
    }
    final cached = _cache[h];
    if (cached != null) {
      return cached;
    }
    if (_pending.contains(h)) {
      return null;
    }
    _pending.add(h);
    try {
      final addrs = await InternetAddress.lookup(h)
          .timeout(const Duration(seconds: 3));
      bool any = false;
      for (final a in addrs) {
        if (CloudflareRanges.isCloudflareLiteral(a.address)) {
          any = true;
          break;
        }
      }
      _cache[h] = any;
      for (final l in List.of(_listeners)) {
        try {
          l(h, any);
        } catch (_) {}
      }
      return any;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(h);
    }
  }

  static void setCache(String host, bool isCf) {
    _cache[host.trim()] = isCf;
  }
}

/// Confirms an IP is a live Cloudflare edge by opening TLS :443 with SNI
/// [probeHost] and requesting the /cdn-cgi/trace endpoint, which only CF
/// answers (contains `fl=` and `colo=` lines).
Future<CfProbeResult> cfProbeTrace(
  String ip, {
  String probeHost = "speed.cloudflare.com",
  Duration timeout = const Duration(seconds: 5),
  String? expectColo,
}) async {
  final sw = Stopwatch()..start();
  SecureSocket? socket;
  try {
    final raw = await Socket.connect(ip, 443, timeout: timeout);
    try {
      socket = await SecureSocket.secure(
        raw,
        host: probeHost,
        onBadCertificate: (_) => true,
        supportedProtocols: const ["h2", "http/1.1"],
      ).timeout(timeout);
    } catch (err) {
      raw.destroy();
      rethrow;
    }
    sw.stop();
    final tlsMs = sw.elapsedMilliseconds;

    final req = "GET /cdn-cgi/trace HTTP/1.1\r\n"
        "Host: $probeHost\r\n"
        "User-Agent: karing-cf-scanner\r\n"
        "Accept: */*\r\n"
        "Connection: close\r\n"
        "\r\n";
    socket.add(req.codeUnits);
    final body = await _readAll(socket, timeout);
    await socket.close();
    socket.destroy();

    final text = String.fromCharCodes(body);
    final isCf = text.contains("fl=") && text.contains("colo=");
    String? colo;
    String? ip0;
    String? warp;
    if (isCf) {
      for (final line in text.split("\n")) {
        final l = line.trim();
        if (l.startsWith("colo=")) {
          colo = l.substring(5);
        } else if (l.startsWith("ip=")) {
          ip0 = l.substring(3);
        } else if (l.startsWith("warp=")) {
          warp = l.substring(5);
        }
      }
    }
    return CfProbeResult(
      ip: ip,
      ok: isCf,
      latencyMs: tlsMs,
      totalMs: 0,
      colo: colo,
      exitIp: ip0,
      warp: warp,
      error: isCf ? "" : "no cdn-cgi/trace response",
    );
  } catch (err) {
    sw.stop();
    try {
      socket?.destroy();
    } catch (_) {}
    var msg = err.toString();
    if (msg.length > 120) {
      msg = msg.substring(0, 120);
    }
    return CfProbeResult(
      ip: ip,
      ok: false,
      latencyMs: sw.elapsedMilliseconds,
      totalMs: 0,
      error: msg,
    );
  }
}

Future<List<int>> _readAll(SecureSocket socket, Duration timeout) async {
  final out = <int>[];
  final done = Completer<void>();
  late final StreamSubscription<List<int>> sub;
  sub = socket.listen(
    (data) {
      out.addAll(data);
      if (out.length > 16384) {
        done.complete();
        sub.cancel();
        socket.destroy();
      }
    },
    onDone: () {
      if (!done.isCompleted) {
        done.complete();
      }
    },
    onError: (Object e) {
      if (!done.isCompleted) {
        done.complete();
      }
    },
    cancelOnError: true,
  );
  return done.future.timeout(timeout, onTimeout: () {
    try {
      sub.cancel();
      socket.destroy();
    } catch (_) {}
    return out;
  }).then<List<int>>((_) => out);
}

class CfProbeResult {
  final String ip;
  final bool ok;
  final int latencyMs;
  final int totalMs;
  final String? colo;
  final String? exitIp;
  final String? warp;
  final String error;

  CfProbeResult({
    required this.ip,
    required this.ok,
    required this.latencyMs,
    required this.totalMs,
    this.colo,
    this.exitIp,
    this.warp,
    this.error = "",
  });
}
