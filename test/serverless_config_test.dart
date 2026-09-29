import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// Every outbound tag referenced by the route (rules and `final`) must exist
/// in the emitted outbound list, otherwise sing-box dies on start with
/// "default outbound not found" / "outbound ... not found".
void _expectRouteTagsResolve(Map<String, dynamic> route, Set<String> tags) {
  final finalTag = route['final']?.toString() ?? '';
  expect(finalTag, isNotEmpty);
  expect(tags, contains(finalTag), reason: 'route.final $finalTag missing');
  for (final rule in (route['rules'] as List).cast<Map>()) {
    final outbound = rule['outbound']?.toString() ?? '';
    if (outbound.isEmpty) {
      continue;
    }
    expect(tags, contains(outbound), reason: 'rule outbound $outbound missing');
  }
}

void main() {
  final setting = SettingManager.getConfig();

  tearDown(() {
    setting.tls.enableServerless = false;
    setting.tls.enableSniSpoofing = false;
  });

  List<dynamic> builtOutbounds() => SingboxConfigBuilder.outbounds(
    "",
    {},
    {},
    null,
    [],
    null,
    {},
    SingboxExportType.karing,
  );

  Map<String, dynamic> builtRoute(List<dynamic> allOutBounds) =>
      Map<String, dynamic>.from(
        SingboxConfigBuilder.route(
          "",
          "",
          "",
          "",
          [],
          [],
          [],
          false,
          allOutBounds,
          {},
          null,
          [],
          [],
          null,
          null,
          null,
          "",
          SingboxExportType.karing,
        ) as Map,
      );

  test('serverless outbounds are emitted with the rest of the outbounds', () {
    setting.tls.enableServerless = true;
    final outbounds = builtOutbounds();
    final tags = outbounds
        .whereType<Map>()
        .map((ob) => ob['tag']?.toString() ?? '')
        .toSet();

    expect(
      tags,
      containsAll(<String>[
        SingboxConfigBuilder.kServerlessTcpFragment,
        SingboxConfigBuilder.kServerlessTcpFragmentTls,
        SingboxConfigBuilder.kServerlessUdpNoises,
      ]),
    );
    for (final ob in outbounds.whereType<Map>()) {
      final tag = ob['tag']?.toString() ?? '';
      if (!tag.startsWith('tcp-fragment') && tag != 'udp-noises') {
        continue;
      }
      expect(ob['type'], 'direct');
      expect(ob['finalmask'], isA<Map>(), reason: '$tag has no finalmask');
    }
  });

  test('serverless masks carry the v50 parameters', () {
    setting.tls.enableServerless = true;
    final byTag = <String, Map>{};
    for (final ob in builtOutbounds().whereType<Map>()) {
      byTag[ob['tag'].toString()] = Map<String, dynamic>.from(ob);
    }

    // patterniha/Serverless-for-Iran v50, Serverless-fragA.jsonc: the
    // ClientHello is split into 6/98/1 byte pieces with no delay. The second
    // v50 stage (114/1 on the packets after the hello) has no slot in a
    // single-mask direct outbound, so it is not emitted.
    expect(
      byTag[SingboxConfigBuilder.kServerlessTcpFragmentTls]!['finalmask'],
      {
        'tcp_split': true,
        'packets': 'tlshello',
        'lengths': ["6", "98", "1"],
        'delays': ["0"],
        'max_split': 0,
      },
    );
    // v50's aggressive variants, kept unreferenced like upstream does.
    expect(
      byTag[SingboxConfigBuilder.kServerlessTcpFragment]!['finalmask'],
      {
        'tcp_split': true,
        'packets': '1-1',
        'lengths': ["1"],
        'delays': ["1"],
        'max_split': 201,
      },
    );
    expect(
      byTag[SingboxConfigBuilder.kServerlessUdpNoises]!['finalmask'],
      {
        'udp_noise': true,
        'noise_rand': '1200-1230',
        'noise_delay': '10',
        'noise_reset': 28,
        'noise_count': 24,
      },
    );
  });

  test('serverless route is the v50 rule set', () {
    setting.tls.enableServerless = true;
    final rules = (builtRoute(<dynamic>[])['rules'] as List).cast<Map>();
    // The v50 block begins at the DPI-honeypot reject.
    final start = rules.indexWhere((r) => r['ip_cidr'] != null);
    expect(start, isNonNegative, reason: 'the v50 block is missing');
    final serverless = rules.sublist(start);

    // TLS has to be sniffed first, otherwise the protocol rules never match
    // (Karing leaves inbound sniffing off). The sniff action is now added once,
    // near the top of the whole rule list, so that domain rules like geosite-ir
    // see it too — assert the ordering rather than treating it as the block's
    // first entry.
    final sniff = rules.indexWhere((r) => r['action'] == 'sniff');
    expect(sniff, isNonNegative, reason: 'no sniff action');
    expect(sniff, lessThan(start), reason: 'sniff must precede the v50 block');
    expect(rules[sniff]['sniffer'], ['tls', 'http', 'quic']);

    // The three "refuse" rules (DPI honeypot ranges, QUIC, UDP/443) are
    // `reject` actions rather than pointing at the `block` outbound, which
    // sing-box 1.11 deprecated and removes in 1.13.
    for (final r in serverless.take(3)) {
      expect(r['action'], 'reject', reason: '$r must refuse via the action');
      expect(
        r.containsKey('outbound'),
        isFalse,
        reason: '$r must not target the removed block outbound',
      );
    }
    List<String?> outsFrom(int index) => serverless
        .skip(index)
        .map((r) => r['outbound']?.toString())
        .toList();
    expect(outsFrom(3), [
      SingboxConfigBuilder.kServerlessTcpFragmentTls, // sniffed TLS
      SingboxConfigBuilder.kServerlessTcpFragmentTls, // TCP/443
    ]);
    // v50's tcp-direct/udp-direct catch-alls: nothing else is masked.
    expect(
      serverless.firstWhere((r) => r['ip_cidr'] != null)['ip_cidr'],
      SingboxConfigBuilder.kServerlessBlockedCidrs,
    );
    for (final tag in outsFrom(0)) {
      expect(tag, isNot(SingboxConfigBuilder.kServerlessTcpFragment));
      expect(tag, isNot(SingboxConfigBuilder.kServerlessUdpNoises));
    }
  });

  test('serverless route references resolve against the outbounds', () {
    setting.tls.enableServerless = true;
    // route() used to append these outbounds to a list that had already been
    // consumed, leaving route.final dangling -> fatal on core start.
    final allOutBounds = <dynamic>[];
    final tags = builtOutbounds()
        .whereType<Map>()
        .map((ob) => ob['tag']?.toString() ?? '')
        .toSet();
    final route = builtRoute(allOutBounds);
    // v50 leaves everything the TLS/443 rules miss to the plain direct
    // outbound, so `final` must resolve to it.
    expect(route['final'], kOutboundTagDirect);
    expect(allOutBounds, isEmpty);
    _expectRouteTagsResolve(route, tags);
  });

  test('proxy mode route keeps the proxy final and no serverless outbounds', () {
    setting.tls.enableServerless = false;
    final outbounds = builtOutbounds();
    final tags = outbounds
        .whereType<Map>()
        .map((ob) => ob['tag']?.toString() ?? '')
        .toSet();
    final route = builtRoute(<dynamic>[]);

    expect(route['final'], kOutboundTagProxy);
    expect(tags, isNot(contains(SingboxConfigBuilder.kServerlessTcpFragment)));
    _expectRouteTagsResolve(route, tags);
  });

  test('selector and urltest always carry at least one member', () {
    // sing-box: "initialize outbound[0]: missing tags"
    setting.tls.enableServerless = true;
    for (final ob in builtOutbounds().whereType<Map>()) {
      if (ob['type'] == 'selector' || ob['type'] == 'urltest') {
        expect(
          (ob['outbounds'] as List),
          isNotEmpty,
          reason: '${ob['tag']} has no members',
        );
      }
    }
  });
}
