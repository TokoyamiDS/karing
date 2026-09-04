import 'package:karing/app/runtime/return_result.dart';

/// One dns server entry used by the karing-fork clash dns query api:
/// {tag, servers: [url], detour}
class SingboxDNSServerBatchOptions {
  final String tag;
  final List<String> servers;
  String detour = "";

  SingboxDNSServerBatchOptions(this.tag, {List<String>? servers})
      : servers = servers ?? [];

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{'tag': tag, 'servers': servers};
    if (detour.isNotEmpty) {
      out['detour'] = detour;
    }
    return out;
  }
}

class SingboxDNSDomainResolver {
  final String server;
  final String strategy;
  SingboxDNSDomainResolver({required this.server, required this.strategy});

  Map<String, dynamic> toJson() => {'server': server, 'strategy': strategy};
}

const String kDnsTagResolver = 'dns-resolver-1';
const String kDnsTagOutbound = 'dns-remote-1';
const String kDnsTagDirect = 'dns-direct-1';
const String kDnsTagProxy = 'dns-remote-1';
const String kDnsTagBlock = 'dns-block';

class DNSQueryRequest {
  String tag = "";
  String domain = "";
  String strategy = "";
  List<SingboxDNSServerBatchOptions> servers = [];

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'domain': domain,
        'strategy': strategy,
        'servers': servers.map((e) => e.toJson()).toList(),
      };
}

class SingboxDnsServerOptions {
  String tag = "";
  String address = "";
  String addressResolver = "";
  String strategy = "";
  String detour = "";
  String type = "";
}

class SingboxDnsUtils {
  /// converts dns server urls/ips into batch options for the dns query api.
  /// supported schemes: udp://, tcp://, tls://, https://, h3://, quic://,
  /// rcode://success|refused, local
  static ReturnResult<List<SingboxDNSServerBatchOptions>> tryParseList(
      List<String> urls,
      String? detour,
      SingboxDNSDomainResolver? domainResolver) {
    final servers = <SingboxDNSServerBatchOptions>[];
    int index = 1;
    for (final url in urls) {
      final tag = _tagFromUrl(url, index++);
      if (tag == null) {
        return ReturnResult(error: ReturnResultError("invalid dns: $url"));
      }
      final options = SingboxDNSServerBatchOptions(tag.$1, servers: [url])
        ..detour = detour ?? "";
      servers.add(options);
    }
    return ReturnResult(data: servers);
  }

  static (String, String)? _tagFromUrl(String url, int index) {
    String address = url.trim();
    String type = "udp";
    final schemeMatch =
        RegExp(r'^(udp|tcp|tls|https|h3|quic|dhcp|auto|rcode|fakeip)://')
            .firstMatch(address);
    if (schemeMatch != null) {
      type = schemeMatch.group(1)!;
    } else if (address.startsWith('local')) {
      type = 'local';
    }
    final host = Uri.tryParse(address.contains('://') ? address : "udp://$address")?.host ?? "";
    final name = host.isEmpty ? address : host;
    return ("dns-$type-$index-$name", type);
  }
}

class SingboxDns {
  static const String kTypeUdp = "udp";
  static const String kTypeTcp = "tcp";
  static const String kTypeTls = "tls";
  static const String kTypeHttps = "https";
  static const String kTypeQuic = "quic";
  static const String kTypeLocal = "local";
  static const String kTypeFakeip = "fakeip";

  static bool isEncrypted(String type) {
    return type == kTypeTls ||
        type == kTypeHttps ||
        type == kTypeQuic ||
        type == kTypeTcp;
  }
}

/// top-level helper expected by server_manager.
ReturnResult<List<SingboxDNSServerBatchOptions>> SingboxDNSTryParseList(
    List<String> urls,
    String? detour,
    SingboxDNSDomainResolver? domainResolver) {
  return SingboxDnsUtils.tryParseList(urls, detour, domainResolver);
}
