// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:io';

/// Result of probing one (ip, sni) pair.
class SniScanResult {
  final String ip;
  final String sni;
  final int latencyMs;
  final bool ok;
  final String error;
  final String tlsVersion;
  final String alpn;

  SniScanResult({
    required this.ip,
    required this.sni,
    required this.latencyMs,
    required this.ok,
    this.error = "",
    this.tlsVersion = "",
    this.alpn = "",
  });
}

/// Scans (clean IP, fake SNI) pairs the same way patterniha/SNI-Spoofing and
/// the SNI-Finder family do: open a TCP connection to the IP, complete a TLS
/// handshake presenting the candidate SNI, and time it. A pair is usable when
/// the handshake completes without the middlebox resetting the connection.
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

  /// Probes one pair. [timeout] covers connect + handshake.
  Future<SniScanResult> probe(
    String ip,
    String sni, {
    int port = 443,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    SecureSocket? socket;
    try {
      final raw = await Socket.connect(ip, port, timeout: timeout);
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
      final proto = socket.selectedProtocol ?? "";
      await socket.close();
      socket.destroy();
      return SniScanResult(
        ip: ip,
        sni: sni,
        latencyMs: sw.elapsedMilliseconds,
        ok: true,
        alpn: proto,
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
  /// streaming every result through [onResult]. Returns the successful pairs
  /// sorted by latency.
  Future<List<SniScanResult>> scan({
    required List<String> ips,
    required List<String> snis,
    int port = 443,
    int concurrency = 16,
    Duration timeout = const Duration(seconds: 5),
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
    results.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    return results;
  }
}
