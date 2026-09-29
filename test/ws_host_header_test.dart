import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/auto_conf_utils.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// A real link the user reported as "works fast in v2rayN, not even connecting
/// in Karing". It carries `sni=` but no `host=`, which is the whole problem:
/// Cloudflare routes by the Host header, so without it the WebSocket upgrade is
/// answered 403 and the node never connects.
///
/// Measured against that node: `Host: <sni>` reached Cloudflare (503 — the
/// origin was down), `Host: <the dialled IP>` returned 403. v2rayN/Xray default
/// the Host to the SNI; we did not.
const _linkNoHost = 'vless://b7483fbf-94f6-4d6c-add6-ec3df4fb8015@172.67.216.37:8443'
    '?encryption=none&security=tls&sni=swz.yandex-api.store&fp=safari'
    '&type=ws&path=%2Fassets#ws-no-host';

Future<ProxyConfig> _parse(String link) async {
  final group = ServerConfigGroupItem();
  final err = await AutoConfUtils.tryConvert(
    '',
    false,
    true,
    group,
    [],
    null,
    RemoteContent()..text = link,
  );
  expect(err, isNull, reason: 'the link should convert cleanly');
  expect(group.servers, hasLength(1));
  return group.servers.first;
}

void main() {
  test('a ws link with no host= takes its Host from the SNI', () async {
    final proxy = await _parse(_linkNoHost);

    expect(proxy.raw['server'], '172.67.216.37');
    expect(proxy.raw['server_port'], 8443);

    final transport = proxy.raw['transport'] as Map<String, dynamic>;
    expect(transport['type'], 'ws');
    expect(transport['path'], '/assets');
    expect(
      (transport['headers'] as Map?)?['Host'],
      'swz.yandex-api.store',
      reason: 'Cloudflare routes by Host; without it the upgrade is answered 403',
    );
  });

  test('the TLS parameters of that link survive intact', () async {
    final proxy = await _parse(_linkNoHost);

    final tls = proxy.raw['tls'] as Map<String, dynamic>;
    expect(tls['enabled'], isTrue);
    expect(tls['server_name'], 'swz.yandex-api.store');
    expect((tls['utls'] as Map)['fingerprint'], 'safari');
  });

  test('an explicit host= still wins over the SNI', () async {
    final proxy = await _parse(
      'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443'
      '?encryption=none&security=tls&sni=sni.example.com&host=front.example.com'
      '&type=ws&path=%2Fws#explicit-host',
    );

    final transport = proxy.raw['transport'] as Map<String, dynamic>;
    expect(
      (transport['headers'] as Map)['Host'],
      'front.example.com',
      reason: 'an explicit host= is authoritative',
    );
  });

  test('a link with neither host= nor sni= sets no Host header', () async {
    final proxy = await _parse(
      'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:80'
      '?encryption=none&security=none&type=ws&path=%2Fws#no-host-no-sni',
    );

    final transport = proxy.raw['transport'] as Map<String, dynamic>;
    expect(
      transport.containsKey('headers'),
      isFalse,
      reason: 'inventing a Host would be worse than omitting it',
    );
  });

  test('a node persisted before the default existed is repaired in place', () {
    // The real stored form of the reported node, copied from the user's profile.
    // It was imported before the SNI->Host default existed, so it carries no Host
    // and Cloudflare answers 403 forever. The config is built from this stored
    // raw, so the safety net has to fix it — asking someone to re-import a whole
    // subscription to repair one node is not reasonable.
    final stored = <String, dynamic>{
      'type': 'vless',
      'server': '104.25.77.78',
      'server_port': 8443,
      'uuid': 'b7483fbf-94f6-4d6c-add6-ec3df4fb8015',
      'tls': {
        'enabled': true,
        'server_name': 'swz.yandex-api.store',
        'insecure': true,
        'utls': {'enabled': true, 'fingerprint': 'safari'},
      },
      'transport': {'type': 'ws', 'path': '/assets'},
      'cf': true,
    };

    final fixed =
        SingboxConfigBuilder.normalizeConfigCompatibility(stored) as Map;

    final transport = fixed['transport'] as Map;
    expect(transport['path'], '/assets', reason: 'other fields must survive');
    expect(transport['type'], 'ws');
    expect(
      (transport['headers'] as Map)['Host'],
      'swz.yandex-api.store',
      reason: 'without this the node keeps failing with 403',
    );
  });

  test('the safety net never overwrites an existing Host', () {
    final already = <String, dynamic>{
      'type': 'vless',
      'tls': {'enabled': true, 'server_name': 'sni.example.com'},
      'transport': {
        'type': 'ws',
        'path': '/ws',
        'headers': {'Host': 'front.example.com', 'X-Keep': 'me'},
      },
    };

    final fixed =
        SingboxConfigBuilder.normalizeConfigCompatibility(already) as Map;
    final headers = (fixed['transport'] as Map)['headers'] as Map;

    expect(headers['Host'], 'front.example.com');
    expect(headers['X-Keep'], 'me', reason: 'sibling headers must survive');
  });

  test('the safety net leaves a ws node with no SNI alone', () {
    final noSni = <String, dynamic>{
      'type': 'vless',
      'tls': {'enabled': true},
      'transport': {'type': 'ws', 'path': '/ws'},
    };

    final fixed =
        SingboxConfigBuilder.normalizeConfigCompatibility(noSni) as Map;

    expect(
      (fixed['transport'] as Map).containsKey('headers'),
      isFalse,
      reason: 'there is no SNI to default to, so no Host should be invented',
    );
  });
}
