import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';
import 'package:karing/app/utils/singbox_outbound.dart';

void main() {
  test('normalizes the v2rayN UDP443 Vision flow alias', () {
    expect(
      normalizeVlessFlow('xtls-rprx-vision-udp443'),
      'xtls-rprx-vision',
    );
  });

  test('keeps the supported Vision flow (any casing)', () {
    expect(normalizeVlessFlow('xtls-rprx-vision'), 'xtls-rprx-vision');
    expect(normalizeVlessFlow('  XTLS-RPRX-VISION '), 'xtls-rprx-vision');
  });

  test('drops Xray-only and legacy flows the core cannot parse', () {
    expect(normalizeVlessFlow('xtls-rprx-direct'), '');
    expect(normalizeVlessFlow('xtls-rprx-splice'), '');
    expect(normalizeVlessFlow('unknown-flow'), '');
    expect(normalizeVlessFlow(null), '');
  });

  test('emitted VLESS JSON never contains the unsupported alias', () {
    final outbound = SingboxOutboundOptions()
      ..type = SingboxOutboundType.vless
      ..tag = 'node'
      ..server = 'example.com'
      ..serverPort = 443
      ..vless = (SingboxOutboundVLESSOptions()
        ..uuid = '00000000-0000-0000-0000-000000000000'
        ..flow = 'xtls-rprx-vision-udp443');

    final json = outbound.toJson();
    expect(json['flow'], 'xtls-rprx-vision');
  });

  test('loading VLESS JSON normalizes the unsupported alias', () {
    final outbound = SingboxOutboundOptions()
      ..fromJson({
        'type': 'vless',
        'tag': 'node',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '00000000-0000-0000-0000-000000000000',
        'flow': 'xtls-rprx-vision-udp443',
      });

    expect(outbound.vless?.flow, 'xtls-rprx-vision');
  });

  test('final outbound builder sanitizes persisted raw profile JSON', () {
    final node = ProxyConfig()
      ..type = kOutboundTypeServer
      ..tag = 'persisted-node'
      ..raw = {
        'type': 'vless',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '00000000-0000-0000-0000-000000000000',
        'flow': 'xtls-rprx-vision-udp443',
      };

    final outbound = SingboxConfigBuilder.buildOutbound(node)
        as Map<String, dynamic>;
    expect(outbound['flow'], 'xtls-rprx-vision');
  });

  test('final config sanitizer catches nested aggregate raw maps', () {
    final config = SingboxConfigBuilder.normalizeConfigCompatibility({
      'outbounds': [
        {
          'type': 'vless',
          'flow': 'xtls-rprx-vision-udp443',
        },
      ],
    }) as Map;
    final outbounds = config['outbounds'] as List;
    expect((outbounds.first as Map)['flow'], 'xtls-rprx-vision');
  });

  test('final config sanitizer removes unknown flows entirely', () {
    final config = SingboxConfigBuilder.normalizeConfigCompatibility({
      'outbounds': [
        {
          'type': 'vless',
          'uuid': 'u',
          'flow': 'xtls-rprx-direct',
        },
        {
          'type': 'vless',
          'uuid': 'u',
          'flow': 'xtls-rprx-vision',
        },
      ],
    }) as Map;
    final outbounds = config['outbounds'] as List;
    expect((outbounds[0] as Map).containsKey('flow'), isFalse);
    expect((outbounds[1] as Map)['flow'], 'xtls-rprx-vision');
  });
}
