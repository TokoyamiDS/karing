import 'dart:async';
import 'dart:convert';

import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/modules/statistics_manager.dart';
import 'package:karing/app/utils/clash_api.dart';

/// Accumulates traffic into [StatisticsManager] while the VPN is connected.
///
/// The core's `/connections` endpoint reports only the connections that are
/// open *right now*, and their byte counts are cumulative for the life of each
/// connection. So recording means polling, remembering the last byte count seen
/// per connection, and adding the difference. Without that diff, every poll
/// would re-add the whole total and the history would grow far too fast.
///
/// Polling also means short-lived connections can be missed entirely — a
/// connection that opens and closes between two polls leaves no trace. The
/// interval is the accuracy/cost trade-off; see [_interval].
class StatisticsRecorder {
  /// Two seconds: the app already polls `/connections` at 1 Hz while the
  /// Connections screen is open, so this is cheaper than that, and short
  /// enough that ordinary request/response traffic is caught. Lowering it
  /// trades CPU for catching very short connections.
  static const Duration _interval = Duration(seconds: 2);

  /// How often the retention limits are enforced. Pruning runs a VACUUM when
  /// the size cap bites, which is far too expensive to do on every poll.
  static const Duration _pruneInterval = Duration(minutes: 5);

  static Timer? _timer;
  static bool _polling = false;
  static DateTime? _lastPrune;

  /// Per-connection byte counts as of the previous poll, so the next poll can
  /// add only the increment. Keyed by the core's connection id.
  static final Map<String, (int upload, int download)> _lastSeen = {};

  static bool get isRunning => _timer != null;

  static void start(int controlPort) {
    if (_timer != null) {
      return;
    }
    _lastSeen.clear();
    _timer = Timer.periodic(_interval, (_) => pollOnce(controlPort));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    // A reconnect gets fresh connection ids, but clearing removes any chance of
    // a reused id being diffed against a stale count from the previous session.
    _lastSeen.clear();
    _lastPrune = null;
  }

  /// One poll. Public so a test can drive it without a timer.
  static Future<void> pollOnce(int controlPort) async {
    final statistics = SettingManager.getConfig().statistics;
    if (!statistics.enable || _polling) {
      return;
    }
    _polling = true;
    try {
      final body = await ClashApi.getConnectionsViaHttp(controlPort);
      if (body.isEmpty) {
        return;
      }
      final json = jsonDecode(body);
      if (json is! Map) {
        return;
      }
      final connections = json['connections'];
      if (connections is! List) {
        return;
      }

      final now = DateTime.now();
      final seenIds = <String>{};
      for (final raw in connections) {
        if (raw is! Map) {
          continue;
        }
        final id = raw['id']?.toString() ?? "";
        if (id.isEmpty) {
          continue;
        }
        seenIds.add(id);

        final upload = (raw['upload'] as num?)?.toInt() ?? 0;
        final download = (raw['download'] as num?)?.toInt() ?? 0;
        final previous = _lastSeen[id];
        _lastSeen[id] = (upload, download);
        if (previous == null) {
          // First sighting of this connection: everything reported so far
          // happened since it opened, so all of it is new.
          _record(raw, now, upload, download, statistics);
          continue;
        }
        final uploadDelta = upload - previous.$1;
        final downloadDelta = download - previous.$2;
        if (uploadDelta > 0 || downloadDelta > 0) {
          _record(raw, now, uploadDelta, downloadDelta, statistics);
        }
      }

      // Forget closed connections so the map cannot grow without bound.
      _lastSeen.removeWhere((id, _) => !seenIds.contains(id));
      _pruneIfDue(now, statistics);
    } catch (_) {
      // Statistics must never take the app down: a malformed body or a core
      // that restarted mid-poll just means this sample is lost.
    } finally {
      _polling = false;
    }
  }

  static void _record(
    Map raw,
    DateTime now,
    int uploadDelta,
    int downloadDelta,
    SettingConfigItemStatistics statistics,
  ) {
    final metadata = raw['metadata'];
    final map = metadata is Map ? metadata : const {};
    // `host` is the domain the client asked for; it is empty for connections
    // made straight to an IP, where the address is the only identity available.
    final host = (map['host']?.toString().isNotEmpty ?? false)
        ? map['host'].toString()
        : (map['destinationIP']?.toString() ?? "");
    final chains = raw['chains'];
    final outbound = (chains is List && chains.isNotEmpty)
        ? chains.first.toString()
        : "";

    StatisticsManager.add(
      time: now,
      host: StatisticsManager.desensitizeHost(host, statistics.dataDesensitize),
      process: StatisticsManager.processName(
        map['processPath']?.toString() ?? "",
      ),
      outbound: outbound,
      uploadDelta: uploadDelta,
      downloadDelta: downloadDelta,
    );
  }

  static void _pruneIfDue(DateTime now, SettingConfigItemStatistics statistics) {
    final last = _lastPrune;
    if (last != null && now.difference(last) < _pruneInterval) {
      return;
    }
    _lastPrune = now;
    StatisticsManager.prune(
      cacheDays: statistics.cacheDays,
      cacheSizeLimitMB: statistics.cacheSizeLimitMB,
    );
  }
}
