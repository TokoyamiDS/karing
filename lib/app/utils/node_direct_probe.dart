// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:io';

import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/scan_dialer.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// Result of one direct node probe (no core, no VPN, no system proxy/TUN).
class NodeDirectProbeResult {
  final ProxyConfig server;
  final int latencyMs;
  final bool ok;
  final String error;

  NodeDirectProbeResult({
    required this.server,
    required this.latencyMs,
    required this.ok,
    this.error = "",
  });
}

/// Latency-tests proxy nodes without the core: TCP-connect to server:port
/// on the physical NIC via [ScanDialer], plus a TLS handshake for
/// TLS-based protocols (trojan/vless/vmess+tls/ss+tls/hysteria2/tuic).
/// Results use the same latency/error contract as the clash-API path so the
/// existing lists repaint unchanged. Never starts the VPN, never touches
/// system proxy or TUN routes.
class NodeDirectProbe {
  static bool _cancelled = false;
  static void cancel() => _cancelled = true;
  static bool get cancelled => _cancelled;

  /// One batch at a time: probing several groups/subscriptions at once must
  /// not open a socket storm on the physical NIC.
  static Future<void> _tail = Future<void>.value();

  /// Probes every node of [group], streaming results through [onResult].
  static Future<List<NodeDirectProbeResult>> probeGroup(
    ServerConfigGroupItem group, {
    Duration timeout = const Duration(seconds: 8),
    void Function(NodeDirectProbeResult result, int done, int total)? onResult,
  }) {
    return probeServers(
      group.servers.where((s) => s.type == kOutboundTypeServer).toList(),
      timeout: timeout,
      onResult: onResult,
    );
  }

  /// Probes [servers], streaming results through [onResult]. Batches run one
  /// at a time; inside a batch concurrency is bounded by
  /// settings.latencyCheckConcurrency.
  static Future<List<NodeDirectProbeResult>> probeServers(
    List<ProxyConfig> servers, {
    Duration timeout = const Duration(seconds: 8),
    void Function(NodeDirectProbeResult result, int done, int total)? onResult,
  }) {
    final run = _tail.then((_) => _probeBatch(servers, timeout, onResult));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  static Future<List<NodeDirectProbeResult>> _probeBatch(
    List<ProxyConfig> servers,
    Duration timeout,
    void Function(NodeDirectProbeResult result, int done, int total)? onResult,
  ) async {
    _cancelled = false;
    final total = servers.length;
    final results = <NodeDirectProbeResult>[];
    var done = 0;
    var index = 0;
    final maxConc = SettingManager.getConfig().latencyCheckConcurrency;
    final conc = maxConc <= 0 ? 4 : maxConc.clamp(1, 16);
    Future<void> worker() async {
      while (!_cancelled) {
        if (index >= servers.length) return;
        final s = servers[index++];
        final r = await probe(s, timeout: timeout);
        done++;
        if (r.error != "unsupported") {
          if (r.ok) {
            ServerManager.updateByDelay(r.latencyMs.toString(), s);
          } else {
            ServerManager.updateByDelayResult({"err": r.error}, s);
          }
        }
        results.add(r);
        onResult?.call(r, done, total);
      }
    }
    final workers = <Future<void>>[];
    for (var i = 0; i < conc && i < servers.length; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
    await ServerManager.saveServerConfig();
    return results;
  }

  /// Probes a single node: TCP connect, then TLS handshake when the built
  /// outbound carries a tls section.
  static Future<NodeDirectProbeResult> probe(
    ProxyConfig server, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final ob = SingboxConfigBuilder.buildOutbound(server);
      String host = server.server;
      int port = server.serverport;
      String obType = "";
      Map<String, dynamic>? tls;
      if (ob is Map) {
        obType = (ob['type'] ?? "").toString();
        if (ob['server'] is String && (ob['server'] as String).isNotEmpty) {
          host = ob['server'];
        }
        if (ob['server_port'] is int && (ob['server_port'] as int) > 0) {
          port = ob['server_port'];
        }
        if (ob['tls'] is Map) tls = Map<String, dynamic>.from(ob['tls']);
      }
      if (const {"hysteria", "hysteria2", "tuic", "wireguard"}.contains(obType)) {
        // QUIC/UDP-only nodes cannot be measured over a TCP socket; report
        // "unsupported" so probeGroup keeps the last core-measured latency
        // instead of writing a false failure.
        return NodeDirectProbeResult(
            server: server, latencyMs: 0, ok: false, error: "unsupported");
      }
      if (host.isEmpty || port <= 0) {
        return NodeDirectProbeResult(
            server: server,
            latencyMs: sw.elapsedMilliseconds,
            ok: false,
            error: "invalid server");
      }
      final raw = await ScanDialer.connect(host, port, timeout: timeout);
      final tcpMs = sw.elapsedMilliseconds;
      if (tls == null || tls['enabled'] != true) {
        raw.destroy();
        sw.stop();
        return NodeDirectProbeResult(
            server: server, latencyMs: tcpMs, ok: true);
      }
      final sni = (tls['server_name'] ?? "").toString();
      SecureSocket? socket;
      try {
        socket = await SecureSocket.secure(
          raw,
          host: sni.isNotEmpty ? sni : host,
          onBadCertificate: (_) => true,
          supportedProtocols: const ["h2", "http/1.1"],
        ).timeout(timeout);
      } catch (_) {
        // Handshake refused (REALITY fingerprint, ALPN pinning, mTLS...): the
        // port is reachable, so report the TCP RTT rather than a false "down".
        raw.destroy();
        sw.stop();
        return NodeDirectProbeResult(
            server: server, latencyMs: tcpMs, ok: true);
      }
      sw.stop();
      await socket.close();
      socket.destroy();
      return NodeDirectProbeResult(
          server: server, latencyMs: sw.elapsedMilliseconds, ok: true);
    } catch (err) {
      sw.stop();
      if (err is TimeoutException) {
        return NodeDirectProbeResult(
            server: server,
            latencyMs: sw.elapsedMilliseconds,
            ok: false,
            error: "connectTimeout");
      }
      var msg = err.toString();
      msg = msg.replaceFirst("SocketException: ", "");
      final nl = msg.indexOf("\n");
      if (nl > 0) msg = msg.substring(0, nl);
      if (msg.length > 100) msg = msg.substring(0, 100);
      if (msg.contains("exceeded") || msg.contains("timed out")) {
        msg = "connectTimeout";
      }
      return NodeDirectProbeResult(
          server: server,
          latencyMs: sw.elapsedMilliseconds,
          ok: false,
          error: msg.isEmpty ? "failed" : msg);
    }
  }
}
