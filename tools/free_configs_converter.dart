import 'dart:convert';
import 'dart:io';

const String kDefaultUrl =
    'https://raw.githubusercontent.com/patterniha/Free-Configs/main/configs.txt';

Future<void> main(List<String> args) async {
  String? input;
  String outdir = 'out';
  bool singbox = true;
  for (final a in args) {
    if (a.startsWith('--input=')) {
      input = a.substring(8);
    } else if (a.startsWith('--outdir=')) {
      outdir = a.substring(9);
    } else if (a == '--no-singbox') {
      singbox = false;
    } else if (a == '--help' || a == '-h') {
      _usage();
      return;
    } else {
      input = a;
    }
  }

  String body;
  if (input == null || input.startsWith('http://') || input.startsWith('https://')) {
    final url = input ?? kDefaultUrl;
    stdout.writeln('Fetching $url');
    body = await _httpGet(url);
  } else {
    body = await File(input).readAsString();
  }

  body = _maybeDecodeBase64Subscription(body);
  final lines = body
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('//'))
      .toList();

  final cleaned = <String>[];
  final outbounds = <Map<String, dynamic>>[];
  int parsed = 0;
  int failed = 0;

  for (final line in lines) {
    try {
      final link = _cleanLink(line);
      if (link == null) {
        cleaned.add(line);
        continue;
      }
      parsed++;
      if (link.$1.isNotEmpty && !cleaned.contains(link.$1)) {
        cleaned.add(link.$1);
      }
      if (link.$2 != null && singbox) {
        outbounds.add(link.$2!);
      }
    } catch (_) {
      failed++;
      cleaned.add(line);
    }
  }

  final dedup = _dedupLinks(cleaned);
  final dir = Directory(outdir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final linksFile = File('$outdir/karing_links.txt');
  await linksFile.writeAsString(dedup.join('\n'));

  stdout.writeln('Parsed: $parsed  Passed-through: ${lines.length - parsed}  Failed: $failed');
  stdout.writeln('Unique links: ${dedup.length}');
  stdout.writeln('Outbounds: ${outbounds.length}');
  stdout.writeln('Wrote ${linksFile.path}');

  if (singbox && outbounds.isNotEmpty) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    int i = 1;
    for (final ob in outbounds) {
      final key = '${ob['type']}|${ob['server']}|${ob['server_port']}|'
          '${ob['uuid'] ?? ob['password'] ?? ''}|${jsonEncode(ob['transport'] ?? {})}';
      if (seen.contains(key)) continue;
      seen.add(key);
      ob['tag'] = 'patt-${i.toString().padLeft(2, '0')}';
      i++;
      unique.add(ob);
    }
    final sb = <String, dynamic>{
      'outbounds': unique,
    };
    final sbFile = File('$outdir/singbox_subscription.json');
    await sbFile.writeAsString(const JsonEncoder.withIndent('  ').convert(sb));
    stdout.writeln('Wrote ${sbFile.path} (${unique.length} outbounds)');
  }
}

void _usage() {
  stdout.writeln('Usage: dart run tools/free_configs_converter.dart [--input=<file|url>] [--outdir=out] [--no-singbox]');
  stdout.writeln('Default input: $kDefaultUrl');
}

Future<String> _httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, 'karing-iran-converter');
    final res = await req.close();
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} for $url');
    }
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

String _maybeDecodeBase64Subscription(String body) {
  if (body.contains('://')) return body;
  final compact = body.replaceAll(RegExp(r'\s'), '');
  if (compact.isEmpty) return body;
  try {
    final decoded = utf8.decode(base64.decode(base64.normalize(compact)));
    if (decoded.contains('://')) return decoded;
  } catch (_) {}
  return body;
}

(String, Map<String, dynamic>?)? _cleanLink(String raw) {
  final scheme = raw.split('://').first.toLowerCase();
  switch (scheme) {
    case 'vless':
      return _cleanVless(raw);
    case 'trojan':
      return _cleanTrojan(raw);
    case 'vmess':
      return _cleanVmess(raw);
    case 'ss':
      return _cleanSs(raw);
    default:
      return ('', null);
  }
}

(String, Map<String, dynamic>?) _cleanVless(String raw) {
  final u = _parseUriGeneric(raw);
  final p = u.$2;
  final security = (p['security'] ?? 'none').toLowerCase();
  final type = (p['type'] ?? 'tcp').toLowerCase();
  final q = <String, String>{};
  q['security'] = security;
  void put(String k, String v) {
    if (v.isNotEmpty) q[k] = v;
  }

  put('sni', p['sni'] ?? p['peer'] ?? '');
  put('host', p['host'] ?? '');
  put('path', p['path'] ?? '');
  put('serviceName', p['serviceName'] ?? '');
  put('mode', p['mode'] ?? '');
  put('authority', p['authority'] ?? '');
  put('seed', p['seed'] ?? '');
  q['type'] = type;
  final headerType = p['headerType'] ?? '';
  if (headerType.isNotEmpty && headerType != 'none') q['headerType'] = headerType;
  final flow = p['flow'] ?? '';
  if (flow.isNotEmpty) q['flow'] = flow;
  final encryption = p['encryption'] ?? '';
  if (encryption.isNotEmpty) q['encryption'] = encryption;
  final packetEncoding = p['packetEncoding'] ?? p['packetencoding'] ?? '';
  if (packetEncoding.isNotEmpty) q['packetEncoding'] = packetEncoding;
  put('pbk', p['pbk'] ?? '');
  put('sid', p['sid'] ?? '');
  put('spx', p['spx'] ?? '');
  final fp = p['fp'] ?? '';
  if (fp.isNotEmpty && fp != 'none') {
    q['fp'] = fp == 'unsafe' ? 'chrome' : fp;
  }
  if (type == 'ws' && q.containsKey('alpn')) q.remove('alpn');
  if (security == 'tls') q['allowInsecure'] = '0';

  final link = '${u.$1}://${Uri.encodeComponent(u.$3)}@${_hostPort(u.$4, u.$5)}?${_encodeQuery(q)}#${Uri.encodeComponent(u.$6)}';

  final ob = <String, dynamic>{
    'type': 'vless',
    'server': u.$4,
    'server_port': u.$5,
    'uuid': u.$3,
    'tls': _tlsObject(security, p, type),
  };
  if (p.containsKey('flow') && (p['flow'] ?? '').isNotEmpty) {
    ob['flow'] = p['flow'];
  }
  final pe = packetEncoding;
  if (pe.isNotEmpty) ob['packet_encoding'] = pe;
  final tr = _transportObject(type, p);
  if (tr != null) ob['transport'] = tr;
  return (link, ob);
}

(String, Map<String, dynamic>?) _cleanTrojan(String raw) {
  final u = _parseUriGeneric(raw);
  final p = u.$2;
  final security = (p['security'] ?? 'tls').toLowerCase();
  final type = (p['type'] ?? 'tcp').toLowerCase();
  final q = <String, String>{};
  q['security'] = security;
  q['type'] = type;
  void put(String k, String v) {
    if (v.isNotEmpty) q[k] = v;
  }

  put('sni', p['sni'] ?? p['peer'] ?? '');
  put('host', p['host'] ?? '');
  put('path', p['path'] ?? '');
  put('serviceName', p['serviceName'] ?? '');
  put('seed', p['seed'] ?? '');
  final headerType = p['headerType'] ?? '';
  if (headerType.isNotEmpty && headerType != 'none') q['headerType'] = headerType;
  final fp = p['fp'] ?? '';
  if (fp.isNotEmpty && fp != 'none') {
    q['fp'] = fp == 'unsafe' ? 'chrome' : fp;
  }
  if (type == 'ws' && q.containsKey('alpn')) q.remove('alpn');
  q['allowInsecure'] = '0';

  final link = '${u.$1}://${Uri.encodeComponent(u.$3)}@${_hostPort(u.$4, u.$5)}?${_encodeQuery(q)}#${Uri.encodeComponent(u.$6)}';

  final ob = <String, dynamic>{
    'type': 'trojan',
    'server': u.$4,
    'server_port': u.$5,
    'password': u.$3,
    'tls': _tlsObject(security, p, type),
  };
  final tr = _transportObject(type, p);
  if (tr != null) ob['transport'] = tr;
  return (link, ob);
}

(String, Map<String, dynamic>?) _cleanVmess(String raw) {
  final b64 = raw.substring('vmess://'.length).replaceAll(RegExp(r'\s'), '');
  final json = utf8.decode(base64.decode(base64.normalize(b64)));
  final j = jsonDecode(json) as Map<String, dynamic>;
  final net = (j['net'] ?? 'tcp').toString();
  final tls = (j['tls'] ?? '').toString().toLowerCase() == 'tls';
  final fp = (j['fp'] ?? '').toString();
  j['fp'] = fp == 'unsafe' ? 'chrome' : fp;
  if (net == 'ws') j['alpn'] = '';
  if ((j['scy'] ?? '').toString().isEmpty) j['scy'] = 'auto';
  final outB64 = base64.encode(utf8.encode(jsonEncode(j)));
  final link = 'vmess://$outB64';
  final ob = <String, dynamic>{
    'type': 'vmess',
    'server': (j['add'] ?? '').toString(),
    'server_port': int.tryParse((j['port'] ?? '0').toString()) ?? 0,
    'uuid': (j['id'] ?? '').toString(),
    'security': (j['scy'] ?? 'auto').toString(),
    'alter_id': int.tryParse((j['aid'] ?? '0').toString()) ?? 0,
    'tls': _tlsObject(tls ? 'tls' : 'none', {
      'sni': (j['sni'] ?? '').toString(),
      'alpn': (j['alpn'] ?? '').toString(),
      'fp': (j['fp'] ?? '').toString(),
    }, net),
  };
  final p = <String, String>{
    'host': (j['host'] ?? '').toString(),
    'path': (j['path'] ?? '').toString(),
    'headerType': (j['type'] ?? '').toString(),
  };
  final tr = _transportObject(net, p);
  if (tr != null) ob['transport'] = tr;
  return (link, ob);
}

(String, Map<String, dynamic>?) _cleanSs(String raw) {
  var body = raw.substring('ss://'.length);
  String remark = '';
  final hashIdx = body.indexOf('#');
  if (hashIdx >= 0) {
    remark = Uri.decodeComponent(body.substring(hashIdx + 1));
    body = body.substring(0, hashIdx);
  }
  String method;
  String password;
  String host;
  int port;
  String plugin = '';
  final qIdx = body.indexOf('?');
  if (qIdx >= 0) {
    final qs = body.substring(qIdx + 1);
    body = body.substring(0, qIdx);
    for (final pair in qs.split('&')) {
      final eq = pair.indexOf('=');
      if (eq > 0 && pair.substring(0, eq) == 'plugin') {
        plugin = Uri.decodeComponent(pair.substring(eq + 1));
      }
    }
  }
  if (body.contains('@')) {
    final at = body.lastIndexOf('@');
    var userinfo = body.substring(0, at);
    if (!userinfo.contains(':')) {
      try {
        userinfo = utf8.decode(base64.decode(base64.normalize(userinfo)));
      } catch (_) {}
    }
    final ci = userinfo.indexOf(':');
    method = userinfo.substring(0, ci);
    password = userinfo.substring(ci + 1);
    final hp = body.substring(at + 1);
    final ci2 = hp.lastIndexOf(':');
    host = hp.substring(0, ci2);
    port = int.tryParse(hp.substring(ci2 + 1)) ?? 0;
  } else {
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(body)));
      final at = decoded.lastIndexOf('@');
      final ci = decoded.indexOf(':');
      method = decoded.substring(0, ci);
      password = decoded.substring(ci + 1, at);
      final hp = decoded.substring(at + 1);
      final ci2 = hp.lastIndexOf(':');
      host = hp.substring(0, ci2);
      port = int.tryParse(hp.substring(ci2 + 1)) ?? 0;
    } catch (_) {
      return ('', null);
    }
  }
  final userinfo = base64.encode(utf8.encode('$method:$password'));
  final pluginParam = plugin.isEmpty ? '' : '?plugin=${Uri.encodeComponent(plugin)}';
  final link = 'ss://$userinfo@${_hostPort(host, port)}$pluginParam#${Uri.encodeComponent(remark)}';
  final ob = <String, dynamic>{
    'type': 'shadowsocks',
    'server': host,
    'server_port': port,
    'method': method,
    'password': password,
  };
  return (link, ob);
}

(String scheme, Map<String, String> params, String userinfo, String host, int port, String remark)
    _parseUriGeneric(String raw) {
  final schemeEnd = raw.indexOf('://');
  final scheme = raw.substring(0, schemeEnd).toLowerCase();
  var rest = raw.substring(schemeEnd + 3);
  String remark = '';
  final hashIdx = rest.indexOf('#');
  if (hashIdx >= 0) {
    remark = Uri.decodeComponent(rest.substring(hashIdx + 1));
    rest = rest.substring(0, hashIdx);
  }
  final qIdx = rest.indexOf('?');
  Map<String, String> params = {};
  if (qIdx >= 0) {
    final qs = rest.substring(qIdx + 1);
    rest = rest.substring(0, qIdx);
    for (final pair in qs.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq < 0) {
        params[Uri.decodeComponent(pair)] = '';
      } else {
        params[Uri.decodeComponent(pair.substring(0, eq))] =
            Uri.decodeComponent(pair.substring(eq + 1));
      }
    }
  }
  String authority = rest;
  String userinfo = '';
  final at = authority.lastIndexOf('@');
  if (at >= 0) {
    userinfo = Uri.decodeComponent(authority.substring(0, at));
    authority = authority.substring(at + 1);
  }
  String host;
  int port;
  if (authority.startsWith('[')) {
    final close = authority.indexOf(']');
    host = authority.substring(1, close);
    final colon = authority.indexOf(':', close);
    port = colon >= 0 ? int.tryParse(authority.substring(colon + 1)) ?? 0 : 443;
  } else {
    final colon = authority.lastIndexOf(':');
    if (colon >= 0) {
      host = authority.substring(0, colon);
      port = int.tryParse(authority.substring(colon + 1)) ?? 443;
    } else {
      host = authority;
      port = 443;
    }
  }
  return (scheme, params, userinfo, host, port, remark);
}

Map<String, dynamic> _tlsObject(String security, Map<String, String> p, String type) {
  final enabled = security == 'tls' || security == 'reality' || security == 'xtls';
  if (!enabled) {
    return {'enabled': false};
  }
  final reality = security == 'reality';
  final tls = <String, dynamic>{
    'enabled': true,
    'server_name': (p['sni'] ?? p['peer'] ?? '').toString(),
  };
  final fp = (p['fp'] ?? '').toString();
  if (fp.isNotEmpty && fp != 'none') {
    tls['utls'] = {
      'enabled': true,
      'fingerprint': fp == 'unsafe' ? 'chrome' : fp,
    };
  }
  final cipher = (p['cs'] ?? '').toString();
  if (cipher.isNotEmpty) {
    tls['cipher_suites'] = cipher.split(':').where((c) => c.isNotEmpty).toList();
  }
  if (reality) {
    tls['reality'] = {
      'enabled': true,
      'public_key': (p['pbk'] ?? '').toString(),
      'short_id': (p['sid'] ?? '').toString(),
    };
  }
  if (type == 'ws') {
    tls['fragment'] = true;
    tls['fragment_fallback_delay'] = '0-1';
    tls['record_fragment'] = true;
  }
  final insecure = (p['allowInsecure'] ?? p['insecure'] ?? '0').toString();
  if (insecure == '1' || insecure == 'true') tls['insecure'] = true;
  return tls;
}

Map<String, dynamic>? _transportObject(String type, Map<String, String> p) {
  switch (type) {
    case 'ws':
      final ws = <String, dynamic>{'type': 'ws'};
      final path = (p['path'] ?? '').toString();
      if (path.isNotEmpty) ws['path'] = path;
      final host = (p['host'] ?? '').toString();
      if (host.isNotEmpty) ws['headers'] = {'Host': host};
      final eh = (p['eh'] ?? p['earlyDataHeaderName'] ?? '').toString();
      if (eh.isNotEmpty) ws['early_data_header_name'] = eh;
      final ed = int.tryParse((p['ed'] ?? '').toString());
      if (ed != null) ws['max_early_data'] = ed;
      return ws;
    case 'grpc':
      final g = <String, dynamic>{'type': 'grpc'};
      final sn = (p['serviceName'] ?? '').toString();
      if (sn.isNotEmpty) g['service_name'] = sn;
      return g;
    case 'http':
    case 'h2':
      final h = <String, dynamic>{'type': 'http'};
      final host = (p['host'] ?? '').toString();
      if (host.isNotEmpty) h['host'] = host.split(',').map((e) => e.trim()).toList();
      final path = (p['path'] ?? '').toString();
      if (path.isNotEmpty) h['path'] = path;
      return h;
    case 'tcp':
      final headerType = (p['headerType'] ?? '').toString();
      if (headerType == 'http') {
        final h = <String, dynamic>{'type': 'http'};
        final host = (p['host'] ?? '').toString();
        if (host.isNotEmpty) h['host'] = host.split(',').map((e) => e.trim()).toList();
        final path = (p['path'] ?? '').toString();
        if (path.isNotEmpty) h['path'] = path;
        return h;
      }
      return null;
    default:
      return null;
  }
}

String _hostPort(String host, int port) {
  if (host.contains(':') && !host.startsWith('[')) {
    return '[${host}]:$port';
  }
  return '$host:$port';
}

String _encodeQuery(Map<String, String> q) {
  return q.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

List<String> _dedupLinks(List<String> links) {
  final seen = <String>{};
  final out = <String>[];
  for (final link in links) {
    final key = link
        .replaceAll(RegExp(r'#.*$'), '')
        .replaceAll(RegExp(r'\?(allowInsecure|headerType)=[^&]*&?'), '?');
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(link);
  }
  return out;
}
