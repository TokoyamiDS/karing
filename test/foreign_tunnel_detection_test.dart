import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/network_utils.dart';

/// Two full-tunnel clients each install a default route and rewrite DNS. That
/// is what makes Windows decide connectivity is lost and reset the WLAN
/// adapter — experienced as "the WiFi dropped and I had to wait for the driver
/// to come back". The app therefore refuses to add a second tunnel.
///
/// This heuristic decides whether the VPN runs in TUN mode at all, so the
/// negatives matter as much as the positives: a false positive silently
/// downgrades a perfectly good setup to proxy mode.
void main() {
  test('detects the tunnels seen on this machine, plus common clients', () {
    for (final name in [
      'xray_tun', // observed live alongside Karing
      'wintun',
      'tun0',
      'WireGuard Tunnel',
      'OpenVPN Connect DCO Adapter',
      'Tailscale',
      'ZeroTier One',
      'Radmin VPN',
      'sing-box',
      'Clash',
      'Hiddify',
      'Nekoray',
    ]) {
      expect(
        NetworkUtils.isForeignTunnelName(name),
        isTrue,
        reason: '$name belongs to another tunnelling client',
      );
    }
  });

  test('never mistakes our own tunnel for a foreign one', () {
    expect(NetworkUtils.isForeignTunnelName('karing'), isFalse);
    expect(NetworkUtils.isForeignTunnelName('Karing'), isFalse);
  });

  test('leaves ordinary adapters alone', () {
    for (final name in [
      'Ethernet',
      'Ethernet 5',
      'Wi-Fi',
      'vEthernet (Default Switch)',
      'vEthernet (WSL (Hyper-V firewall))',
      'VMware Network Adapter VMnet1',
      'VMware Network Adapter VMnet8',
      'Loopback Pseudo-Interface 1',
      'Bluetooth Network Connection',
      'PdaNet Broadband Connection',
    ]) {
      expect(
        NetworkUtils.isForeignTunnelName(name),
        isFalse,
        reason: '$name is a normal adapter; flagging it would disable TUN for nothing',
      );
    }
  });

  test('the Bypass choice survives a save/load cycle', () {
    final tun = SettingConfigItemTUN()..ignoreForeignTunnel = true;

    final restored = SettingConfigItemTUN.fromJsonStatic(tun.toJson());

    expect(
      restored.ignoreForeignTunnel,
      isTrue,
      reason: 'a bypass that does not persist would nag on every single launch',
    );
  });

  test('the check is on by default', () {
    expect(SettingConfigItemTUN.fromJsonStatic({}).ignoreForeignTunnel, isFalse);
  });
}
