import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';

/// The app runs several listeners at once, and two of them sharing a port means
/// the core cannot start at all — with a bind error that reads like a
/// permissions problem rather than a clash.
///
/// The scan inbound is the worst case: it is bound to **loopback** on the scan
/// port and routed straight to `direct` (so latency scanners measure the
/// physical NIC, not the tunnel), and a loopback binding is more specific than
/// the mixed inbound's `0.0.0.0`, so it silently shadows every loopback client.
///
/// Observed live: with `mixed_port == scan_port == 3068`, the app's own
/// exit-IP lookup connected to `127.0.0.1:3068`, hit the scan inbound, and
/// reported the user's **direct** IP (Tehran) instead of the selected node's.
void main() {
  SettingConfigItemProxy load(Map<String, dynamic> map) =>
      SettingConfigItemProxy()..fromJson(map);

  test('a scan port equal to the rule port is moved off it', () {
    final proxy = load({
      'mixed_port': 3068,
      'mixed_forword_port': 3066,
      'scan_port': 3068,
    });

    expect(
      proxy.scanPort,
      isNot(proxy.mixedRulePort),
      reason: 'a shared port shadows the mixed inbound on loopback',
    );
    expect(proxy.scanPort, isNot(proxy.mixedForwardPort));
  });

  test('a scan port equal to the forward port is moved off it', () {
    final proxy = load({
      'mixed_port': 3067,
      'mixed_forword_port': 3066,
      'scan_port': 3066,
    });

    expect(proxy.scanPort, isNot(proxy.mixedForwardPort));
    expect(proxy.scanPort, isNot(proxy.mixedRulePort));
  });

  test('a zero scan port resolves clear of both mixed ports', () {
    final proxy = load({'mixed_port': 3068, 'scan_port': 0});

    expect(proxy.scanPort, greaterThan(0));
    expect(
      proxy.scanPort,
      isNot(proxy.mixedRulePort),
      reason: 'the default is not safe once mixedPort has been moved onto it',
    );
  });

  test('genuinely distinct ports are left untouched', () {
    final proxy = load({'mixed_port': 3067, 'scan_port': 3068});

    expect(proxy.scanPort, 3068);
    expect(proxy.mixedRulePort, 3067);
  });

  test('a control port landing on a mixed port is moved off it', () {
    final proxy = load({
      'mixed_port': 3068,
      'mixed_forword_port': 3066,
      'scan_port': 3067,
      'control_port': 3068,
    });

    expect(proxy.controlPort, isNot(proxy.mixedRulePort));
    expect(proxy.controlPort, isNot(proxy.mixedForwardPort));
    expect(proxy.controlPort, isNot(proxy.scanPort));
  });

  test('the control port default is not safe once mixedPort moves onto it', () {
    final proxy = load({
      'mixed_port': 3057,
      'scan_port': 3068,
      'control_port': 3057,
    });

    expect(
      proxy.controlPort,
      isNot(proxy.mixedRulePort),
      reason: 'falling back to the default is useless if the default now clashes',
    );
  });
}
