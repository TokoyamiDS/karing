import 'dart:async';

import 'package:flutter/material.dart';
import 'package:karing/app/utils/speed_test.dart';
import 'package:karing/i18n/strings.g.dart';

/// Runs a throughput test and shows the numbers as they arrive.
///
/// The mode chooser is the point of this dialog. Download and upload answer
/// different questions and each costs up to twelve seconds, so "upload only"
/// has to be reachable without sitting through a download first.
///
/// Every string here comes from the existing `meta` namespace — no new keys, so
/// nothing to add across the other 27 locales.
class SpeedTestDialog extends StatefulWidget {
  const SpeedTestDialog({super.key, required this.proxyPort});

  /// The mixed port while the core is up; 0 dials directly.
  final int proxyPort;

  static Future<void> show(BuildContext context, int proxyPort) {
    return showDialog<void>(
      context: context,
      builder: (context) => SpeedTestDialog(proxyPort: proxyPort),
    );
  }

  @override
  State<SpeedTestDialog> createState() => _SpeedTestDialogState();
}

class _SpeedTestDialogState extends State<SpeedTestDialog> {
  /// Remembered across opens, so the usual choice is one tap away.
  static SpeedTestMode _lastMode = SpeedTestMode.both;

  SpeedTestMode _mode = _lastMode;
  SpeedTestPhase _phase = SpeedTestPhase.idle;
  double _mbps = 0;
  int _bytes = 0;
  SpeedTestResult? _result;
  bool _running = false;

  /// Set while a run is in flight, so Cancel has something to flip.
  SpeedTestCancel? _cancel;

  Future<void> _start() async {
    final cancel = SpeedTestCancel();
    setState(() {
      _cancel = cancel;
      _running = true;
      _phase = _mode == SpeedTestMode.upload
          ? SpeedTestPhase.upload
          : SpeedTestPhase.download;
      _mbps = 0;
      _bytes = 0;
      _result = null;
    });
    final result = await SpeedTest.run(
      proxyPort: widget.proxyPort,
      mode: _mode,
      cancel: cancel,
      onProgress: (phase, mbps, bytes) {
        if (!mounted) {
          return;
        }
        setState(() {
          _phase = phase;
          if (phase == SpeedTestPhase.download ||
              phase == SpeedTestPhase.upload) {
            _mbps = mbps;
            _bytes = bytes;
          }
        });
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _cancel = null;
      _result = result;
      _phase = result.ok ? SpeedTestPhase.done : SpeedTestPhase.failed;
    });
  }

  /// Stops the run and closes. The engine aborts its own sockets, so this
  /// returns immediately rather than waiting out the phase.
  void _cancelRun() {
    _cancel?.cancel();
    Navigator.pop(context);
  }

  String _phaseLabel() {
    switch (_phase) {
      case SpeedTestPhase.download:
        return t.meta.download;
      case SpeedTestPhase.upload:
        return t.meta.upload;
      case SpeedTestPhase.done:
        return t.meta.done;
      case SpeedTestPhase.failed:
        return _result?.error ?? t.meta.tips;
      case SpeedTestPhase.idle:
        return t.SettingsScreen.speedTest;
    }
  }

  String _fmt(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Widget _modeChip(SpeedTestMode mode, String label) {
    final selected = _mode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      // Changing the target mid-run would make the number meaningless.
      onSelected: _running
          ? null
          : (_) {
              setState(() {
                _mode = mode;
                _lastMode = mode;
                _result = null;
                _phase = SpeedTestPhase.idle;
                _mbps = 0;
                _bytes = 0;
              });
            },
    );
  }

  Widget _resultRow(String label, double mbps, int bytes, bool show) {
    if (!show) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${_fmt(mbps)} Mbps",
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "${(bytes / 1000000).toStringAsFixed(1)} MB",
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    // Which halves the current mode can report.
    final wantsDown = _mode != SpeedTestMode.upload;
    final wantsUp = _mode != SpeedTestMode.download;

    return AlertDialog(
      title: Text(t.SettingsScreen.speedTest),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _modeChip(SpeedTestMode.both, t.meta.all),
              _modeChip(SpeedTestMode.download, t.meta.download),
              _modeChip(SpeedTestMode.upload, t.meta.upload),
            ],
          ),
          const SizedBox(height: 14),
          if (_running) ...[
            Center(
              child: Text(
                _phaseLabel(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                "${_fmt(_mbps)} Mbps",
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Center(
              child: Text(
                "${(_bytes / 1000000).toStringAsFixed(1)} MB",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ] else if (result != null && result.ok) ...[
            _resultRow(t.meta.download, result.downloadMbps, result.downloadBytes, wantsDown),
            _resultRow(t.meta.upload, result.uploadMbps, result.uploadBytes, wantsUp),
          ] else if (result != null) ...[
            Text(
              result.error,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ] else
            Center(
              // Which path the number will describe. Worth stating: a result
              // through the tunnel and a result on the raw link are different
              // measurements, and the difference is otherwise invisible.
              child: Text(
                widget.proxyPort > 0 ? t.meta.systemProxy : t.meta.local,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
      actions: _running
          ? [
              // A run can take twenty-four seconds. Leaving only a disabled
              // Close meant committing to that.
              TextButton(
                onPressed: _cancelRun,
                child: Text(t.meta.cancel),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.meta.close),
              ),
              FilledButton(onPressed: _start, child: Text(t.meta.start)),
            ],
    );
  }
}
