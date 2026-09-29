import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';
import 'package:tuple/tuple.dart';

/// sing-box 1.11 deprecated the legacy `block` and `dns` special outbounds
/// (removed in 1.13) and 1.12 deprecated outbound DNS rule items (removed in
/// 1.14). The bundled core is 1.12.x, so both only warn today — but a config
/// that still emits them starts failing outright on the next core bump.
///
/// These tests fail on the *warning*, not on a crash: every construct the core
/// complains about is asserted absent, so the migration cannot silently regress
/// while the deprecation is still only a warning.
void main() {
  final setting = SettingManager.getConfig();
  final originalIranOverride = setting.iranModeOverride;

  tearDown(() {
    setting.iranModeOverride = originalIranOverride;
    setting.tls.enableServerless = false;
  });

  dynamic builtDns() {
    final dns = SingboxConfigBuilder.dns(false, SingboxExportType.karing, null);
    expect(dns.error, isNull, reason: 'dns() returned an error');
    return dns.data;
  }

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

  Map<String, dynamic> builtRoute(
    List<dynamic> allOutBounds,
    dynamic dns, {
    List<Tuple3<DiversionRulesGroup, ProxyConfig, List<String>>>
    diversionGroups = const [],
  }) => Map<String, dynamic>.from(
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
      diversionGroups,
      [],
      dns,
      null,
      null,
      "",
      SingboxExportType.karing,
    ),
  );

  List<Map> outboundsOf(List<dynamic> obs) => obs.cast<Map>();

  List<Map> routeRules(Map<String, dynamic> route) =>
      (route['rules'] as List).cast<Map>();

  test('no legacy special outbounds are emitted', () {
    final types = outboundsOf(builtOutbounds())
        .map((o) => o['type'].toString())
        .toSet();

    // These two are the ones sing-box calls "legacy special outbounds".
    expect(
      types,
      isNot(contains('block')),
      reason: 'a `block` outbound makes the core log the 1.11 deprecation',
    );
    expect(
      types,
      isNot(contains('dns')),
      reason: 'a `dns` outbound makes the core log the 1.11 deprecation',
    );
    // `direct` is an ordinary outbound and must survive the migration.
    expect(types, contains('direct'));
  });

  test('no DNS rule carries the deprecated outbound item', () {
    final rules = (builtDns()['rules'] as List).cast<Map>();
    for (final r in rules) {
      expect(
        r.containsKey('outbound'),
        isFalse,
        reason:
            '${r} uses an outbound DNS rule item, deprecated in 1.12 and '
            'removed in 1.14 — bootstrap resolution belongs in '
            'route.default_domain_resolver',
      );
    }
  });

  test('DNS queries are hijacked with the hijack-dns action', () {
    final route = builtRoute(builtOutbounds(), builtDns());
    final hijack = routeRules(
      route,
    ).where((r) => r['protocol'] == 'dns').toList();

    expect(hijack, isNotEmpty, reason: 'expected the DNS hijack rules');
    for (final r in hijack) {
      expect(
        r['action'],
        'hijack-dns',
        reason: '$r must use the rule action, not the removed dns outbound',
      );
    }
  });

  test('the Iran ads rule rejects instead of targeting a block outbound', () {
    setting.iranModeOverride = true;
    final route = builtRoute(builtOutbounds(), builtDns());

    final ads = routeRules(
      route,
    ).firstWhere((r) => r['rule_set']?.toString().contains('category-ads-ir') == true);

    expect(ads['action'], 'reject');
    expect(ads.containsKey('outbound'), isFalse);
  });

  test('a diversion rule that blocks becomes a reject action', () {
    final rule = DiversionRulesGroup()
      ..outbound = 'block'
      ..domain = ['ads.example'];
    final route = builtRoute(
      builtOutbounds(),
      builtDns(),
      diversionGroups: [Tuple3(rule, ProxyConfig(), <String>[])],
    );

    final blocked = routeRules(
      route,
    ).firstWhere((r) => r['domain_suffix']?.toString().contains('ads.example') == true);

    expect(blocked['action'], 'reject');
    expect(blocked.containsKey('outbound'), isFalse);
  });

  test('no route rule points at the removed block/dns outbounds', () {
    setting.iranModeOverride = true;
    setting.tls.enableServerless = true;
    final route = builtRoute(builtOutbounds(), builtDns());

    const removed = [kOutboundTagBlock, SingboxConfigBuilder.kOutboundTagDns];
    for (final r in routeRules(route)) {
      expect(
        r['outbound'],
        isNot(anyOf(removed)),
        reason: '$r targets an outbound that is no longer emitted',
      );
    }
    expect(route['final'], isNot(anyOf(removed)));
  });

  test('default_domain_resolver is published and dials directly', () {
    final dns = builtDns();
    final route = builtRoute(builtOutbounds(), dns);

    final resolver = route['default_domain_resolver'];
    expect(
      resolver,
      isNotNull,
      reason:
          'it replaces the removed {outbound: any} DNS rule, so without it '
          'outbound server addresses lose their bootstrap resolver',
    );

    final tag = (resolver as Map)['server'].toString();
    final chosen = (dns['servers'] as List)
        .cast<Map>()
        .firstWhere((s) => s['tag'].toString() == tag);
    expect(chosen['detour'], isNull, reason: 'bootstrap must not be detoured');
  });
}
