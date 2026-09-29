export 'package:karing/app/utils/singbox_dns.dart'
    show kDnsTagResolver, kDnsTagOutbound, kDnsTagDirect, kDnsTagProxy, kDnsTagBlock;

import 'dart:convert';
import 'dart:io';

import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/log.dart';
import 'package:tuple/tuple.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';

class CurrentServerForUrltestHistory {
  int delay = 0;
  String error = "";

  void clear() {
    delay = 0;
    error = "";
  }
}

class CurrentServerForUrltest {
  String now = "";
  CurrentServerForUrltestHistory history = CurrentServerForUrltestHistory();

  void clear() {
    now = "";
    history = CurrentServerForUrltestHistory();
  }
}

class DnsQueryResult {
  final String tag;
  final String json;
  DnsQueryResult(this.tag, this.json);
}

class RemoteRulesetState {
  String tag = "";
  int count = 0;
  String format = "";
  String type = "";
}

class ClashApi {
  static const String kScheme = "http";

  static Uri _uri(int port, String path, [Map<String, String>? query]) {
    final q = query == null ? null : Uri(queryParameters: query).query;
    return Uri.parse("$kScheme://127.0.0.1:$port$path${q == null || q.isEmpty ? '' : '?$q'}");
  }

  static Future<Map<String, dynamic>?> _getJson(int port, String path,
      {Map<String, String>? query, String? secret}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(_uri(port, path, query));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (secret != null && secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final res = await req.close();
      if (res.statusCode != 200) {
        client.close(force: true);
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (body.isEmpty) {
        return null;
      }
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Future<String> getSecret() async {
    return "";
  }

  static Future<ReturnResult<String>> getDelay(int port, String tag, int timeout,
      {String targetUrl = "https://www.gstatic.com/generate_204"}) async {
    try {
      // [timeout] is seconds (settings.urlTestTimeout); clash api wants ms.
      final timeoutMs = timeout * 1000;
      final client = HttpClient();
      client.connectionTimeout = Duration(milliseconds: timeoutMs + 3000);
      final uri = _uri(port, '/proxies/${Uri.encodeComponent(tag)}/delay',
          {'timeout': '$timeoutMs', 'url': targetUrl});
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      Log.w("getDelay uri=${uri.toString()} status=${res.statusCode} body=${body.length > 120 ? body.substring(0, 120) : body}");
      if (res.statusCode == 200) {
        final json = jsonDecode(body);
        final delay = json['delay'];
        return ReturnResult(data: delay?.toString() ?? "");
      }
      return ReturnResult(error: ReturnResultError(_errFromBody(body, res.statusCode)));
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<ReturnResult<HttpRequestResponse>> getHttpRequestByProxy(
      int port, String tag, String url) async {
    final result = HttpRequestResponse();
    try {
      final client = HttpClient();
      client.findProxy = (uri) => "PROXY 127.0.0.1:$port";
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      result.statusCode = res.statusCode;
      result.body = body;
      res.headers.forEach((name, values) {
        result.headers[name] = values.join(',');
      });
      return ReturnResult(data: result);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  /// Fetches [url] **through one named outbound**, via the core's
  /// `GET /proxies/{name}/http` endpoint.
  ///
  /// [getHttpRequestByProxy] cannot do this: it points an `HttpClient` at the
  /// mixed port, so the request is routed by the rules to whatever node happens
  /// to be *selected*. Every row of a per-node lookup therefore reported the same
  /// exit IP, and it only changed when the selection did. This asks the core to
  /// dial the named node instead.
  static Future<ReturnResult<HttpRequestResponse>> getHttpRequestByProxyTag(
    int controlPort,
    String tag,
    String url, {
    int timeoutMs = 5000,
  }) async {
    final result = HttpRequestResponse();
    try {
      final client = HttpClient();
      client.connectionTimeout = Duration(milliseconds: timeoutMs + 3000);
      final uri = _uri(controlPort, '/proxies/${Uri.encodeComponent(tag)}/http',
          {'timeout': '$timeoutMs', 'url': url});
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode != 200) {
        return ReturnResult(
          error: ReturnResultError(_errFromBody(body, res.statusCode)),
        );
      }
      final json = jsonDecode(body);
      result.statusCode = int.tryParse(json['status']?.toString() ?? '') ?? 0;
      result.body = json['body']?.toString() ?? '';
      return ReturnResult(data: result);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  /// queries the sing-box dns through the clash api compatible endpoint.
  /// [request] servers: list of SingboxDNSServerBatchOptions-like maps.
  static Future<ReturnResult<Tuple2<String, String>>> dnsQuery(
      int port, dynamic request) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      // our sing-box fork implements the karing POST /dns/query batch API
      final uri = _uri(port, '/dns/query');
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final payload = jsonEncode(request.toJson());
      Log.w("dnsQuery POST ${uri.toString()} payload=${payload.length > 200 ? payload.substring(0, 200) : payload}");
      // payload contains emoji node tags: must write UTF-8 bytes, not String
      req.add(utf8.encode(payload));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      Log.w("dnsQuery status=${res.statusCode} body=${body.length > 150 ? body.substring(0, 150) : body}");
      if (res.statusCode == 200) {
        return ReturnResult(data: Tuple2("dns", body));
      }
      return ReturnResult(error: ReturnResultError(_errFromBody(body, res.statusCode)));
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<ReturnResult<Tuple2<String, String>>> dnsQueryWithDefaultRouter(
      int port, String domain, String strategy) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final uri = _uri(port, '/dns/query', {
        'name': domain,
        if (strategy.isNotEmpty) 'strategy': strategy,
      });
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode == 200) {
        return ReturnResult(data: Tuple2("default", body));
      }
      return ReturnResult(error: ReturnResultError(_errFromBody(body, res.statusCode)));
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<ReturnResult<Tuple2<String, String>>> outboundQuery(
      int port, String domain, String ip) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(_uri(port, '/outbound/query'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode({
        'domain': domain,
        'ip': ip,
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode == 200) {
        return ReturnResult(data: Tuple2("outbound", body));
      }
      return ReturnResult(error: ReturnResultError(_errFromBody(body, res.statusCode)));
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<void> updateUrltestCheck(int port) async {
    // the karing fork of sing-box exposes /group updates via GET;
    // nothing to do for the stock clash api.
  }

  static Future<ReturnResult<CurrentServerForUrltest>> getCurrentServerForUrltest(
      String tag, int port) async {
    final result = CurrentServerForUrltest();
    final json = await _getJson(port, '/proxies/${Uri.encodeComponent(tag)}');
    if (json == null) {
      return ReturnResult(error: ReturnResultError("not found"));
    }
    result.now = json['now']?.toString() ?? "";
    final history = json['history'];
    if (history is List && history.isNotEmpty) {
      final last = history.last;
      if (last is Map) {
        result.history.delay = last['delay'] ?? 0;
      }
    }
    return ReturnResult(data: result);
  }

  static Future<String> getConnectionsUrl(int port,
      {bool noConnections = false}) async {
    if (noConnections) {
      return "";
    }
    return "ws://127.0.0.1:$port/connections";
  }

  /// GET /connections once and return a JSON body shaped like the app's
  /// Connections model. The clash REST snapshot lacks speeds and the start
  /// time, so speeds are diffed and startTime is injected by the caller.
  static Map<String, num>? lastTotals;
  static DateTime? _lastTotalsAt;
  static DateTime? connectionsStartTime;

  static void resetConnectionsStats() {
    lastTotals = null;
    _lastTotalsAt = null;
    connectionsStartTime = null;
  }

  static Future<String> getConnectionsViaHttp(int port) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(_uri(port, '/connections'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (body.isEmpty) {
        return "";
      }
      final json = jsonDecode(body);
      if (json is! Map) {
        return "";
      }
      final now = DateTime.now();
      num down = (json['downloadTotal'] as num?) ?? 0;
      num up = (json['uploadTotal'] as num?) ?? 0;
      num downSpeed = 0;
      num upSpeed = 0;
      if (lastTotals != null && _lastTotalsAt != null) {
        final dt = now.difference(_lastTotalsAt!).inMilliseconds / 1000.0;
        if (dt > 0.1 && dt < 10) {
          downSpeed = ((down - lastTotals!['down']!) / dt).round();
          upSpeed = ((up - lastTotals!['up']!) / dt).round();
          if (downSpeed < 0) downSpeed = 0;
          if (upSpeed < 0) upSpeed = 0;
        }
      }
      lastTotals = {'down': down, 'up': up};
      _lastTotalsAt = now;
      json['downloadSpeed'] = downSpeed;
      json['uploadSpeed'] = upSpeed;
      final connections = json['connections'];
      json['connectionsInCount'] =
          connections is List ? connections.length : 0;
      json['connectionsOutCount'] =
          connections is List ? connections.length : 0;
      final start = connectionsStartTime;
      if (start != null) {
        json['startTime'] = start.toIso8601String();
      }
      return jsonEncode(json);
    } catch (_) {
      return "";
    }
  }

  static Future<ReturnResult<String>> resetNetwork(int port) async {
    return ReturnResult<String>(data: "");
  }

  static Future<ReturnResult<String>> resetOutboundConnections(int port) async {
    try {
      final client = HttpClient();
      final req = await client.deleteUrl(_uri(port, '/connections'));
      final res = await req.close();
      await res.drain();
      client.close(force: true);
      return ReturnResult<String>(data: "");
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<ReturnResult<Tuple2<Map<String, DateTime>, Map<String, String>>>>
      getRemoteRulesetsStates(int port) async {
    final out = <RemoteRulesetState>[];
    final updatedAt = <String, DateTime>{};
    final errors = <String, String>{};
    final json = await _getJson(port, '/providers/rules');
    if (json == null) {
      return ReturnResult(error: ReturnResultError("not found"));
    }
    final providers = json['providers'];
    if (providers is Map) {
      providers.forEach((key, value) {
        if (value is Map) {
          final name = key.toString();
          final updatedAtStr = value['updatedAt']?.toString() ?? "";
          if (updatedAtStr.isNotEmpty) {
            final dt = DateTime.tryParse(updatedAtStr);
            if (dt != null) {
              updatedAt[name] = dt;
            }
          }
          final vehicleType = value['vehicleType']?.toString() ?? "";
          if (vehicleType.toLowerCase() == 'http') {
            errors[name] = value['errorMessage']?.toString() ?? "";
          }
        }
      });
    }
    return ReturnResult(data: Tuple2(updatedAt, errors));
  }

  static Future<ReturnResult<Map<String, int>>> getRemoteRulesetsCount(
      int port) async {
    final states = await getRemoteRulesetsStates(port);
    if (states.error != null) {
      return ReturnResult(error: states.error);
    }
    final out = <String, int>{};
    states.data!.item2.forEach((key, value) {
      out[key] = value.isEmpty ? 0 : 1;
    });
    return ReturnResult(data: out);
  }

  static Future<ReturnResult<Tuple2<String, String>>> getGroupDelayHistory(
      int port) async {
    final out = <String, List<int>>{};
    final json = await _getJson(port, '/proxies');
    if (json == null) {
      return ReturnResult(error: ReturnResultError("not found"));
    }
    final proxies = json['proxies'];
    if (proxies is Map) {
      proxies.forEach((key, value) {
        if (value is Map) {
          final history = value['history'];
          if (history is List) {
            out[key.toString()] =
                history.map((e) => (e is Map ? e['delay'] ?? 0 : 0) as int).toList();
          }
        }
      });
    }
    return ReturnResult(data: Tuple2("history", jsonEncode(out)));
  }

  static Future<String> getLogsUrl(int port, [String level = 'info']) async {
    return "ws://127.0.0.1:$port/logs?level=$level";
  }

  static String _errFromBody(String body, int statusCode) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['message'] != null) {
        return json['message'].toString();
      }
    } catch (_) {}
    return "http $statusCode";
  }
}

class DNSQueryResponse {
  String? err;
  int latency = 0;

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    final e = map['err']?.toString();
    err = (e == null || e.isEmpty) ? null : e;
    latency = map['latency'] ?? 0;
  }
}