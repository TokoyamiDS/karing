import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// A TUN inbound delivers raw IP packets, so the core has no hostname unless it
/// sniffs one. Every domain-based rule — `geosite-ir` above all — then matches
/// nothing, and Iranian traffic only escapes the proxy if DNS happened to hand
/// back an Iranian address.
///
/// That was a real bug: Iran routing looked correct through the mixed port,
/// where the client sends the hostname in the request, and silently did nothing
/// under TUN. These tests pin the sniff action's presence *and its position*,
/// because a sniff rule placed after the domain rules is as useless as none.
void main() {
  final setting = SettingManager.getConfig();
  final originalIranMode = setting.iranModeOverride;

  tearDown(() {
    setting.iranModeOverride = originalIranMode;
    setting.tls.enableServerless = false;
  });

  List<Map> builtRules({required bool tunMode}) {
    final outbounds = SingboxConfigBuilder.outbounds(
      "",
      {},
      {},
      null,
      [],
      null,
      {},
      SingboxExportType.karing,
    );
    final route = SingboxConfigBuilder.route(
      "",
      "",
      "",
      "",
      [],
      [],
      [],
      tunMode,
      outbounds,
      {},
      null,
      [],
      [],
      null,
      null,
      null,
      "",
      SingboxExportType.karing,
    );
    expect(route, isNotNull, reason: 'route() returned nothing');
    return ((route as Map)['rules'] as List).cast<Map>();
  }

  int sniffIndex(List<Map> rules) =>
      rules.indexWhere((r) => r['action'] == 'sniff');

  int iranRuleIndex(List<Map> rules) => rules.indexWhere(
    (r) => (r['rule_set'] as List?)?.contains('geosite-ir') == true,
  );

  test('TUN mode sniffs, and does so before the Iran domain rule', () {
    setting.iranModeOverride = true;
    final rules = builtRules(tunMode: true);

    final sniff = sniffIndex(rules);
    expect(sniff, isNonNegative, reason: 'no sniff rule under TUN');
    expect(
      (rules[sniff]['sniffer'] as List),
      containsAll(<String>['tls', 'http', 'quic']),
    );

    final iran = iranRuleIndex(rules);
    expect(iran, isNonNegative, reason: 'the geosite-ir rule is missing');
    expect(
      sniff,
      lessThan(iran),
      reason: 'sniff must run before the domain rules it exists to feed',
    );
  });

  test('sniff is not final, so the Iran rule still routes direct', () {
    setting.iranModeOverride = true;
    final rules = builtRules(tunMode: true);
    final sniff = rules[sniffIndex(rules)];
    expect(
      sniff.containsKey('outbound'),
      isFalse,
      reason: 'a final action here would stop matching and bypass the rules below',
    );
  });

  test('no sniff rule when neither TUN nor serverless is active', () {
    setting.iranModeOverride = true;
    setting.tls.enableServerless = false;
    final rules = builtRules(tunMode: false);
    expect(sniffIndex(rules), -1);
  });

  test('serverless mode sniffs even without TUN', () {
    setting.iranModeOverride = false;
    setting.tls.enableServerless = true;
    final rules = builtRules(tunMode: false);
    expect(sniffIndex(rules), isNonNegative);
  });
}
