import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// Cloudflare Workers shares carry their own ClientHello fragmentation in the
/// `fm=` parameter, tuned by whoever published the worker for that edge.
///
/// The app used to read those lengths and then overwrite them with Patt's
/// preset whenever Iran mode was on — so every one of 50 Workers nodes in a
/// real profile was handed identical fragment sizes and none of them passed a
/// delay test. These tests pin the preset as a *fallback*: it fills what a
/// config left empty and never replaces what the config already says.
void main() {
  final setting = SettingManager.getConfig();
  final originalIran = setting.iranModeOverride;

  tearDown(() {
    setting.iranModeOverride = originalIran;
  });

  /// A Cloudflare Workers share with the provider's own `fm=` tuning.
  String workersLink() {
    final fm = jsonEncode({
      'tcp': [
        {
          'type': 'fragment',
          'settings': {
            'packets': 'tlshello',
            'lengths': ['0', '104', '1'],
            'delays': ['0'],
            'maxSplit': '0',
          },
        },
      ],
    });
    return 'vless://00000000-0000-0000-0000-000000000000@188.114.97.6:443'
        '?security=tls&type=ws'
        '&host=w.example.workers.dev'
        '&path=%2Fpyip%3DProxyIP.SG.CMLiussss.net'
        '&sni=w.example.workers.dev&fp=unsafe'
        '&fm=${Uri.encodeComponent(fm)}';
  }

  Map<String, dynamic> tlsOf(String url) {
    final server = ProxyConfig()
      ..type = kOutboundTypeServer
      ..tag = 'node'
      ..url = url;
    final outbound = SingboxConfigBuilder.buildOutbound(server);
    expect(outbound, isNotNull, reason: 'buildOutbound returned null');
    return Map<String, dynamic>.from((outbound as Map)['tls'] as Map);
  }

  test('Iran mode keeps the fragment lengths the config shipped', () {
    setting.iranModeOverride = true;

    final tls = tlsOf(workersLink());

    expect(
      tls['fragment_sizes'],
      ['0', '104', '1'],
      reason: "Iran mode must not overwrite the config's own fm= lengths",
    );
    expect(tls['fragment_delays'], ['0']);
    // Fragmentation itself is still forced on — that is the deliberate Iran
    // hardening; only the provider's own values are preserved.
    expect(tls['fragment'], isTrue);
  });

  test('the preset still fills in a config that ships no tuning', () {
    setting.iranModeOverride = true;

    final tls = tlsOf(
      'vless://00000000-0000-0000-0000-000000000000@1.2.3.4:443'
      '?security=tls&type=tcp&sni=a.example',
    );

    expect(tls['fragment_sizes'], SettingConfigItemTLS.kFragmentSizesPatt);
    expect(tls['fragment_delays'], SettingConfigItemTLS.kFragmentDelaysPatt);
    expect(tls['fragment_max_split'], SettingConfigItemTLS.kFragmentMaxSplitPatt);
  });

  test('the config keeps its own cipher list', () {
    setting.iranModeOverride = true;

    final tls = tlsOf(
      'vless://00000000-0000-0000-0000-000000000000@1.2.3.4:443'
      '?security=tls&type=tcp&sni=a.example'
      '&cs=TLS_AES_128_GCM_SHA256%3ATLS_AES_256_GCM_SHA384',
    );

    expect(tls['cipher_suites'], [
      'TLS_AES_128_GCM_SHA256',
      'TLS_AES_256_GCM_SHA384',
    ]);
  });

  test('outside Iran nothing is injected at all', () {
    setting.iranModeOverride = false;

    final tls = tlsOf(
      'vless://00000000-0000-0000-0000-000000000000@1.2.3.4:443'
      '?security=tls&type=tcp&sni=a.example',
    );

    // The model omits `fragment` entirely when it is false, so assert on the
    // absence of the *effect* rather than on a literal false.
    expect(tls['fragment'], isNot(true));
    expect(tls.containsKey('fragment_sizes'), isFalse);
  });
}
