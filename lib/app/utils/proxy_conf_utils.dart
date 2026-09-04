import 'package:karing/app/runtime/return_result.dart';

import 'package:tuple/tuple.dart';

import 'dart:io';

const String kOutboundTypeSelector = "selector";
const String kOutboundTypeUrltest = "urltest";
const String kOutboundTypeDns = "dns";
const String kOutboundTypeDirect = "direct";
const String kOutboundTypeBlock = "block";
const String kOutboundTypeServer = "server";
const String kOutboundTypeSpecial = "special";
const String kProxyDirect = "direct";
const String kProxyBlock = "block";
const String kProxyCurrent = "currentSelected";

// Proxy config models shared between app modules and screens.

class SubscriptionTraffic {
  int upload = 0;
  int download = 0;
  int total = 0;
  int expire = 0;

  SubscriptionTraffic();

  SubscriptionTraffic.from(this.upload, this.download, this.total, this.expire);

  Map<String, dynamic> toJson() =>
      {'upload': upload, 'download': download, 'total': total, 'expire': expire};

  static SubscriptionTraffic? tryParse(String headerUserInfo) {
    final pattern = RegExp(
        r'upload=(\d+); download=(\d+); total=(\d+); expire=(\d+)',
        caseSensitive: false);
    final m = pattern.firstMatch(headerUserInfo);
    if (m == null) {
      final parts = headerUserInfo.trim().split(RegExp(r'[; ]'));
      if (parts.length >= 4) {
        final u = int.tryParse(parts[0].split('=').last);
        final d = int.tryParse(parts[1].split('=').last);
        final t = int.tryParse(parts[2].split('=').last);
        final e = int.tryParse(parts[3].split('=').last);
        if (u != null && d != null && t != null && e != null) {
          return SubscriptionTraffic.from(u, d, t, e);
        }
      }
      return null;
    }
    return SubscriptionTraffic.from(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!));
  }

  static const List<String> kLanguageTagsWithDayFirst = ['en'];

  Tuple2<bool, String> getExpireTime(String languageTag) {
    if (expire <= 0) {
      return const Tuple2(false, "");
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(expire * 1000);
    final now = DateTime.now();
    final expiring = dt.isBefore(now) || dt.difference(now).inDays < 3;
    return Tuple2(
        expiring,
        "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}");
  }

  bool get overQuota {
    if (total <= 0) {
      return false;
    }
    return (upload + download) >= total;
  }

  static SubscriptionTraffic? fromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    return SubscriptionTraffic.from(
        map['upload'] ?? 0, map['download'] ?? 0, map['total'] ?? 0, map['expire'] ?? 0);
  }
}

enum SubscriptionLinkType {
  unknown,
  singbox,
  clash,
  v2ray,
  v,
  ss,
  wireguard;

  static SubscriptionLinkType fromString(String name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return SubscriptionLinkType.unknown;
  }
}

enum ProxyStrategy {
  preferProxy,
  preferDirect,
  onlyProxy,
  onlyDirect;

  static ProxyStrategy fromString(String name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return ProxyStrategy.preferDirect;
  }
}

enum ProxyFilterMethod {
  all,
  include,
  exclude;

  static ProxyFilterMethod fromString(String name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return ProxyFilterMethod.all;
  }
}

class ProxyFilter {
  ProxyFilterMethod method = ProxyFilterMethod.all;
  String keywordOrRegx = "";

  Map<String, dynamic> toJson() =>
      {'method': method.name, 'keyword_or_regx': keywordOrRegx};

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    method = ProxyFilterMethod.fromString(map['method'] ?? "all");
    keywordOrRegx = map['keyword_or_regx'] ?? "";
  }

  ProxyFilter clone() {
    final c = ProxyFilter();
    c.fromJson(toJson());
    return c;
  }
}

class RemoteContent {
  bool download = false;
  String text = "";

  String get content => text;
}

class SubscriptionISP {
  String id = "";
  String user = "";

  Map<String, dynamic> toJson() => {'id': id, 'user': user};

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    id = map['id'] ?? "";
    user = map['user'] ?? "";
  }
}

class ServerConfigItemIsp {
  String id = "";
  String user = "";

  Map<String, dynamic> toJson() => {'id': id, 'user': user};

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    id = map['id'] ?? "";
    user = map['user'] ?? "";
  }
}

/// A single server / outbound entry.
class ProxyConfig {
  String groupid = "";
  String tag = "";
  String remark = "";
  String type = kOutboundTypeServer;
  String server = "";
  int serverport = 0;
  int get port => serverport;
  set port(int v) => serverport = v;
  String url = "";
  Map<String, dynamic> raw = {};
  String fullConfig = "";
  String outsideChainProxy = "";
  String outletip = "";
  String outletregion = "";
  String attach = "";
  dynamic rawConfig;
  String latency = "";
  bool enable = true;
  int index = 0;
  String clipboardLink = "";
  List<String> proxies = [];
  List<ProxyConfig> servers = [];
  List<String> outbounds = [];
  List<String> dnsServers = [];

  Map<String, dynamic> toJson() => {
        'groupid': groupid,
        'tag': tag,
        'remark': remark,
        'type': type,
        'server': server,
        'serverport': serverport,
        'url': url,
        'raw': raw,
        'fullconfig': fullConfig,
        'outsidechainproxy': outsideChainProxy,
        'outletip': outletip,
        'latency': latency,
        'enable': enable,
        'index': index,
        'clipboard_link': clipboardLink,
        'proxies': proxies,
        'outbounds': outbounds,
        'dns_servers': dnsServers,
      };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    groupid = map['groupid'] ?? "";
    tag = map['tag'] ?? "";
    remark = map['remark'] ?? "";
    type = map['type'] ?? kOutboundTypeServer;
    server = map['server'] ?? "";
    serverport = map['serverport'] ?? map['port'] ?? 0;
    url = map['url'] ?? "";
    if (map['raw'] is Map) {
      raw = Map<String, dynamic>.from(map['raw']);
    }
    fullConfig = map['fullconfig'] ?? "";
    outsideChainProxy = map['outsidechainproxy'] ?? "";
    outletip = map['outletip'] ?? "";
    latency = map['latency'] ?? "";
    enable = map['enable'] ?? true;
    index = map['index'] ?? 0;
    clipboardLink = map['clipboard_link'] ?? "";
    proxies = List<String>.from(map['proxies'] ?? []);
    outbounds = List<String>.from(map['outbounds'] ?? []);
    dnsServers = List<String>.from(map['dns_servers'] ?? []);
    final t = map['servers'] ?? [];
    servers = [];
    for (final s in t) {
      final p = ProxyConfig();
      p.fromJson(s);
      servers.add(p);
    }
  }

  ProxyConfig clone() {
    final c = ProxyConfig();
    c.fromJson(toJson());
    return c;
  }

  /// The disable-key used by ServerUse.
  String disableKey() => "$groupid:$tag";
}

/// A subscription / config group.
class ServerConfigGroupItem {
  String groupid = "";
  int index = 0;
  String remark = "";
  String urlOrPath = "";
  String site = "";
  SubscriptionLinkType type = SubscriptionLinkType.unknown;
  bool enable = true;
  String updateTime = "";
  Duration? updateDuration;
  bool userAgentAppend = false;
  List<String> userAgentCompatibles = [];
  bool xhwid = false;
  bool keepDiversionRules = false;
  bool enableDiversionRules = false;
  bool reloadAfterProfileUpdate = false;
  bool testLatencyAfterProfileUpdate = false;
  bool testLatencyAutoRemove = false;
  ProxyStrategy proxyStrategy = ProxyStrategy.preferDirect;
  ProxyFilter proxyFilter = ProxyFilter();
  List<String> proxyFilterRemove = [];
  List<String> testLatency = [];
  List<String> testLatencyIndepends = [];
  List<ProxyConfig> servers = [];
  SubscriptionTraffic? traffic;
  SubscriptionISP? isp;
  String decryptPassword = "";
  bool editAble = true;
  List<UrltestItem> urltests = [];

  String get url => urlOrPath;
  set url(String v) => urlOrPath = v;
  String get name => remark;
  set name(String v) => remark = v;

  bool isRemote() {
    return urlOrPath.isNotEmpty &&
        (urlOrPath.startsWith("http://") || urlOrPath.startsWith("https://"));
  }

  void updateTestLatencyList() {}

  Map<String, dynamic> toJson() => {
        'groupid': groupid,
        'index': index,
        'remark': remark,
        'url_or_path': urlOrPath,
        'site': site,
        'type': type.name,
        'enable': enable,
        'update_time': updateTime,
        'update_duration': updateDuration?.inSeconds,
        'user_agent_append': userAgentAppend,
        'user_agent_compatibles': userAgentCompatibles,
        'xhwid': xhwid,
        'keep_diversion_rules': keepDiversionRules,
        'enable_diversion_rules': enableDiversionRules,
        'reload_after_profile_update': reloadAfterProfileUpdate,
        'test_latency_after_profile_update': testLatencyAfterProfileUpdate,
        'test_latency_auto_remove': testLatencyAutoRemove,
        'proxy_strategy': proxyStrategy.name,
        'proxy_filter': proxyFilter.toJson(),
        'proxy_filter_remove': proxyFilterRemove,
        'test_latency': testLatency,
        'test_latency_independs': testLatencyIndepends,
        'servers': servers,
        'traffic': traffic?.toJson(),
        'isp': isp?.toJson(),
        'decrypt_password': decryptPassword,
        'editable': editAble,
        'urltests': urltests,
      };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    groupid = map['groupid'] ?? "";
    index = map['index'] ?? 0;
    remark = map['remark'] ?? map['name'] ?? "";
    urlOrPath = map['url_or_path'] ?? map['url'] ?? "";
    site = map['site'] ?? "";
    type = SubscriptionLinkType.fromString(map['type'] ?? "unknown");
    enable = map['enable'] ?? true;
    updateTime = map['update_time'] ?? "";
    if (map['update_duration'] != null) {
      updateDuration = Duration(seconds: map['update_duration']);
    }
    userAgentAppend = map['user_agent_append'] ?? false;
    userAgentCompatibles = List<String>.from(map['user_agent_compatibles'] ?? []);
    xhwid = map['xhwid'] ?? false;
    keepDiversionRules = map['keep_diversion_rules'] ?? false;
    enableDiversionRules = map['enable_diversion_rules'] ?? false;
    reloadAfterProfileUpdate = map['reload_after_profile_update'] ?? false;
    testLatencyAfterProfileUpdate =
        map['test_latency_after_profile_update'] ?? false;
    testLatencyAutoRemove = map['test_latency_auto_remove'] ?? false;
    proxyStrategy = ProxyStrategy.fromString(map['proxy_strategy'] ?? "preferDirect");
    if (map['proxy_filter'] is Map) {
      proxyFilter = ProxyFilter()..fromJson(map['proxy_filter']);
    }
    proxyFilterRemove = List<String>.from(map['proxy_filter_remove'] ?? []);
    testLatency = List<String>.from(map['test_latency'] ?? []);
    testLatencyIndepends = List<String>.from(map['test_latency_independs'] ?? []);
    final t = map['servers'] ?? [];
    servers = [];
    for (final s in t) {
      final p = ProxyConfig();
      p.fromJson(s);
      servers.add(p);
    }
    traffic = SubscriptionTraffic.fromJson(map['traffic']);
    if (map['isp'] is Map) {
      isp = SubscriptionISP();
      isp!.fromJson(Map<String, dynamic>.from(map['isp']));
    }
    decryptPassword = map['decrypt_password'] ?? "";
    editAble = map['editable'] ?? true;
    final ut = map['urltests'] ?? [];
    urltests = [];
    for (final u in ut) {
      final item = UrltestItem();
      item.fromJson(u);
      urltests.add(item);
    }
  }

  ServerConfigGroupItem clone({bool includeServers = true}) {
    final g = ServerConfigGroupItem();
    g.fromJson(toJson());
    if (!includeServers) {
      g.servers = [];
    }
    return g;
  }

  ProxyConfig? getByTag(String tag) {
    for (final s in servers) {
      if (s.tag == tag) {
        return s;
      }
    }
    return null;
  }

  bool get isSubscription => urlOrPath.isNotEmpty;
}

/// A diversion (routing) group: a named rule set applied to a selected proxy.
class DiversionRulesGroup {
  String groupid = "";
  int index = 0;
  String name = "";
  List<String> proxies = [];
  bool or = true;
  bool switch_ = true;
  bool enable = true;
  String outbound = "currentSelected";
  List<String> ruleSetBuildIn = [];
  List<String> ruleSet = [];
  List<String> package = [];
  List<String> processName = [];
  List<String> processPath = [];
  List<String> processDir = [];
  List<String> domainSuffix = [];
  List<String> domain = [];
  List<String> domainKeyword = [];
  List<String> domainRegex = [];
  List<String> ipCidr = [];
  String ipVersion = "";
  List<String> network = [];
  List<String> networkType = [];
  List<String> wifiSsid = [];
  List<String> wifiBssid = [];
  List<int> port = [];
  List<String> portRange = [];
  List<String> protocol = [];

  Map<String, dynamic> toJson({bool noGroupId = false}) {
    return {
        if (!noGroupId) 'groupid': groupid,
        'index': index,
        'name': name,
        'proxies': proxies,
        'or': or,
        'switch': switch_,
        'enable': enable,
        'outbound': outbound,
        'rule_set_build_in': ruleSetBuildIn,
        'rule_set': ruleSet,
        'package': package,
        'processName': processName,
        'processPath': processPath,
        'processDir': processDir,
        'domainSuffix': domainSuffix,
        'domain': domain,
        'domainKeyword': domainKeyword,
        'domainRegex': domainRegex,
        'ipCidr': ipCidr,
        'ipVersion': ipVersion,
        'network': network,
        'networkType': networkType,
        'wifiSsid': wifiSsid,
        'wifiBssid': wifiBssid,
        'port': port,
        'portRange': portRange,
        'protocol': protocol,
      };
  }

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    groupid = map['groupid'] ?? "";
    index = map['index'] ?? 0;
    name = map['name'] ?? "";
    proxies = List<String>.from(map['proxies'] ?? []);
    or = map['or'] ?? true;
    switch_ = map['switch'] ?? true;
    enable = map['enable'] ?? true;
    outbound = map['outbound'] ?? "currentSelected";
    ruleSetBuildIn = List<String>.from(map['rule_set_build_in'] ?? []);
    ruleSet = List<String>.from(map['rule_set'] ?? []);
    package = List<String>.from(map['package'] ?? []);
    processName = List<String>.from(map['processName'] ?? []);
    processPath = List<String>.from(map['processPath'] ?? []);
    processDir = List<String>.from(map['processDir'] ?? []);
    domainSuffix = List<String>.from(map['domainSuffix'] ?? []);
    domain = List<String>.from(map['domain'] ?? []);
    domainKeyword = List<String>.from(map['domainKeyword'] ?? []);
    domainRegex = List<String>.from(map['domainRegex'] ?? []);
    ipCidr = List<String>.from(map['ipCidr'] ?? []);
    ipVersion = map['ipVersion'] ?? "";
    network = List<String>.from(map['network'] ?? []);
    networkType = List<String>.from(map['networkType'] ?? []);
    wifiSsid = List<String>.from(map['wifiSsid'] ?? []);
    wifiBssid = List<String>.from(map['wifiBssid'] ?? []);
    port = List<int>.from(map['port'] ?? []);
    portRange = List<String>.from(map['portRange'] ?? []);
    protocol = List<String>.from(map['protocol'] ?? []);
  }

  DiversionRulesGroup clone() {
    final c = DiversionRulesGroup();
    c.fromJson(toJson());
    return c;
  }
}

class ServerDiversionGroupItem {
  String groupid = "";
  int index = 0;
  String remark = "";
  String urlOrPath = "";
  bool editAble = false;
  List<DiversionRulesGroup> groups = [];

  String get name => remark;
  set name(String v) => remark = v;

  Map<String, dynamic> toJson() => {
        'groupid': groupid,
        'index': index,
        'remark': remark,
        'url_or_path': urlOrPath,
        'editable': editAble,
        'groups': groups,
      };

  void fromJson(Map<String, dynamic>? map, [bool init = false, String custom = ""]) {
    if (map == null) return;
    groupid = map['groupid'] ?? "";
    index = map['index'] ?? 0;
    remark = map['remark'] ?? map['name'] ?? "";
    urlOrPath = map['url_or_path'] ?? map['url'] ?? "";
    editAble = map['editable'] ?? false;
    final g = map['groups'] ?? [];
    groups = [];
    for (final r in g) {
      final item = DiversionRulesGroup();
      item.fromJson(r);
      groups.add(item);
    }
  }

  DiversionRulesGroup? getByName(String name) {
    for (final g in groups) {
      if (g.name == name) {
        return g;
      }
    }
    return null;
  }

  ServerDiversionGroupItem clone() {
    final c = ServerDiversionGroupItem();
    c.fromJson(toJson());
    return c;
  }
}


class ServerDiversionGroupRuleSetItem {
  String type = "";
  String tag = "";
  String format = "";
  String? url;
  String? detail;
  bool disable = false;

  Map<String, dynamic> toJson() =>
      {'type': type, 'tag': tag, 'format': format, 'url': url, 'detail': detail, 'disable': disable};

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    type = map['type'] ?? "";
    tag = map['tag'] ?? "";
    format = map['format'] ?? "";
    url = map['url'];
    detail = map['detail'];
    disable = map['disable'] ?? false;
  }

  static String? getTagFromUrl(Uri uri) {
    final path = uri.path;
    final file = path.split('/').last;
    if (file.isEmpty) {
      return null;
    }
    return file.replaceAll('.srs', '').replaceAll('.json', '');
  }

  ServerDiversionGroupRuleSetItem clone() {
    final c = ServerDiversionGroupRuleSetItem();
    c.fromJson(toJson());
    return c;
  }

  @override
  bool operator ==(Object other) {
    if (other is! ServerDiversionGroupRuleSetItem) return false;
    return type == other.type && tag == other.tag && format == other.format && url == other.url;
  }

  @override
  int get hashCode => Object.hash(type, tag, format, url);
}

class HttpRequestResponse {
  String body = "";
  int statusCode = 0;
  Map<String, String> headers = {};
}

class ProxyConfUtils {
  static ReturnResult<String> getUrlFromQRContent(String content) {
    var text = content.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      final uri = Uri.tryParse(text);
      if (uri != null && uri.queryParameters.containsKey('url')) {
        return ReturnResult(data: uri.queryParameters['url']!);
      }
    }
    return ReturnResult(data: text);
  }

  static String convertTrafficToStringDouble(num? value, {num kb = 1024}) {
    if (value == null || value < 0) {
      return "";
    }
    num kKB = kb;
    num kMB = kb * kKB;
    num kGB = kb * kMB;
    num kTB = kb * kGB;
    num kPB = kb * kTB;
    if (value >= kPB) {
      return "${(value / kPB).toStringAsFixed(1)} PB";
    }
    if (value >= kTB) {
      return "${(value / kTB).toStringAsFixed(1)} TB";
    }
    if (value >= kGB) {
      return "${(value / kGB).toStringAsFixed(1)} GB";
    }
    if (value >= kMB) {
      return "${(value / kMB).toStringAsFixed(1)} MB";
    }
    if (value >= kKB) {
      return "${(value / kKB).toStringAsFixed(1)} KB";
    }
    return "$value B";
  }

  static SubscriptionTraffic? getTraffic(HttpHeaders headers,
      [SubscriptionTraffic? old]) {
    final userInfo = headers.value('subscription-userinfo');
    if (userInfo == null || userInfo.isEmpty) {
      return old;
    }
    final traffic = SubscriptionTraffic.tryParse(userInfo);
    return traffic ?? old;
  }
}

typedef ProxyUrltest = UrltestItem;

class UrltestItem {
  String remark = "";
  List<String> tags = [];
  List<String> regexs = [];

  Map<String, dynamic> toJson() =>
      {'remark': remark, 'tags': tags, 'regexs': regexs};

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    remark = map['remark'] ?? "";
    tags = List<String>.from(map['tags'] ?? []);
    regexs = List<String>.from(map['regexs'] ?? []);
  }
}

extension ProxyConfigExtra on ProxyConfig {
  bool isSame(ProxyConfig other) {
    return groupid == other.groupid &&
        tag == other.tag &&
        server == other.server &&
        serverport == other.serverport;
  }

  void removeLatencyError() {
    latency = "";
  }
}

extension ServerConfigGroupItemKaring on ServerConfigGroupItem {
  SubscriptionISP? getISP() {
    return isp;
  }

  void removeLatencyError() {
    for (final server in servers) {
      server.latency = "";
    }
  }
}

extension ProxyConfigKaring on ProxyConfig {
  String getShowType() {
    if (type == kOutboundTypeSelector || type == kOutboundTypeUrltest) {
      return type;
    }
    return type;
  }
}

extension ServerConfigGroupItemKaring2 on ServerConfigGroupItem {
  String getTypeShort() {
    switch (type) {
      case SubscriptionLinkType.clash:
        return "C";
      case SubscriptionLinkType.singbox:
        return "S";
      default:
        return "V";
    }
  }

  String? getBindProvider() {
    return null;
  }
}