import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/singbox_outbound.dart';

void main() {
  test('ws transport drops legacy host into Host header', () {
    final o = SingboxOutboundOptions()
      ..fromJson({
        'type': 'trojan',
        'tag': 't',
        'server': '104.25.204.167',
        'server_port': 443,
        'password': 'humanity',
        'transport': {
          'type': 'ws',
          'path': '/assignment',
          'host': '216.24.57.7',
        },
      });
    final tr = o.toJson()['transport'] as Map<String, dynamic>;
    expect(tr.containsKey('host'), isFalse);
    expect(tr['headers'], {'Host': '216.24.57.7'});
  });

  test('ws transport keeps existing Host header', () {
    final o = SingboxOutboundOptions()
      ..fromJson({
        'type': 'trojan',
        'tag': 't',
        'server': 's',
        'server_port': 443,
        'password': 'p',
        'transport': {
          'type': 'ws',
          'path': '/',
          'host': 'legacy.example',
          'headers': {'Host': 'real.example'},
        },
      });
    final tr = o.toJson()['transport'] as Map<String, dynamic>;
    expect(tr.containsKey('host'), isFalse);
    expect(tr['headers'], {'Host': 'real.example'});
  });
}
