// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:karing/app/utils/cloudflare_utils.dart';
import 'package:karing/app/utils/scan_dialer.dart';

/// Result of probing one (ip, sni) pair.
class SniScanResult {
  final String ip;
  final String sni;
  final int latencyMs;
  final bool ok;

  /// True when the pair was positively confirmed.
  ///
  /// - Trace mode: the peer answered `/cdn-cgi/trace`, so it is a live
  ///   Cloudflare edge rather than merely some host that completed a TLS
  ///   handshake.
  /// - Template mode: the full request path (TLS with the fake SNI, then the
  ///   real domain in the Host header) succeeded through this IP.
  final bool verified;

  /// Cloudflare colo, trace mode only.
  final String colo;

  /// HTTP status of the template probe, 0 when none was received.
  final int status;
  final String error;

  SniScanResult({
    required this.ip,
    required this.sni,
    required this.latencyMs,
    required this.ok,
    this.verified = false,
    this.colo = "",
    this.status = 0,
    this.error = "",
  });

  /// Coarse bucket for a failure, so the UI can explain *why* nothing worked
  /// (ISP reset vs. timeout vs. simply unreachable) instead of leaving the
  /// user with an empty list and no diagnosis.
  String get failureReason {
    if (ok) {
      return "";
    }
    final e = error.toLowerCase();
    if (e.contains("timeout") || e.contains("timed out")) {
      return "timeout";
    }
    if (e.contains("reset") || e.contains("closed") || e.contains("eof")) {
      return "reset";
    }
    if (e.contains("handshake") ||
        e.contains("tls") ||
        e.contains("certificate")) {
      return "handshake";
    }
    return "unreachable";
  }
}

/// The parts of a real node that decide whether a clean IP is usable with it.
///
/// SNI spoofing rewrites a CDN outbound to dial a clean IP while presenting a
/// whitelisted fake SNI, keeping the real domain in the transport `Host`
/// header. Verifying a candidate IP therefore means replaying exactly that:
/// TLS with the fake SNI, then an HTTP request carrying [host].
class SniTemplate {
  /// Real domain — goes in the Host header, and is what the CDN routes on.
  final String host;

  /// Transport path (`/dl`, `/ws`, …).
  final String path;

  /// Transport type: `ws`, `grpc`, `httpupgrade`, `http`, or empty.
  final String transportType;

  SniTemplate({
    required this.host,
    this.path = "/",
    this.transportType = "",
  });
}

/// Scans (clean IP, fake SNI) pairs the way patterniha/SNI-Spoofing and the
/// SNI-Finder family do: open a TCP connection to the IP, present the candidate
/// SNI, and find out whether the pair is actually usable.
///
/// Two modes:
/// - **trace** (default): confirm the peer is a live Cloudflare edge.
/// - **template**: replay the selected node's real request through the
///   candidate IP, which validates TLS, Host-header routing and the transport
///   in one go. This is what cfray and CFScanner do, and it is the only way to
///   know an IP works *for your node* rather than in the abstract.
class SniScanner {
  /// Fake-SNI candidates known to pass Iranian DPI whitelists
  /// (Patt's channel + community lists).
  static const List<String> defaultSniCandidates = [
    "chatgpt.com",
    "auth.vercel.com",
    "www.speedtest.net",
    "zula.ir",
    "www.digikala.com",
    "cdn.jsdelivr.net",
    "www.wikipedia.org",
    "www.cloudflare.com",
    "discord.com",
    "www.icloud.com",
  ];

  /// Clean edge IPs from Patt's Irancell post plus common CF anycast edges.
  static const List<String> defaultIps = [
    "199.181.197.1",
    "103.160.204.34",
    "185.193.30.94",
    "45.8.211.57",
    "159.112.235.52",
    "170.114.45.239",
    "188.42.88.24",
    "88.216.67.230",
    "45.130.125.75",
    "104.21.33.59",
    "188.114.96.0",
    "188.114.97.6",
  ];

  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get cancelled => _cancelled;

  /// Ordering for the result list: verified pairs first — only a confirmed
  /// edge can serve the real domain carried in the transport Host header —
  /// then fastest first.
  static int compare(SniScanResult a, SniScanResult b) {
    if (a.verified != b.verified) {
      return a.verified ? -1 : 1;
    }
    return a.latencyMs.compareTo(b.latencyMs);
  }

  /// HTTP status from a response head, 0 when there is no status line.
  /// Exposed for testing: a parsing slip here would misjudge every IP.
  static int httpStatusOf(String head) {
    final match = RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(head);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  /// Cloudflare serves an "error code: 10xx" page when the edge cannot resolve
  /// the requested zone (1016 origin DNS error, 1014 CNAME cross-user ban,
  /// 1003 direct IP access, 1001/1000 DNS points to a prohibited IP). Those
  /// pages look like a normal HTTP response, so without this check a dead IP
  /// would be recommended as working.
  static bool isCloudflareZoneError(String head) {
    for (final code in const ["1016", "1014", "1003", "1001", "1000"]) {
      if (head.contains("error code: $code")) {
        return true;
      }
    }
    return false;
  }

  /// Probes one pair. [timeout] covers connect + handshake + verification.
  /// The connection is made on the direct path (see ScanDialer): through the
  /// core's scan channel while the VPN is running, plain otherwise.
  ///
  /// A bare TLS handshake is not evidence enough: `onBadCertificate` accepts
  /// any certificate, so *any* TLS server that answered the SNI looked like a
  /// hit even though it could never serve the real domain. Both modes below
  /// therefore verify something real instead of the handshake alone.
  Future<SniScanResult> probe(
    String ip,
    String sni, {
    int port = 443,
    Duration timeout = const Duration(seconds: 5),
    SniTemplate? template,
  }) async {
    if (template != null) {
      return _probeTemplate(ip, sni, template, port: port, timeout: timeout);
    }
    if (port != 443) {
      // /cdn-cgi/trace is only served on 443.
      return _probeHandshake(ip, sni, port: port, timeout: timeout);
    }
    final trace = await cfProbeTrace(ip, probeHost: sni, timeout: timeout);
    if (trace.ok) {
      return SniScanResult(
        ip: ip,
        sni: sni,
        latencyMs: trace.latencyMs,
        ok: true,
        verified: true,
        colo: trace.colo ?? "",
      );
    }
    if (trace.totalMs > 0) {
      // TLS completed (totalMs is the handshake time) but the peer is not a
      // Cloudflare edge.
      return SniScanResult(
        ip: ip,
        sni: sni,
        latencyMs: trace.totalMs,
        ok: true,
      );
    }
    return SniScanResult(
      ip: ip,
      sni: sni,
      latencyMs: trace.latencyMs,
      ok: false,
      error: trace.error,
    );
  }

  /// Replays the node's real request through [ip] with [sni] presented.
  ///
  /// A Cloudflare edge answers `101 Switching Protocols` when the WebSocket
  /// upgrade reaches a live worker, which is the strongest possible signal
  /// that this IP works for this node. Any other HTTP status means the request
  /// was routed somewhere real; the Cloudflare "error code: 10xx" pages mean
  /// the edge does not know the domain at all, and 5xx means the worker behind
  /// it is broken.
  Future<SniScanResult> _probeTemplate(
    String ip,
    String sni,
    SniTemplate template, {
    required int port,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    SecureSocket? socket;
    try {
      final raw = await ScanDialer.connect(ip, port, timeout: timeout);
      try {
        socket = await SecureSocket.secure(
          raw,
          host: sni,
          onBadCertificate: (_) => true,
          // HTTP/1.1 only: the request below is HTTP/1.1 text, so negotiating
          // h2 would make the server answer with binary frames.
          supportedProtocols: const ["http/1.1"],
        ).timeout(timeout);
      } catch (err) {
        raw.destroy();
        rethrow;
      }

      final path = template.path.isEmpty ? "/" : template.path;
      final req = StringBuffer()
        ..write("GET $path HTTP/1.1\r\n")
        // The real domain, exactly as _applySniSpoofing places it.
        ..write("Host: ${template.host}\r\n")
        ..write("User-Agent: karing-sni-probe\r\n")
        ..write("Accept: */*\r\n");
      if (template.transportType == "ws") {
        req
          ..write("Upgrade: websocket\r\n")
          ..write("Connection: Upgrade\r\n")
          ..write("Sec-WebSocket-Version: 13\r\n")
          ..write("Sec-WebSocket-Key: ${_webSocketKey()}\r\n");
      } else {
        req.write("Connection: close\r\n");
      }
      req.write("\r\n");
      socket.add(req.toString().codeUnits);

      final head = await _readHead(socket, timeout);
      sw.stop();
      try {
        await socket.close();
        socket.destroy();
      } catch (_) {}

      final status = httpStatusOf(head);
      if (status == 0) {
        return SniScanResult(
          ip: ip,
          sni: sni,
          latencyMs: sw.elapsedMilliseconds,
          ok: false,
          error: "no HTTP response",
        );
      }
      if (isCloudflareZoneError(head)) {
        return SniScanResult(
          ip: ip,
          sni: sni,
          latencyMs: sw.elapsedMilliseconds,
          ok: false,
          status: status,
          error: "edge does not serve ${template.host}",
        );
      }
      if (status >= 500) {
        return SniScanResult(
          ip: ip,
          sni: sni,
          latencyMs: sw.elapsedMilliseconds,
          ok: false,
          status: status,
          error: "origin returned $status",
        );
      }
      return SniScanResult(
        ip: ip,
        sni: sni,
        latencyMs: sw.elapsedMilliseconds,
        ok: true,
        verified: true,
        status: status,
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
      return SniScanResult(
        ip: ip,
        sni: sni,
        latencyMs: sw.elapsedMilliseconds,
        ok: false,
        error: msg,
      );
    }
  }

  /// Handshake-only probe, kept for non-443 ports where the trace endpoint
  /// does not exist.
  Future<SniScanResult> _probeHandshake(
    String ip,
    String sni, {
    required int port,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    SecureSocket? socket;
    try {
      final raw = await ScanDialer.connect(ip, port, timeout: timeout);
      try {
        socket = await SecureSocket.secure(
          raw,
          host: sni,
          onBadCertificate: (_) => true,
          supportedProtocols: const ["h2", "http/1.1"],
        ).timeout(timeout);
      } catch (err) {
        raw.destroy();
        rethrow;
      }
      sw.stop();
      await socket.close();
      socket.destroy();
      return SniScanResult(
        ip: ip,
        sni: sni,
        latencyMs: sw.elapsedMilliseconds,
        ok: true,
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
      return SniScanResult(
        ip: ip,
        sni: sni,
        latencyMs: sw.elapsedMilliseconds,
        ok: false,
        error: msg,
      );
    }
  }

  /// Scans the cartesian product of [ips] x [snis] with bounded concurrency,
  /// streaming every result through [onResult]. Returns the successful pairs,
  /// verified ones first, then by latency.
  Future<List<SniScanResult>> scan({
    required List<String> ips,
    required List<String> snis,
    int port = 443,
    int concurrency = 16,
    Duration timeout = const Duration(seconds: 5),
    SniTemplate? template,
    void Function(SniScanResult result, int done, int total)? onResult,
  }) async {
    _cancelled = false;
    final pairs = <List<String>>[];
    for (final ip in ips) {
      for (final sni in snis) {
        pairs.add([ip, sni]);
      }
    }
    final total = pairs.length;
    final results = <SniScanResult>[];
    int done = 0;
    int index = 0;

    Future<void> worker() async {
      while (!_cancelled) {
        final int current;
        if (index >= pairs.length) {
          return;
        }
        current = index++;
        final pair = pairs[current];
        final result = await probe(
          pair[0],
          pair[1],
          port: port,
          timeout: timeout,
          template: template,
        );
        done++;
        if (result.ok) {
          results.add(result);
        }
        onResult?.call(result, done, total);
      }
    }

    final workers = <Future<void>>[];
    for (int i = 0; i < concurrency && i < pairs.length; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
    results.sort(compare);
    return results;
  }
}

String _webSocketKey() {
  final rnd = Random();
  return base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
}

/// Reads until the response headers are complete. The body is irrelevant for
/// a reachability verdict and can be large, so the read stops at the first
/// blank line.
Future<String> _readHead(SecureSocket socket, Duration timeout) async {
  final buf = <int>[];
  final done = Completer<void>();
  late final StreamSubscription<List<int>> sub;
  sub = socket.listen(
    (data) {
      buf.addAll(data);
      if (!done.isCompleted &&
          (String.fromCharCodes(buf).contains("\r\n\r\n") ||
              buf.length > 8192)) {
        done.complete();
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
  try {
    await done.future.timeout(timeout);
  } catch (_) {}
  try {
    await sub.cancel();
  } catch (_) {}
  return String.fromCharCodes(buf);
}
