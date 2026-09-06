// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/cloudflare_scanner.dart';
import 'package:karing/app/utils/sni_scanner.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/theme_config.dart';
import 'package:karing/screens/theme_define.dart';
import 'package:karing/screens/widgets/framework.dart';

/// Scans random IPs sampled across the official Cloudflare ranges, verifies
/// each with a real /cdn-cgi/trace request, and can apply the healthy edges
/// as SNI-Spoofing clean IPs (same flow as the SNI Scanner).
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

  @override
  void initState() {
    super.initState();
    final tls = SettingManager.getConfig().tls;
    _probeHostController.text = tls.sniSpoofingFakeSni.isNotEmpty
        ? tls.sniSpoofingFakeSni
        : CloudflareScanner.defaultProbeHost;
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
    final probeHost = _probeHostController.text.trim();
    final count = int.tryParse(_countController.text.trim()) ?? 256;
    if (probeHost.isEmpty || count < 8 || count > 4096) {
      await DialogUtils.showAlertDialog(
        context,
        "Probe host must not be empty and count must be 8..4096.",
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

  Future<void> _applyBest() async {
    if (_results.isEmpty) {
      await DialogUtils.showAlertDialog(
        context,
        "No healthy Cloudflare IP found yet.",
      );
      return;
    }
    const topN = 5;
    final best = _results.take(topN).toList();
    final tls = SettingManager.getConfig().tls;
    tls.sniSpoofingIps = best.map((r) => r.ip).toList();
    tls.sniSpoofingFakeSni = _probeHostController.text.trim();
    tls.enableSniSpoofing = true;
    tls.enableServerless = false;
    tls.cfScanResults = best
        .map((r) => "${r.ip}|${r.latencyMs}|${r.colo ?? ""}")
        .toList();
    SettingManager.setDirty(true);
    await SettingManager.save();
    if (!mounted) {
      return;
    }
    await DialogUtils.showAlertDialog(
      context,
      "Applied ${best.length} healthy CF IP(s), best ${best.first.latencyMs}ms"
      "${best.first.colo != null ? " @colo ${best.first.colo}" : ""}. "
      "SNI Spoofing enabled — reconnect to apply.",
    );
    setState(() {});
  }

  Future<void> _replaceNodes() async {
    if (_results.isEmpty) {
      await DialogUtils.showAlertDialog(
        context,
        "No healthy Cloudflare IP found yet.",
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
    final count =
        ServerManager.replaceCloudflareServerIps(best.map((r) => r.ip).toList());
    if (!mounted) {
      return;
    }
    await DialogUtils.showAlertDialog(
      context,
      count > 0
          ? "$count Cloudflare node(s) now dial the $topN fastest clean IPs.\n"
              "Connect (or reconnect) to apply.\n\n"
              "Turn off the Cloudflare card on the home screen to restore "
              "the original addresses."
          : "No Cloudflare nodes detected in your profiles yet.",
    );
    setState(() {});
  }

  Future<void> _restoreNodes() async {
    final count = ServerManager.restoreCloudflareServerIps();
    if (!mounted) {
      return;
    }
    await DialogUtils.showAlertDialog(
      context,
      count > 0
          ? "Original addresses restored for $count node(s). "
              "Connect (or reconnect) to apply."
          : "Nothing to restore.",
    );
    setState(() {});
  }

  Widget _buildReplacePanel(ThemeData theme) {
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
                    replaced ? "Clean IPs active" : "Use clean IPs",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    replaced
                        ? "CF nodes dial the fastest scanned IPs. Tap to undo."
                        : "Point all CF nodes at the fastest scanned IPs.",
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
                replaced ? "Active" : "Replace",
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
                    child: const Text(
                      "Cloudflare Scanner",
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: ThemeConfig.kFontWeightTitle,
                        fontSize: ThemeConfig.kFontSizeTitle,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: _results.isEmpty ? null : _applyBest,
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
                      decoration: const InputDecoration(
                        labelText:
                            "Probe host / SNI to apply (speed.cloudflare.com)",
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
                      decoration: const InputDecoration(
                        labelText: "Candidate IPs to sample (default 256)",
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _total == 0
                              ? "${_results.length} healthy (saved)"
                              : "$_done / $_total probed · ${_results.length} healthy",
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
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildReplacePanel(Theme.of(context)),
              const SizedBox(height: 8),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    itemCount: _results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final r = _results[index];
                      return Material(
                        borderRadius: ThemeDefine.kBorderRadius,
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
