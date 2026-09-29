// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:karing/app/utils/scan_dialer.dart';

/// Result of one direct DNS probe (no core, no VPN, no system proxy/TUN).
class DnsDirectProbeResult {
  final String server;
  final int latencyMs;
  final bool ok;
  final String error;

  DnsDirectProbeResult({
    required this.server,
    required this.latencyMs,
    required this.ok,
    this.error = "",
  });
}

/// Probes DNS servers directly over the physical NIC (never through the
/// core / Clash API / system proxy / TUN): DoH via plain HttpClient,
/// DoT via SecureSocket, UDP via RawDatagramSocket. `local`/`dhcp://auto`
/// fall back to the OS resolver. Used by the DNS screens when the VPN is
/// off so DNS can be tested without starting the core.
class DnsDirectProbe {
  static Future<DnsDirectProbeResult> probe(
    String server,
    String domain, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final s = server.trim();
      if (s == "local" || s == "dhcp://auto") {
        final addrs = await InternetAddress.lookup(domain).timeout(timeout);
        sw.stop();
        if (addrs.isEmpty) {
          return DnsDirectProbeResult(
              server: server,
              latencyMs: sw.elapsedMilliseconds,
              ok: false,
              error: "no answer");
        }
        return DnsDirectProbeResult(
            server: server, latencyMs: sw.elapsedMilliseconds, ok: true);
      }
      final uri = Uri.tryParse(s);
      if (uri == null || uri.scheme.isEmpty) {
        return DnsDirectProbeResult(
            server: server,
            latencyMs: sw.elapsedMilliseconds,
            ok: false,
            error: "bad url");
      }
      switch (uri.scheme) {
        case "https":
        case "h3":
          await _probeDoh(uri, domain, timeout);
          break;
        case "tls":
        case "dot":
          await _probeDot(uri, domain, timeout);
          break;
        case "udp":
          await _probeUdp(uri, domain, timeout);
          break;
        default:
          return DnsDirectProbeResult(
              server: server,
              latencyMs: sw.elapsedMilliseconds,
              ok: false,
              error: "unsupported");
      }
      sw.stop();
      return DnsDirectProbeResult(
          server: server, latencyMs: sw.elapsedMilliseconds, ok: true);
    } catch (err) {
      sw.stop();
      String msg;
      if (err is TimeoutException) {
        msg = "timeout";
      } else {
        msg = err.toString().replaceFirst("Exception: ", "");
        if (msg.contains("network location cannot be reached")) {
          msg = "unreachable";
        }
      }
      if (msg.length > 100) msg = msg.substring(0, 100);
      return DnsDirectProbeResult(
          server: server,
          latencyMs: sw.elapsedMilliseconds,
          ok: false,
          error: msg);
    }
  }

  static Future<void> _probeDoh(
      Uri uri, String domain, Duration timeout) async {
    // RFC 8484 wire format: every `/dns-query` server accepts it, while the
    // JSON API lives on different paths per vendor (dns.google: /resolve).
    // The system proxy is never inherited so the probe always leaves through
    // the physical NIC (Karing itself sets a system proxy while the VPN runs).
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => "DIRECT";
    final query = buildQuery(domain);
    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.contentType = ContentType("application", "dns-message");
      req.contentLength = query.length;
      req.add(query);
      final res = await req.close().timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > 4096) break;
      }
      if (res.statusCode != 200) throw Exception("http ${res.statusCode}");
      if (bytes.length < 12) throw Exception("no answer");
      if (bytes[0] != query[0] || bytes[1] != query[1]) {
        throw Exception("bad txid");
      }
      if (((bytes[6] << 8) | bytes[7]) < 1) throw Exception("no answer");
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _probeDot(
      Uri uri, String domain, Duration timeout) async {
    final host = uri.host;
    final port = uri.hasPort ? uri.port : 853;
    final raw = await ScanDialer.connect(host, port, timeout: timeout);
    late final SecureSocket socket;
    try {
      socket = await SecureSocket.secure(
        raw,
        host: host,
        onBadCertificate: (_) => true,
      ).timeout(timeout);
    } catch (_) {
      raw.destroy();
      rethrow;
    }
    // SecureSocket is a single-subscription stream, so the whole prefixed
    // answer has to be collected by one listener.
    final received = <int>[];
    final done = Completer<void>();
    void fail(Object err) {
      if (!done.isCompleted) done.completeError(err);
    }

    try {
      socket.listen(
        (data) {
          received.addAll(data);
          if (received.length < 2) return;
          final len = (received[0] << 8) | received[1];
          if (received.length >= 2 + len && !done.isCompleted) {
            done.complete();
          }
        },
        onError: fail,
        onDone: () => fail(Exception("no answer")),
        cancelOnError: true,
      );
      socket.add(framedQuery(domain));
      await done.future.timeout(timeout);
    } finally {
      socket.destroy();
    }
  }

  static Future<void> _probeUdp(
      Uri uri, String domain, Duration timeout) async {
    final host = uri.host;
    final port = uri.hasPort ? uri.port : 53;
    final targets = await ScanDialer.resolve(host);
    InternetAddress? dest = targets.isNotEmpty ? targets.first : null;
    dest ??= InternetAddress.tryParse(host.replaceAll(RegExp(r'[\[\]]'), ""));
    if (dest == null) throw Exception("resolve failed");
    final socket = await RawDatagramSocket.bind(
        dest.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0);
    final query = buildQuery(domain);
    final queryId = (query[0] << 8) | query[1];
    final done = Completer<void>();
    Timer? timer;
    void fail(Object err) {
      if (!done.isCompleted) done.completeError(err);
    }

    try {
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg == null || done.isCompleted) return;
          final data = dg.data;
          // Validate the answer instead of accepting any datagram: Iranian
          // ISPs hijack plain UDP/53 and inject spoofed replies that would
          // otherwise look like a fast, healthy resolver. Require a real DNS
          // response with our txid, the QR bit set and RCODE 0.
          if (data.length < 12) return;
          if (((data[0] << 8) | data[1]) != queryId) return;
          if ((data[2] & 0x80) == 0) return; // QR: must be a response
          final rcode = data[3] & 0x0f;
          if (rcode != 0) {
            fail(Exception("dns rcode $rcode"));
            return;
          }
          done.complete();
        }
      }, onError: (Object err) => fail(err), cancelOnError: true);
      socket.send(query, dest, port);
      timer = Timer(timeout, () => fail(TimeoutException("timeout")));
      await done.future;
    } finally {
      timer?.cancel();
      socket.close();
    }
  }

  static int _txId = 0x1234;

  /// A standards-compliant DNS query for the A record of [domain]:
  /// 12-byte header (id, flags=0x0100 RD, QDCOUNT=1, rest zero), labels,
  /// root label, QTYPE=A, QCLASS=IN. Public for the wire-format test.
  static Uint8List buildQuery(String domain) {
    final id = (_txId = (_txId + 1) & 0xffff);
    final name = <int>[];
    for (final label in domain.split(".")) {
      name.add(label.length);
      name.addAll(label.codeUnits);
    }
    name.add(0);
    final b = BytesBuilder();
    b.add([(id >> 8) & 0xff, id & 0xff, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00]);
    b.add(name);
    b.add([0x00, 0x01, 0x00, 0x01]);
    return b.toBytes();
  }

  /// [buildQuery] prefixed with the 2-byte TCP/DoT length.
  static Uint8List framedQuery(String domain) {
    final q = buildQuery(domain);
    final b = BytesBuilder();
    b.add([(q.length >> 8) & 0xff, q.length & 0xff]);
    b.add(q);
    return b.toBytes();
  }

}
