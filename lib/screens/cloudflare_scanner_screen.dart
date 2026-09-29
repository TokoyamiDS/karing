// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/biz.dart';
import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/clash_api.dart';
import 'package:karing/app/utils/cloudflare_scanner.dart';
import 'package:karing/app/utils/cloudflare_utils.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/scan_dialer.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/theme_config.dart';
import 'package:karing/screens/theme_define.dart';
import 'package:karing/screens/widgets/framework.dart';

/// One CF-labeled profile node with its measured latencies.
/// directMs/coreMs: null = not tested, -1 = failed, >0 = milliseconds.
class _CfNodeLatency {
  final ProxyConfig server;
  int? directMs;
  int? coreMs;
  _CfNodeLatency(this.server);
}

/// Scans random IPs sampled across the official Cloudflare ranges, verifies
/// each with a real /cdn-cgi/trace request, and can point the CF-fronted
/// profile nodes at the fastest healthy edges (clean-IP replacement; the
/// nodes' own SNI is left untouched).
class CloudflareScannerScreen extends LasyRenderingStatefulWidget {
  static RouteSettings routSettings() {
    return const RouteSettings(name: "CloudflareScannerScreen");
  }

  const CloudflareScannerScreen({super.key});

  @override
  State<CloudflareScannerScreen> createState() =>
      _CloudflareScannerScreenState();
}

class _CloudflareScannerScreenState
    extends LasyRenderingState<CloudflareScannerScreen> {
  final CloudflareScanner _scanner = CloudflareScanner();
  final List<CfScanResult> _results = [];
  final TextEditingController _probeHostController = TextEditingController();
  final TextEditingController _countController = TextEditingController();
  bool _scanning = false;
  int _done = 0;
  int _total = 0;
  bool _vpnOn = false;

  // CF nodes latency panel state
  List<_CfNodeLatency> _nodeLatencies = [];
  bool _testingNodes = false;

  @override
  void initState() {
    super.initState();
    final tls = SettingManager.getConfig().tls;
    _probeHostController.text = CloudflareScanner.defaultProbeHost;
    _countController.text = "256";
    final saved = tls.cfScanResults;
    for (final entry in saved) {
      final parts = entry.split("|");
      if (parts.length < 2) {
        continue;
      }
      final latency = int.tryParse(parts[1]) ?? 99999;
      _results.add(
        CfScanResult(
          ip: parts[0],
          latencyMs: latency,
          ok: true,
          colo: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
        ),
      );
    }
    _results.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    VPNService.getStarted().then((v) {
      if (mounted) {
        setState(() {
          _vpnOn = v;
        });
      }
    });
  }

  @override
  void dispose() {
    _scanner.cancel();
    _probeHostController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_scanning) {
      _scanner.cancel();
      setState(() {
        _scanning = false;
      });
      return;
    }
    final tcontext = Translations.of(context);
    final probeHost = _probeHostController.text.trim();
    final count = int.tryParse(_countController.text.trim()) ?? 256;
    if (probeHost.isEmpty || count < 8 || count > 4096) {
      await DialogUtils.showAlertDialog(
        context,
        tcontext.CloudflareScannerScreen.invalidInput,
      );
      return;
    }
    final ips = CloudflareScanner.generateCandidates(count);
    setState(() {
      _scanning = true;
      _results.clear();
      _done = 0;
      _total = ips.length;
    });
    await _scanner.scan(
      ips: ips,
      probeHost: probeHost,
      concurrency: 24,
      onResult: (result, done, total) {
        if (!mounted) {
          return;
        }
        setState(() {
          _done = done;
          _total = total;
          if (result.ok) {
            _results.add(result);
            _results.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
          }
        });
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _scanning = false;
    });
  }

  Future<void> _replaceNodes() async {
    final tcontext = Translations.of(context);
    if (_results.isEmpty) {
      await DialogUtils.showAlertDialog(
        context,
        tcontext.CloudflareScannerScreen.noHealthy,
      );
      return;
    }
    const topN = 8;
    final best = _results.take(topN).toList();
    final tls = SettingManager.getConfig().tls;
    tls.cfScanResults = best
        .map((r) => "${r.ip}|${r.latencyMs}|${r.colo ?? ""}")
        .toList();
    await SettingManager.save();
    final count = await ServerManager.replaceCloudflareServerIps(
      best.map((r) => r.ip).toList(),
    );
    if (!mounted) {
      return;
    }
    if (count > 0) {
      // Marked dirty above: this applies the new config immediately when the
      // VPN is up, and starts it (with the clean IPs) when it is down.
      await Biz.startOrRestartIfDirtyVPN(context, "cloudflare_replace");
      if (!mounted) {
        return;
      }
    }
    await DialogUtils.showAlertDialog(
      context,
      count > 0
          ? tcontext.CloudflareScannerScreen.replaceDone(
              count: count,
              topN: topN,
            )
          : tcontext.CloudflareScannerScreen.noCfNodes,
    );
    setState(() {});
  }

  Future<void> _restoreNodes() async {
    final tcontext = Translations.of(context);
    final count = await ServerManager.restoreCloudflareServerIps();
    if (!mounted) {
      return;
    }
    if (count > 0) {
      await Biz.startOrRestartIfDirtyVPN(context, "cloudflare_restore");
      if (!mounted) {
        return;
      }
    }
    await DialogUtils.showAlertDialog(
      context,
      count > 0
          ? tcontext.CloudflareScannerScreen.restoreDone(count: count)
          : tcontext.CloudflareScannerScreen.nothingToRestore,
    );
    setState(() {});
  }

  /// Latency-tests every Cloudflare-labeled node in the profiles WITHOUT
  /// touching their configuration:
  /// - direct: TLS handshake to the node's own address/port (works VPN-off)
  /// - core:   clash API delay through the node (works VPN-on, reflects the
  ///           full outbound incl. SNI spoofing / clean-IP replacement)
  Future<void> _testNodeLatencies() async {
    if (_testingNodes) {
      return;
    }
    final tcontext = Translations.of(context);
    final nodes = ServerManager.getCloudflareServers();
    if (nodes.isEmpty) {
      await DialogUtils.showAlertDialog(
        context,
        tcontext.CloudflareScannerScreen.noCfNodesFound,
      );
      return;
    }
    setState(() {
      _testingNodes = true;
      _nodeLatencies = nodes.map(_CfNodeLatency.new).toList();
    });
    final vpnOn = await VPNService.getStarted();
    if (mounted && vpnOn != _vpnOn) {
      setState(() {
        _vpnOn = vpnOn;
      });
    }
    final probeHost = _probeHostController.text.trim().isNotEmpty
        ? _probeHostController.text.trim()
        : CloudflareScanner.defaultProbeHost;
    for (final node in _nodeLatencies) {
      // direct probe: dial the node's own address on the real direct path
      final host = node.server.server.trim();
      final port = node.server.port > 0 ? node.server.port : 443;
      final isLiteral = InternetAddress.tryParse(host) != null;
      if (isLiteral && port == 443) {
        final r = await cfProbeTrace(host, probeHost: probeHost);
        node.directMs = r.ok ? r.latencyMs : -1;
      } else {
        // domain or non-443: plain TCP timing via a resolving connect
        final r = await _tcpTiming(host, port);
        node.directMs = r;
      }
      // core delay: only meaningful while the VPN is running
      if (vpnOn) {
        final result = await ClashApi.getDelay(
          SettingManager.getConfig().proxy.controlPort,
          node.server.tag,
          SettingManager.getConfig().urlTestTimeout,
          targetUrl: SettingManager.getConfig().urlTest,
        );
        node.coreMs = result.error == null
            ? (int.tryParse(result.data ?? "") ?? -1)
            : -1;
      }
      if (!mounted) {
        return;
      }
      setState(() {});
    }
    if (!mounted) {
      return;
    }
    _nodeLatencies.sort((a, b) {
      final av = (a.directMs == null || a.directMs! <= 0) ? 1 << 30 : a.directMs!;
      final bv = (b.directMs == null || b.directMs! <= 0) ? 1 << 30 : b.directMs!;
      return av.compareTo(bv);
    });
    setState(() {
      _testingNodes = false;
    });
  }

  static Future<int> _tcpTiming(String host, int port) async {
    final sw = Stopwatch()..start();
    Socket? s;
    try {
      // ScanDialer: through the core's direct scan channel while the VPN is
      // up (avoids FakeIP for domains), plain socket otherwise.
      s = await ScanDialer.connect(host, port);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      try {
        s?.destroy();
      } catch (_) {}
    }
  }

  Widget _buildNodeLatencyPanel() {
    final tcontext = Translations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, color: Colors.blue, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tcontext.CloudflareScannerScreen.existingNodes(
                      count: _nodeLatencies.length,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: _testingNodes ? null : _testNodeLatencies,
                  icon: _testingNodes
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: RepaintBoundary(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.bolt, size: 16),
                  label: Text(
                    _testingNodes
                        ? tcontext.CloudflareScannerScreen.testing
                        : tcontext.CloudflareScannerScreen.test,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _vpnOn
                  ? tcontext.CloudflareScannerScreen.directCoreOn
                  : tcontext.CloudflareScannerScreen.directCoreOff,
              style: const TextStyle(fontSize: 11),
            ),
            ..._nodeLatencies.map((n) {
              Widget ms(int? v, {bool bold = false}) {
                final text = v == null
                    ? "—"
                    : (v < 0 ? "fail" : "$v ms");
                final color = v == null || v < 0
                    ? Colors.red
                    : (v < 300
                        ? Colors.green
                        : (v < 800 ? Colors.orange : Colors.red));
                return SizedBox(
                  width: 74,
                  child: Text(
                    text,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: bold ? FontWeight.bold : null,
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        n.server.remark.isNotEmpty
                            ? n.server.remark
                            : n.server.tag,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        n.server.server,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    ms(n.directMs, bold: true),
                    ms(n.coreMs),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildReplacePanel(ThemeData theme) {
    final tcontext = Translations.of(context);
    final replaced = ServerManager.hasReplacedCfServers();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: replaced
              ? Colors.green.withValues(alpha: 0.10)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: replaced
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.orange.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              replaced ? Icons.swap_horiz : Icons.shield_outlined,
              color: replaced ? Colors.green : Colors.orange,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    replaced
                        ? tcontext.CloudflareScannerScreen.cleanIpsActive
                        : tcontext.CloudflareScannerScreen.useCleanIps,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    replaced
                        ? tcontext.CloudflareScannerScreen.cfNodesDialFastest
                        : tcontext.CloudflareScannerScreen.pointCfNodes,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: replaced ? Colors.green : Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: _results.isEmpty ? null : (replaced ? null : _replaceNodes),
              icon: Icon(replaced ? Icons.check : Icons.bolt, size: 18),
              label: Text(
                replaced
                    ? tcontext.CloudflareScannerScreen.active
                    : tcontext.CloudflareScannerScreen.replace,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (replaced) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: _restoreNodes,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.undo, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tcontext = Translations.of(context);
    Size windowSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: PreferredSize(preferredSize: Size.zero, child: AppBar()),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox(
                      width: 50,
                      height: 30,
                      child: Icon(Icons.arrow_back_ios_outlined, size: 26),
                    ),
                  ),
                  SizedBox(
                    width: windowSize.width - 50 * 3,
                    child: Text(
                      tcontext.CloudflareScannerScreen.title,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: ThemeConfig.kFontWeightTitle,
                        fontSize: ThemeConfig.kFontSizeTitle,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: _results.isEmpty ? null : _replaceNodes,
                        child: SizedBox(
                          width: 50,
                          height: 30,
                          child: Icon(
                            Icons.done_all,
                            size: 26,
                            color: _results.isEmpty ? Colors.grey : null,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _startScan,
                        child: SizedBox(
                          width: 50,
                          height: 30,
                          child: Icon(
                            _scanning
                                ? Icons.stop_circle_outlined
                                : Icons.bolt_outlined,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Column(
                  children: [
                    TextField(
                      controller: _probeHostController,
                      maxLines: 1,
                      enabled: !_scanning,
                      decoration: InputDecoration(
                        labelText:
                            tcontext.CloudflareScannerScreen.probeHostLabel,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _countController,
                      maxLines: 1,
                      enabled: !_scanning,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: tcontext
                            .CloudflareScannerScreen.candidateCountLabel,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _total == 0
                              ? tcontext.CloudflareScannerScreen.healthySaved(
                                  count: _results.length,
                                )
                              : tcontext.CloudflareScannerScreen.progress(
                                  done: _done,
                                  total: _total,
                                  count: _results.length,
                                ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (_scanning)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: RepaintBoundary(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _vpnOn
                          ? tcontext.CloudflareScannerScreen.vpnOn
                          : tcontext.CloudflareScannerScreen.vpnOff,
                      style: TextStyle(
                        fontSize: 11,
                        color: _vpnOn ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildReplacePanel(Theme.of(context)),
              const SizedBox(height: 8),
              _buildNodeLatencyPanel(),
              const SizedBox(height: 8),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: _total > 0 && !_scanning
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  tcontext
                                      .CloudflareScannerScreen.emptyHint,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      )
                    : Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    itemCount: _results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final r = _results[index];
                      final isTop5 = index < 5;
                      final isTop8 = index < 8;
                      return Material(
                        borderRadius: ThemeDefine.kBorderRadius,
                        color: isTop5
                            ? Colors.green.withValues(alpha: 0.14)
                            : (isTop8
                                ? Colors.green.withValues(alpha: 0.07)
                                : null),
                        child: InkWell(
                          onTap: () async {
                            try {
                              await Clipboard.setData(
                                ClipboardData(text: r.ip),
                              );
                            } catch (_) {}
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                if (isTop8) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isTop5
                                          ? Colors.green
                                          : Colors.green.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    r.ip,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    r.colo ?? "",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    "${r.latencyMs}ms",
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      color: r.latencyMs < 300
                                          ? Colors.green
                                          : (r.latencyMs < 800
                                                ? Colors.orange
                                                : Colors.red),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (BuildContext context, int index) {
                      return const Divider(height: 1, thickness: 0.3);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
