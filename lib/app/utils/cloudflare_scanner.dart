import 'dart:math';

import 'package:karing/app/utils/cloudflare_utils.dart';

/// Result of probing one candidate Cloudflare edge IP.
class CfScanResult {
  final String ip;
  final int latencyMs;
  final bool ok;
  final String? colo;
  final String? exitIp;
  final String error;

  CfScanResult({
    required this.ip,
    required this.latencyMs,
    required this.ok,
    this.colo,
    this.exitIp,
    this.error = "",
  });
}

/// Scans random IPs sampled across the official Cloudflare ranges the way
/// clean-IP scanners (mlmvpn & co.) do: TLS :443 handshake timed, then a
/// /cdn-cgi/trace request to confirm the IP really is a live Cloudflare
/// edge. Only verified edges are reported as healthy.
class CloudflareScanner {
  static const String defaultProbeHost = "speed.cloudflare.com";

  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get cancelled => _cancelled;

  /// Generates [count] unique candidate IPs spread over all CF ranges.
  static List<String> generateCandidates(int count, {int? seed}) {
    final ips = CloudflareRanges.sampleIps(count, seed: seed);
    ips.shuffle(seed == null ? Random() : Random(seed));
    return ips;
  }

  Future<CfScanResult> probe(
    String ip, {
    String probeHost = defaultProbeHost,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final r = await cfProbeTrace(
      ip,
      probeHost: probeHost,
      timeout: timeout,
    );
    return CfScanResult(
      ip: ip,
      latencyMs: r.latencyMs,
      ok: r.ok,
      colo: r.colo,
      exitIp: r.exitIp,
      error: r.error,
    );
  }

  /// Probes [ips] with bounded concurrency, streaming every result through
  /// [onResult]. Returns the healthy edges sorted by latency.
  Future<List<CfScanResult>> scan({
    required List<String> ips,
    String probeHost = defaultProbeHost,
    int concurrency = 24,
    Duration timeout = const Duration(seconds: 5),
    void Function(CfScanResult result, int done, int total)? onResult,
  }) async {
    _cancelled = false;
    final total = ips.length;
    final results = <CfScanResult>[];
    int done = 0;
    int index = 0;

    Future<void> worker() async {
      while (!_cancelled) {
        final int current;
        if (index >= ips.length) {
          return;
        }
        current = index++;
        final result = await probe(
          ips[current],
          probeHost: probeHost,
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
    for (int i = 0; i < concurrency && i < ips.length; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
    results.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    return results;
  }
}
