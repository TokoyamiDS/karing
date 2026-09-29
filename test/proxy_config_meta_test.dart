import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';

void main() {
  group('ProxyConfig metadata', () {
    test('getProtocol reads raw sing-box type', () {
      final p = ProxyConfig()
        ..type = kOutboundTypeServer
        ..raw = {'type': 'vless', 'server': 'a.example', 'server_port': 443};
      expect(p.getProtocol(), 'vless');
      expect(p.getProtocolLabel(), 'VLESS');
    });

    test('getProtocol falls back to the share-link scheme', () {
      final p = ProxyConfig()
        ..type = kOutboundTypeServer
        ..clipboardLink = 'hy2://pass@host:443#x';
      expect(p.getProtocol(), 'hysteria2');
      expect(p.getProtocolLabel(), 'HY2');
    });

    test('getProtocol keeps pseudo-outbound type', () {
      final p = ProxyConfig()..type = kOutboundTypeUrltest;
      expect(p.getProtocol(), kOutboundTypeUrltest);
    });

    test('displayServer/originalServer reflect a clean-IP replacement', () {
      final p = ProxyConfig()
        ..type = kOutboundTypeServer
        ..server = '104.16.0.1'
        ..raw = {
          'type': 'vmess',
          'server': '104.16.0.1',
          'server_port': 443,
          'server_ip_replaced': true,
          'cf_replaced': 'origin.example.com',
        };
      expect(p.displayServer, '104.16.0.1');
      expect(p.originalServer, 'origin.example.com');
    });

    test('originalServer is the dial address when not replaced', () {
      final p = ProxyConfig()
        ..server = 'origin.example.com'
        ..raw = {'type': 'trojan', 'server': 'origin.example.com'};
      expect(p.originalServer, 'origin.example.com');
      expect(p.displayServer, 'origin.example.com');
    });

    test('isProxyNode is false for pseudo-outbounds', () {
      expect((ProxyConfig()..type = kOutboundTypeServer).isProxyNode, isTrue);
      expect((ProxyConfig()..type = kOutboundTypeDirect).isProxyNode, isFalse);
      expect((ProxyConfig()..type = kOutboundTypeBlock).isProxyNode, isFalse);
    });

    test('hasTls reflects the tls section', () {
      final p = ProxyConfig()
        ..type = kOutboundTypeServer
        ..raw = {
          'type': 'trojan',
          'server': 'h',
          'server_port': 443,
          'tls': {'enabled': true, 'server_name': 'h'},
        };
      expect(p.hasTls, isTrue);
      final p2 = ProxyConfig()
        ..type = kOutboundTypeServer
        ..raw = {'type': 'vless', 'server': 'h', 'server_port': 80};
      expect(p2.hasTls, isFalse);
    });
  });
}
