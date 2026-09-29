// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';
import 'package:karing/app/utils/sni_scanner.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/theme_config.dart';
import 'package:karing/screens/theme_define.dart';
import 'package:karing/screens/widgets/framework.dart';

/// Scans (clean IP × fake SNI) pairs by completing a real TLS handshake and
/// verifying the peer is a live Cloudflare edge — the local equivalent of the
/// SNI-Finder / SNI-Spoofing scanner family. The best pair can be applied
/// straight into SNI Spoofing settings.
class SniScannerScreen extends LasyRenderingStatefulWidget {
  static RouteSettings routSettings() {
    return const RouteSettings(name: "SniScannerScreen");
  }

  const SniScannerScreen({super.key});

  @override
  State<SniScannerScreen> createState() => _SniScannerScreenState();
}

/// Why a node cannot be used as a SNI-Spoofing template. Each case is a
/// distinct fix for the user, so they are reported separately.
enum SniTemplateRejection { noNode, noTls, reality, noTransport }

class _SniScannerScreenState extends LasyRenderingState<SniScannerScreen> {
  final SniScanner _scanner = SniScanner();
  final List<SniScanResult> _results = [];
  final Map<String, int> _failures = <String, int>{};
  final TextEditingController _ipsController = TextEditingController();
  final TextEditingController _snisController = TextEditingController();
  bool _scanning = false;
  int _done = 0;
  int _total = 0;
  bool _vpnOn = false;

  /// When on, each candidate IP is tested by replaying the selected node's real
  /// request through it, instead of only checking that a Cloudflare edge
  /// answers. This is the only mode that proves an IP works *for this node*.
  bool _templateMode = false;

  /// Why the selected node cannot be replayed as a template. Reported to the
  /// user because the old blanket "not CDN-backed" message misattributed the
  /// cause — a REALITY node is skipped for an entirely different reason, and
  /// blaming the transport sends people looking in the wrong place.
  SniTemplateRejection? _templateRejection;

  /// Builds the replay template from the selected node, or null when that node
  /// cannot carry SNI Spoofing at all. Checks run in the same order as
  /// `SingboxConfigBuilder._applySniSpoofing`, so the reported reason is the
  /// one that actually stopped it.
  SniTemplate? _selectedNodeTemplate() {
    _templateRejection = null;
    final outbound = SingboxConfigBuilder.buildOutbound(VPNService.getCurrent());
    if (outbound is! Map) {
      _templateRejection = SniTemplateRejection.noNode;
      return null;
    }
    final tls = outbound['tls'];
    if (tls is! Map || tls['enabled'] != true) {
      _templateRejection = SniTemplateRejection.noTls;
      return null;
    }
    if (tls['reality'] != null) {
      _templateRejection = SniTemplateRejection.reality;
      return null;
    }
    final transport = outbound['transport'];
    if (transport is! Map) {
      _templateRejection = SniTemplateRejection.noTransport;
      return null;
    }
    final server = outbound['server']?.toString() ?? "";
    if (server.isEmpty) {
      _templateRejection = SniTemplateRejection.noNode;
      return null;
    }
    // The real domain is what the CDN routes on: prefer an explicit Host
    // header, then the transport host field, then the node's own address —
    // matching what _applySniSpoofing guarantees is present.
    final headers = transport['headers'];
    var host = "";
    if (headers is Map && headers['Host'] != null) {
      host = headers['Host'].toString();
    }
    if (host.isEmpty) {
      host = transport['host']?.toString() ?? "";
    }
    if (host.isEmpty) {
      host = server;
    }
    return SniTemplate(
      host: host,
      path: transport['path']?.toString() ?? "/",
      transportType: transport['type']?.toString() ?? "",
    );
  }

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
    VPNService.getStarted().then((v) {
      if (mounted) {
        setState(() {
          _vpnOn = v;
        });
      }
    });
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

  String _reasonLabel(Translations tcontext, String reason) {
    switch (reason) {
      case "timeout":
        return tcontext.SniScannerScreen.reasonTimeout;
      case "reset":
        return tcontext.SniScannerScreen.reasonReset;
      case "handshake":
        return tcontext.SniScannerScreen.reasonHandshake;
      default:
        return tcontext.SniScannerScreen.reasonUnreachable;
    }
  }

  /// "timeout ×12 · reset ×3" — so a scan that found nothing still tells the
  /// user *why*, instead of leaving an empty list.
  String _failureSummary(Translations tcontext) {
    final parts = _failures.entries
        .where((e) => e.value > 0)
        .map((e) => "${_reasonLabel(tcontext, e.key)} ×${e.value}")
        .toList();
    return parts.join(" · ");
  }

  String _templateRejectionMessage(Translations tcontext) {
    final s = tcontext.SniScannerScreen;
    switch (_templateRejection) {
      case SniTemplateRejection.noTls:
        return s.templateNoTls;
      case SniTemplateRejection.reality:
        return s.templateReality;
      case SniTemplateRejection.noTransport:
        return s.templateNoTransport;
      case SniTemplateRejection.noNode:
        return s.templateNoNode;
      case null:
        return s.templateUnavailable;
    }
  }

  Future<void> _startScan() async {
    final tcontext = Translations.of(context);
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
        tcontext.SniScannerScreen.needInput,
      );
      return;
    }
    SniTemplate? template;
    if (_templateMode) {
      template = _selectedNodeTemplate();
      if (template == null) {
        await DialogUtils.showAlertDialog(
          context,
          _templateRejectionMessage(tcontext),
        );
        return;
      }
    }
    setState(() {
      _scanning = true;
      _results.clear();
      _failures.clear();
      _done = 0;
      _total = ips.length * snis.length;
    });
    await _scanner.scan(
      ips: ips,
      snis: snis,
      concurrency: 16,
      template: template,
      onResult: (result, done, total) {
        if (!mounted) {
          return;
        }
        setState(() {
          _done = done;
          _total = total;
          if (result.ok) {
            _results.add(result);
            _results.sort(SniScanner.compare);
          } else {
            final reason = result.failureReason;
            _failures[reason] = (_failures[reason] ?? 0) + 1;
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
    final tcontext = Translations.of(context);
    if (_results.isEmpty) {
      await DialogUtils.showAlertDialog(
        context,
        tcontext.SniScannerScreen.noResults,
      );
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
      tcontext.SniScannerScreen.applied(
        sni: best.sni,
        count: ips.length,
        ms: best.latencyMs,
      ),
    );
    setState(() {});
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
                      tcontext.SniScannerScreen.title,
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
                        onTap: _results.isEmpty ? null : _applyBest,
                        child: SizedBox(
                          width: 50,
                          height: 30,
                          child: Tooltip(
                            message: tcontext.SniScannerScreen.applyTooltip,
                            child: Icon(
                              Icons.done_all,
                              size: 26,
                              color: _results.isEmpty ? Colors.grey : null,
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _startScan,
                        child: SizedBox(
                          width: 50,
                          height: 30,
                          child: Tooltip(
                            message: _scanning
                                ? tcontext.SniScannerScreen.stopTooltip
                                : tcontext.SniScannerScreen.startTooltip,
                            child: Icon(
                              _scanning
                                  ? Icons.stop_circle_outlined
                                  : Icons.bolt_outlined,
                              size: 26,
                            ),
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
                      decoration: InputDecoration(
                        labelText: tcontext.SniScannerScreen.ipsLabel,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _snisController,
                      maxLines: 2,
                      enabled: !_scanning,
                      decoration: InputDecoration(
                        labelText: tcontext.SniScannerScreen.snisLabel,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _total == 0
                                ? tcontext.SniScannerScreen.idle
                                : tcontext.SniScannerScreen.progress(
                                    done: _done,
                                    total: _total,
                                    working: _results.length,
                                  ),
                            style: const TextStyle(fontSize: 12),
                          ),
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
                    if (_failures.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tcontext.SniScannerScreen.failures(
                            detail: _failureSummary(tcontext),
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _vpnOn
                            ? tcontext.SniScannerScreen.vpnOn
                            : tcontext.SniScannerScreen.vpnOff,
                        style: TextStyle(
                          fontSize: 11,
                          color: _vpnOn ? Colors.blue : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tcontext.SniScannerScreen.cdnOnlyHint,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tcontext.SniScannerScreen.templateMode,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Switch(
                          value: _templateMode,
                          onChanged: _scanning
                              ? null
                              : (value) {
                                  setState(() {
                                    _templateMode = value;
                                  });
                                },
                        ),
                      ],
                    ),
                    if (_templateMode)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tcontext.SniScannerScreen.templateModeHint,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _total > 0 && !_scanning
                                ? tcontext.SniScannerScreen.emptyHint
                                : tcontext.SniScannerScreen.startHint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      )
                    : Scrollbar(
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
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.sni,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              r.verified
                                                  ? (r.status > 0
                                                      // Template mode: the
                                                      // status is the proof.
                                                      ? "HTTP ${r.status}"
                                                      : tcontext
                                                          .SniScannerScreen
                                                          .verified(
                                                          colo: r.colo,
                                                        ))
                                                  : tcontext.SniScannerScreen
                                                      .unverified,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: r.verified
                                                    ? Colors.green
                                                    : Colors.grey,
                                              ),
                                            ),
                                          ],
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
