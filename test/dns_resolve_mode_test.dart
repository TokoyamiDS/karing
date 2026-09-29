import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// `proxyResolveMode: proxy` is meant to mean "resolve through the connected
/// profile". It used to only pick a different resolver while still sending the
/// query out on the local network, where it can be poisoned — the mode looked
/// enabled but did nothing. These tests pin the detour that makes it real.
void main() {
  final setting = SettingManager.getConfig();
  final original = setting.dns.proxyResolveMode;

  tearDown(() {
    setting.dns.proxyResolveMode = original;
    setting.tls.enableServerless = false;
    setting.dns.enableFakeIp = false;
    setting.dns.enableProxyResolveByProxy = false;
    setting.dns.enableFinalResolveByProxy = false;
  });

  dynamic builtDns() {
    final dns = SingboxConfigBuilder.dns(
      false,
      SingboxExportType.karing,
      null,
    );
    expect(dns.error, isNull, reason: 'dns() returned an error');
    return dns.data;
  }

  List<Map> dnsServers() => (builtDns()['servers'] as List).cast<Map>();

  Map<String, dynamic> builtRoute(List<dynamic> allOutBounds, dynamic dns) =>
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
          dns,
          null,
          null,
          "",
          SingboxExportType.karing,
        ),
      );

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

  test('proxy mode detours the remote resolvers through the proxy outbound', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.proxy;

    final remote = dnsServers()
        .where((s) => s['tag'].toString().startsWith('dns-remote-'))
        .toList();

    expect(remote, isNotEmpty, reason: 'expected dns-remote-* servers');
    for (final s in remote) {
      expect(
        s['detour'],
        kOutboundTagProxy,
        reason: '${s['tag']} must dial via the proxy, otherwise the query '
            'still leaves on the local network',
      );
    }
  });

  test('fakeip mode leaves resolution direct', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.fakeip;

    for (final s in dnsServers()) {
      expect(s['detour'], isNull, reason: '${s['tag']} should not be detoured');
    }
  });

  test('direct mode leaves resolution direct', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct;

    for (final s in dnsServers()) {
      expect(s['detour'], isNull, reason: '${s['tag']} should not be detoured');
    }
  });

  test('serverless mode never detours (the selector has no real node)', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.proxy;
    setting.tls.enableServerless = true;

    for (final s in dnsServers()) {
      expect(s['detour'], isNull, reason: '${s['tag']} should not be detoured');
    }
  });

  test('default_domain_resolver never points at a detoured server', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.proxy;

    final dns = builtDns();
    final servers = (dns['servers'] as List).cast<Map>();
    final route = builtRoute(builtOutbounds(), dns);
    final resolverTag =
        (route['default_domain_resolver'] as Map)['server'].toString();

    final chosen = servers.firstWhere((s) => s['tag'].toString() == resolverTag);
    // Resolving a node whose address is a domain must not need the proxy that
    // is still being built, so this resolver has to dial directly.
    expect(
      chosen['detour'],
      isNull,
      reason: 'default_domain_resolver must not be detoured',
    );
  });

  // The three per-purpose switches predate the consolidated Resolve Channel
  // dropdown. They are additive: each must work on its own, even with the
  // dropdown left on `direct`, or the restored toggles would be decorative.

  test('enableProxyResolveByProxy detours without the dropdown', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct;
    setting.dns.enableProxyResolveByProxy = true;

    final remote = dnsServers()
        .where((s) => s['tag'].toString().startsWith('dns-remote-'))
        .toList();

    expect(remote, isNotEmpty);
    for (final s in remote) {
      expect(s['detour'], kOutboundTagProxy, reason: '${s['tag']}');
    }
  });

  test('enableFinalResolveByProxy points the final rule at a detoured server', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct;
    setting.dns.enableFinalResolveByProxy = true;

    final dns = builtDns();
    final servers = (dns['servers'] as List).cast<Map>();

    // `dns.final` is the fallback *resolver* tag. (The route block's own
    // `final` is the fallback outbound, so it is not what this switch acts on.)
    final finalTag = dns['final'].toString();
    final chosen = servers.firstWhere((s) => s['tag'].toString() == finalTag);
    expect(
      chosen['detour'],
      kOutboundTagProxy,
      reason: 'the [final] resolver must be detoured for this switch to mean '
          'anything',
    );
  });

  test('enableFakeIp enables the fakeip server without the dropdown', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct;
    setting.dns.enableFakeIp = true;

    final tags = dnsServers().map((s) => s['tag'].toString()).toList();
    expect(tags, contains('dns-fakeip'));
  });

  test('with every switch off and the dropdown direct, nothing is detoured', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct;

    for (final s in dnsServers()) {
      expect(s['detour'], isNull, reason: '${s['tag']} should not be detoured');
    }
    final tags = dnsServers().map((s) => s['tag'].toString()).toList();
    expect(tags, isNot(contains('dns-fakeip')));
  });

  // The switches are additive, so one left on from a previous mode would keep
  // forcing its behaviour and the dropdown would appear broken. Picking a mode
  // must therefore reset them.

  group('syncResolveFlagsToMode', () {
    test('direct clears every switch', () {
      final dns = SettingConfigItemDNS()
        ..enableFakeIp = true
        ..enableProxyResolveByProxy = true
        ..enableFinalResolveByProxy = true
        ..proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct
        ..syncResolveFlagsToMode();

      expect(dns.enableFakeIp, isFalse);
      expect(dns.enableProxyResolveByProxy, isFalse);
      expect(dns.enableFinalResolveByProxy, isFalse);
    });

    test('proxy turns on the two proxy switches only', () {
      final dns = SettingConfigItemDNS()
        ..proxyResolveMode = SettingConfigItemDNSProxyResolveMode.proxy
        ..syncResolveFlagsToMode();

      expect(dns.enableFakeIp, isFalse);
      expect(dns.enableProxyResolveByProxy, isTrue);
      expect(dns.enableFinalResolveByProxy, isTrue);
    });

    test('fakeip turns on only the fakeip switch', () {
      final dns = SettingConfigItemDNS()
        ..proxyResolveMode = SettingConfigItemDNSProxyResolveMode.fakeip
        ..syncResolveFlagsToMode();

      expect(dns.enableFakeIp, isTrue);
      expect(dns.enableProxyResolveByProxy, isFalse);
      expect(dns.enableFinalResolveByProxy, isFalse);
    });
  });

  test('a mode-only config derives the switches instead of leaving them off', () {
    final dns = SettingConfigItemDNS()
      ..fromJson({'proxy_resolve_mode': 'proxy'});

    expect(dns.enableProxyResolveByProxy, isTrue);
    expect(dns.enableFinalResolveByProxy, isTrue);
    expect(dns.enableFakeIp, isFalse);
  });

  test('a config carrying the legacy flags keeps them verbatim', () {
    final dns = SettingConfigItemDNS()
      ..fromJson({
        'proxy_resolve_mode': 'direct',
        'enable_fake_ip': false,
        'enable_proxy_resolve_by_proxy': true,
        'enable_final_resolve_by_proxy': false,
      });

    expect(dns.enableProxyResolveByProxy, isTrue);
    expect(dns.enableFinalResolveByProxy, isFalse);
  });
}
