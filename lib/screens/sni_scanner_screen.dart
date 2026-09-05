// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/sni_scanner.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/theme_config.dart';
import 'package:karing/screens/theme_define.dart';
import 'package:karing/screens/widgets/framework.dart';

/// Scans (clean IP × fake SNI) pairs by completing a real TLS handshake and
/// timing it — the local equivalent of the SNI-Finder / SNI-Spoofing scanner
/// family. The best pair can be applied straight into SNI Spoofing settings.
class SniScannerScreen extends LasyRenderingStatefulWidget {
  static RouteSettings routSettings() {
    return const RouteSettings(name: "SniScannerScreen");
  }

  const SniScannerScreen({super.key});

  @override
  State<SniScannerScreen> createState() => _SniScannerScreenState();
}

class _SniScannerScreenState extends LasyRenderingState<SniScannerScreen> {
  final SniScanner _scanner = SniScanner();
  final List<SniScanResult> _results = [];
  final TextEditingController _ipsController = TextEditingController();
  final TextEditingController _snisController = TextEditingController();
  bool _scanning = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    final tls = SettingManager.getConfig().tls;
    final ips = tls.sniSpoofingIps.isNotEmpty
        ? tls.sniSpoofingIps
        : SniScanner.defaultIps;
    _ipsController.text = ips.join(", ");
    final snis = <String>{
      if (tls.sniSpoofingFakeSni.isNotEmpty) tls.sniSpoofingFakeSni,
      ...SniScanner.defaultSniCandidates,
    }.toList();
    _snisController.text = snis.join(", ");
    super.initState();
  }

  @override
  void dispose() {
    _scanner.cancel();
    _ipsController.dispose();
    _snisController.dispose();
    super.dispose();
  }

  List<String> _parseList(String text) {
    return text
        .split(RegExp(r'[,\s\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _startScan() async {
    if (_scanning) {
      _scanner.cancel();
      setState(() {
        _scanning = false;
      });
      return;
    }
    final ips = _parseList(_ipsController.text);
    final snis = _parseList(_snisController.text);
    if (ips.isEmpty || snis.isEmpty) {
      await DialogUtils.showAlertDialog(
        context,
        "Add at least one IP and one SNI candidate.",
      );
      return;
    }
    setState(() {
      _scanning = true;
      _results.clear();
      _done = 0;
      _total = ips.length * snis.length;
    });
    await _scanner.scan(
      ips: ips,
      snis: snis,
      concurrency: 16,
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
      await DialogUtils.showAlertDialog(context, "No working pair found yet.");
      return;
    }
    final best = _results.first;
    final tls = SettingManager.getConfig().tls;
    // put the winning SNI first and prepend its IP so it is used first
    tls.sniSpoofingFakeSni = best.sni;
    final ips = _results
        .where((r) => r.sni == best.sni)
        .map((r) => r.ip)
        .toSet()
        .toList();
    if (ips.isNotEmpty) {
      tls.sniSpoofingIps = ips;
    }
    tls.enableSniSpoofing = true;
    tls.enableServerless = false;
    SettingManager.setDirty(true);
    await SettingManager.save();
    if (!mounted) {
      return;
    }
    await DialogUtils.showAlertDialog(
      context,
      "Applied: SNI ${best.sni} with ${ips.length} IP(s) "
      "(best ${best.latencyMs}ms). SNI Spoofing enabled — reconnect to apply.",
    );
    setState(() {});
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
                      "SNI Scanner",
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
                            _scanning ? Icons.stop_circle_outlined : Icons.bolt_outlined,
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
                      controller: _ipsController,
                      maxLines: 2,
                      enabled: !_scanning,
                      decoration: const InputDecoration(
                        labelText: "Clean IPs (comma separated)",
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _snisController,
                      maxLines: 2,
                      enabled: !_scanning,
                      decoration: const InputDecoration(
                        labelText: "SNI candidates (comma separated)",
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _total == 0
                              ? "Idle"
                              : "$_done / $_total probed · ${_results.length} working",
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
                                ClipboardData(text: "${r.ip} ${r.sni}"),
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
                                    r.sni,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    r.ip,
                                    overflow: TextOverflow.ellipsis,
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
