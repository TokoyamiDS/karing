import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';

/// A port can be unusable with no process holding it: inside the system's
/// ephemeral range it may be in use as the local end of an unrelated outgoing
/// connection, and inside a WinNAT/Hyper-V reserved block Windows refuses it.
/// Both kill the core on a bind error, so the app now checks before starting.
///
/// Note `save()` is a no-op here because `FileSaver` has no path until
/// `SettingManager.init()` runs, so these tests never touch a real profile.
void main() {
  test('a port that cannot be bound is moved to a free neighbour', () async {
    final squatter = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final busy = squatter.port;

    final proxy = SettingManager.getConfig().proxy;
    proxy.mixedRulePort = busy;

    await SettingManager.ensureCorePortsAvailable();

    expect(
      proxy.mixedRulePort,
      isNot(busy),
      reason: 'the core would fail to bind a port that is already taken',
    );

    await squatter.close();
  });

  test('a usable port is left exactly where it is', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final free = probe.port;
    await probe.close();

    final proxy = SettingManager.getConfig().proxy;
    proxy.mixedRulePort = free;

    await SettingManager.ensureCorePortsAvailable();

    expect(
      proxy.mixedRulePort,
      free,
      reason: 'ports must not wander when they are perfectly usable',
    );
  });

  test('the four bound ports end up distinct from each other', () async {
    await SettingManager.ensureCorePortsAvailable();

    final proxy = SettingManager.getConfig().proxy;
    final ports = [
      proxy.mixedRulePort,
      proxy.mixedForwardPort,
      proxy.scanPort,
      proxy.controlPort,
    ];

    expect(
      ports.toSet().length,
      ports.length,
      reason: 'two of the app\'s own listeners on one port means neither starts',
    );
  });
}
