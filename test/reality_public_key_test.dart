import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';
import 'package:karing/app/utils/singbox_outbound.dart';

/// sing-box decodes a reality `public_key` with unpadded URL-safe base64 and
/// requires exactly 32 decoded bytes, so a usable key is 43 characters of
/// [A-Za-z0-9_-]. When that fails the core aborts *every* outbound:
///
///     FATAL[0000] create service: initialize outbound[23]: invalid public_key
///
/// which is what a single node advertising `security=reality` without a `pbk`
/// did to a 30-outbound config. The expectations below were measured against the
/// bundled core with `sing-box check`, not assumed.
void main() {
  const validKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
  const standardBase64Key =
      '+/+/7/79+/+/7/79+/+/7/79+/+/7/79+/+/7/79AAE';

  group('isValidPublicKey', () {
    test('accepts a 43-char unpadded URL-safe base64 key', () {
      expect(validKey.length, 43);
      expect(SingboxOutboundRealityOptions.isValidPublicKey(validKey), isTrue);
    });

    test('rejects the empty key that aborted core startup', () {
      expect(SingboxOutboundRealityOptions.isValidPublicKey(''), isFalse);
    });

    test('rejects wrong lengths', () {
      expect(
        SingboxOutboundRealityOptions.isValidPublicKey(validKey.substring(0, 42)),
        isFalse,
      );
      expect(
        SingboxOutboundRealityOptions.isValidPublicKey('${validKey}A'),
        isFalse,
      );
    });

    test('rejects the standard base64 alphabet', () {
      // The core uses RawURLEncoding: '+' and '/' are illegal even at the
      // correct length, so this must not be treated as usable.
      expect(standardBase64Key.length, 43);
      expect(
        SingboxOutboundRealityOptions.isValidPublicKey(standardBase64Key),
        isFalse,
      );
    });

    test('rejects padding', () {
      expect(
        SingboxOutboundRealityOptions.isValidPublicKey('$validKey='),
        isFalse,
      );
    });
  });

  group('reality serialisation', () {
    test('omits reality when public_key is unusable', () {
      final tls = SingboxOutboundTLSOptions()
        ..fromJson({
          'enabled': true,
          'server_name': 'example.com',
          'reality': {'enabled': true, 'public_key': '', 'short_id': ''},
        });

      final json = tls.toJson();
      expect(json.containsKey('reality'), isFalse);
      // The node still goes out as plain TLS rather than disappearing.
      expect(json['enabled'], isTrue);
    });

    test('keeps reality when public_key is usable', () {
      final tls = SingboxOutboundTLSOptions()
        ..fromJson({
          'enabled': true,
          'reality': {'enabled': true, 'public_key': validKey, 'short_id': 'ab'},
        });

      expect(tls.toJson()['reality'], {
        'enabled': true,
        'public_key': validKey,
        'short_id': 'ab',
      });
    });

    test('reality options never serialise an unusable key directly', () {
      final r = SingboxOutboundRealityOptions()
        ..enabled = true
        ..publicKey = '';
      expect(r.toJson(), isEmpty);
    });
  });

  group('final config sanitizer', () {
    // This is the layer that repairs already-persisted profiles: the offending
    // node was imported before the guard existed and is already on disk.
    test('strips an unusable reality block but keeps the rest', () {
      final cfg =
          SingboxConfigBuilder.normalizeConfigCompatibility({
                'outbounds': [
                  {
                    'type': 'vless',
                    'server': '94.183.154.216',
                    'tls': {
                      'enabled': true,
                      'insecure': true,
                      'reality': {
                        'enabled': true,
                        'public_key': '',
                        'short_id': '',
                      },
                    },
                  },
                  {
                    'type': 'vless',
                    'server': '5.6.7.8',
                    'tls': {
                      'enabled': true,
                      'reality': {
                        'enabled': true,
                        'public_key': validKey,
                        'short_id': '',
                      },
                    },
                  },
                ],
              })
              as Map;

      final outbounds = cfg['outbounds'] as List;

      final brokenTls = (outbounds[0] as Map)['tls'] as Map;
      expect(brokenTls.containsKey('reality'), isFalse);
      expect(brokenTls['enabled'], isTrue);
      expect(brokenTls['insecure'], isTrue);
      expect((outbounds[0] as Map)['server'], '94.183.154.216');

      final goodTls = (outbounds[1] as Map)['tls'] as Map;
      expect((goodTls['reality'] as Map)['public_key'], validKey);
    });

    test('strips a malformed reality key too', () {
      final cfg =
          SingboxConfigBuilder.normalizeConfigCompatibility({
                'outbounds': [
                  {
                    'type': 'vless',
                    'tls': {
                      'enabled': true,
                      'reality': {
                        'enabled': true,
                        'public_key': standardBase64Key,
                        'short_id': '',
                      },
                    },
                  },
                ],
              })
              as Map;

      final tls = ((cfg['outbounds'] as List).first as Map)['tls'] as Map;
      expect(tls.containsKey('reality'), isFalse);
    });
  });
}
