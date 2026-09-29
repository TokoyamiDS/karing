import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// Locks in *which* DNS servers actually get routed through the proxy, per
/// Resolve Channel mode. `dns_proxy_resolve_mode_test.dart` covers the
/// individual switches; this file pins the whole routing table so a change
/// that silently stops detouring — i.e. leaks DNS onto the local network —
/// fails loudly instead of just looking fine in the UI.
///
/// A resolver with no `detour` is queried locally. That is the property every
/// assertion here is really about.
void main() {
  final setting = SettingManager.getConfig();
  final originalMode = setting.dns.proxyResolveMode;

  tearDown(() {
    setting.dns.proxyResolveMode = originalMode;
    setting.dns.enableFakeIp = false;
    setting.dns.enableProxyResolveByProxy = false;
    setting.dns.enableFinalResolveByProxy = false;
    setting.tls.enableServerless = false;
  });

  ({List<Map> servers, List<Map> remote, Map finalServer, bool hasFakeIp})
  build() {
    final dns = SingboxConfigBuilder.dns(false, SingboxExportType.karing, null);
    expect(dns.error, isNull, reason: 'dns() returned an error');
    final data = dns.data as Map;
    final servers = (data['servers'] as List).cast<Map>();
    final finalTag = data['final'].toString();
    return (
      servers: servers,
      remote: servers
          .where((s) => s['tag'].toString().startsWith('dns-remote-'))
          .toList(),
      finalServer: servers.firstWhere(
        (s) => s['tag'].toString() == finalTag,
        orElse: () => <String, dynamic>{'tag': finalTag, 'detour': null},
      ),
      hasFakeIp: servers.any((s) => s['tag'] == 'dns-fakeip'),
    );
  }

  test('Proxy Traffic: every remote resolver dials via the proxy', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.proxy;
    final r = build();

    expect(r.remote, isNotEmpty);
    for (final s in r.remote) {
      expect(s['detour'], kOutboundTagProxy, reason: '${s['tag']}');
    }
    expect(r.finalServer['detour'], kOutboundTagProxy);
    expect(r.hasFakeIp, isFalse);
  });

  test('Direct: nothing is detoured', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct;
    final r = build();

    for (final s in r.servers) {
      expect(s['detour'], isNull, reason: '${s['tag']}');
    }
    expect(r.hasFakeIp, isFalse);
  });

  test('FakeIP: fakeip is on and the fallback resolves locally', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.fakeip;
    final r = build();

    expect(r.hasFakeIp, isTrue, reason: 'fakeip server must be present');
    // Deliberate: in FakeIP mode the exit resolves the real domain for proxied
    // traffic, so the local `final` is only a fallback/bootstrap and must not
    // depend on the proxy it may be resolving the address of.
    for (final s in r.servers) {
      expect(s['detour'], isNull, reason: '${s['tag']}');
    }
  });

  test('Direct + [Proxy Traffic] switch matches Proxy Traffic routing', () {
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.direct;
    setting.dns.enableProxyResolveByProxy = true;
    final r = build();

    expect(r.remote, isNotEmpty);
    for (final s in r.remote) {
      expect(s['detour'], kOutboundTagProxy, reason: '${s['tag']}');
    }
    expect(r.finalServer['detour'], kOutboundTagProxy);
  });

  test('FakeIP + both resolve-by-proxy switches: fakeip kept, fallback detoured',
      () {
    // This is the combination shipped in a real user config: FakeIP left on
    // (the exit resolves the real domain for proxied traffic) *and* both
    // per-purpose switches on, which is what makes the fallback resolver leave
    // at the exit instead of dialling the local network.
    setting.dns.proxyResolveMode = SettingConfigItemDNSProxyResolveMode.fakeip;
    setting.dns.enableFakeIp = true;
    setting.dns.enableProxyResolveByProxy = true;
    setting.dns.enableFinalResolveByProxy = true;
    final r = build();

    expect(r.hasFakeIp, isTrue, reason: 'FakeIP must stay on');
    expect(r.remote, isNotEmpty);
    for (final s in r.remote) {
      expect(s['detour'], kOutboundTagProxy, reason: '${s['tag']}');
    }
    expect(r.finalServer['detour'], kOutboundTagProxy,
        reason: 'the fallback resolver must leave at the exit');
  });

  test('serverless never detours in any mode', () {
    setting.tls.enableServerless = true;
    for (final mode in SettingConfigItemDNSProxyResolveMode.values) {
      setting.dns.proxyResolveMode = mode;
      final r = build();
      for (final s in r.servers) {
        expect(s['detour'], isNull, reason: '${mode.name}/${s['tag']}');
      }
    }
  });
}
