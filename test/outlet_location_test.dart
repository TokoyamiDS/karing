import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/emoji_utils.dart';
import 'package:karing/app/utils/network_utils.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';

/// The profiles list shows each node's exit location inline, in front of its
/// ping. That label is only as good as what survives a save/load cycle, so pin
/// both halves: the location fields round-tripping, and the flag rendering.
void main() {
  test('exit location survives a save/load cycle', () {
    final server = ProxyConfig()
      ..type = kOutboundTypeServer
      ..tag = 'node'
      ..server = '188.114.97.6'
      ..serverport = 443
      ..outletip = '203.0.113.9'
      ..outletregion = 'de';

    final restored = ProxyConfig()..fromJson(server.toJson());

    expect(restored.outletip, '203.0.113.9');
    expect(
      restored.outletregion,
      'de',
      reason: 'without this the flag disappears on the next app start',
    );
  });

  test('a node with no location yet stays empty rather than showing junk', () {
    final server = ProxyConfig()
      ..type = kOutboundTypeServer
      ..tag = 'untested'
      ..server = 'example.com'
      ..serverport = 443;

    final restored = ProxyConfig()..fromJson(server.toJson());

    expect(restored.outletip, isEmpty);
    expect(restored.outletregion, isEmpty);
    // The list renders "${flag} ${ip}".trim(), so both-empty must give "".
    expect(
      "${EmojiUtils.countryCodeToEmoji(restored.outletregion)} ${restored.outletip}"
          .trim(),
      isEmpty,
    );
  });

  test('country code renders as a flag, and a missing one renders as nothing', () {
    expect(EmojiUtils.countryCodeToEmoji('de'), '🇩🇪');
    expect(EmojiUtils.countryCodeToEmoji('IR'), '🇮🇷');
    expect(
      EmojiUtils.countryCodeToEmoji(''),
      '',
      reason: 'an empty code must not produce a garbage glyph',
    );
    expect(EmojiUtils.countryCodeToEmoji('xx'), '🇽🇽');
  });

  test('a location with no country still shows the IP', () {
    const region = '';
    const ip = '203.0.113.9';
    expect("${EmojiUtils.countryCodeToEmoji(region)} $ip".trim(), ip);
  });

  test('the label carries flag, IP and a cost slot', () {
    expect(
      NetworkUtils.outletLabel('de', '203.0.113.9', 0),
      '🇩🇪 203.0.113.9 (*)',
    );
  });

  test('(*) is replaced by how long the lookup took', () {
    expect(
      NetworkUtils.outletLabel('de', '203.0.113.9', 320),
      '🇩🇪 203.0.113.9 (320ms)',
    );
  });

  test('an empty location renders as nothing, not as "(*)"', () {
    expect(
      NetworkUtils.outletLabel('', '', 0),
      isEmpty,
      reason: 'an untested node must render no label at all',
    );
  });

  test('the cost is compact, and (*) means "never measured"', () {
    expect(NetworkUtils.outletCost(0), '*');
    expect(
      NetworkUtils.outletCost(-1),
      '*',
      reason: 'a negative cost is not a measurement',
    );
    expect(NetworkUtils.outletCost(1), '1ms');
    expect(NetworkUtils.outletCost(999), '999ms');
    expect(NetworkUtils.outletCost(1000), '1.0s');
    expect(NetworkUtils.outletCost(2500), '2.5s');
  });

  test('parses the Cloudflare trace body the lookup now uses', () {
    // The real shape, trimmed to the lines that matter.
    const trace = 'fl=123abc\nh=www.cloudflare.com\nip=37.156.154.81\n'
        'ts=1758740000.000\nvisit_scheme=http\nloc=IR\ntls=off\n';

    final parsed = NetworkUtils.parseOutletIpBody(trace);

    expect(parsed.item1, '37.156.154.81');
    expect(
      parsed.item2,
      'IR',
      reason: 'loc is the country the exit IP appears in',
    );
  });

  test('still parses the older JSON geoip body', () {
    const json = '{"ip":"203.0.113.9","country_code":"DE","city":"Berlin"}';

    final parsed = NetworkUtils.parseOutletIpBody(json);

    expect(parsed.item1, '203.0.113.9');
    expect(parsed.item2, 'DE');
  });

  test('a bare address body is taken as the IP, with no country', () {
    final parsed = NetworkUtils.parseOutletIpBody('  203.0.113.9  ');

    expect(parsed.item1, '203.0.113.9');
    expect(parsed.item2, isEmpty);
  });

  test('an empty body yields nothing rather than junk', () {
    final parsed = NetworkUtils.parseOutletIpBody('   ');

    expect(parsed.item1, isEmpty);
    expect(parsed.item2, isEmpty);
  });
}
