// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/clash_api.dart';

/// Dials raw TCP connections on the "real direct path":
/// - VPN off  -> plain socket, exactly like before.
/// - VPN on   -> CONNECT through the loopback `scan-in` mixed inbound, whose
///   traffic the core routes straight to its direct outbound (physical NIC),
///   so probes are never taken through the tunnel / FakeIP / proxy chain.
class ScanDialer {
  /// Returns the scan inbound port while the VPN core is running, else 0.
  static Future<int> scanPort() async {
    final port = SettingManager.getConfig().proxy.scanPort;
    if (port <= 0) {
      return 0;
    }
    if (!await VPNService.getStarted()) {
      return 0;
    }
    return port;
  }

  /// Polls until the core's control API answers (startup can take a few
  /// seconds). Returns false when it never came up within [timeout].
  static Future<bool> waitCoreReady({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!await VPNService.getStarted()) {
      return false;
    }
    final port = SettingManager.getConfig().proxy.controlPort;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 1);
      try {
        final req = await client
            .headUrl(Uri.parse("http://127.0.0.1:$port/version"))
            .timeout(const Duration(seconds: 2));
        await req.close().timeout(const Duration(seconds: 2));
        client.close(force: true);
        return true;
      } catch (_) {
        client.close(force: true);
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  /// Resolves [host] on the direct path: through the core's DNS (direct
  /// detour, bypassing FakeIP) while the VPN is running, via the system
  /// resolver otherwise. Returns the real addresses, never FakeIPs.
  static Future<List<InternetAddress>> resolve(String host) async {
    if (host.isEmpty || InternetAddress.tryParse(host) != null) {
      return [];
    }
    if (!await VPNService.getStarted()) {
      try {
        return await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        return [];
      }
    }
    try {
      final port = SettingManager.getConfig().proxy.controlPort;
      final strategy = SettingManager.getConfig().ipStrategy.name;
      final result = await ClashApi.dnsQueryWithDefaultRouter(
        port,
        host,
        strategy,
      );
      if (result.error != null) {
        return [];
      }
      final json = jsonDecode(result.data!.item2);
      final addrs = json["addr"];
      if (addrs is! List) {
        return [];
      }
      final out = <InternetAddress>[];
      for (final a in addrs) {
        final addr = InternetAddress.tryParse(a.toString());
        if (addr != null) {
          out.add(addr);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Opens a raw TCP connection to [host]:[port] on the direct path.
  static Future<Socket> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final scan = await scanPort();
    if (scan <= 0) {
      return Socket.connect(host, port, timeout: timeout);
    }
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      scan,
      timeout: timeout,
    );
    try {
      // HTTP CONNECT as any HTTP(S) proxy client would send.
      final target = host.contains(":") ? "[$host]:$port" : "$host:$port";
      socket.add(
        "CONNECT $target HTTP/1.1\r\n"
        "Host: $target\r\n"
        "\r\n"
            .codeUnits,
      );
      final status = await _readConnectStatus(socket, timeout);
      if (status != 200) {
        socket.destroy();
        throw SocketException(
          "scan channel CONNECT failed (HTTP $status)",
        );
      }
      return socket;
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  static Future<int> _readConnectStatus(Socket socket, Duration timeout) async {
    final buf = <int>[];
    final done = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = socket.listen(
      (data) {
        buf.addAll(data);
        // header end reached?
        for (int i = 0; i + 3 < buf.length; i++) {
          if (buf[i] == 13 && buf[i + 1] == 10 && buf[i + 2] == 13 && buf[i + 3] == 10) {
            if (!done.isCompleted) {
              done.complete();
            }
            // release the stream: the caller upgrades this socket to TLS
            sub.cancel();
            return;
          }
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
    } catch (_) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    final text = String.fromCharCodes(buf);
    final match = RegExp(r'HTTP/1\.[01] (\d{3})').firstMatch(text);
    return match == null ? 0 : int.parse(match.group(1)!);
  }
}
