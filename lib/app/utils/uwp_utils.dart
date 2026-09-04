import 'dart:io';

import 'package:karing/app/runtime/return_result.dart';

/// A UWP app mapping (loopback exemption list).
class UWPMapping {
  String sid = "";
  String name = "";
  String path = "";
}

/// UWP loopback exemption helpers via CheckNetIsolation.exe.
class UWPUtils {
  static Future<List<UWPMapping>> getMappings() async {
    final out = <UWPMapping>[];
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-AppxPackage | ForEach-Object { "{0}|{1}|{2}" -f \$_.PackageFamilyName, \$_.Name, \$_.InstallLocation }'
        ],
      );
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          final parts = line.trim().split('|');
          if (parts.length == 3) {
            final m = UWPMapping();
            m.sid = parts[0];
            m.name = parts[1];
            m.path = parts[2];
            out.add(m);
          }
        }
      }
    } catch (_) {}
    return out;
  }

  static Future<ReturnResult<Set<String>>> getNetIsolation() async {
    final out = <String>{};
    try {
      final result = await Process.run(
        'checknetisolation',
        ['LoopbackExempt', '-s'],
      );
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          final m = RegExp(r'-p=([\S]+)').firstMatch(line);
          if (m != null) {
            out.add(m.group(1)!);
          }
        }
      }
      return ReturnResult(data: out);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<ReturnResultError?> SetNetIsolation(
      Set<String> sids, bool add) async {
    try {
      final op = add ? '-a' : '-d';
      for (final sid in sids) {
        final result = await Process.run(
          'checknetisolation',
          ['LoopbackExempt', op, 'p=$sid'],
        );
        if (result.exitCode != 0) {
          return ReturnResultError(result.stderr.toString());
        }
      }
      return null;
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }

  static Future<ReturnResultError?> ClearNetIsolation() async {
    try {
      final result = await Process.run(
        'checknetisolation',
        ['LoopbackExempt', '-c'],
      );
      if (result.exitCode != 0) {
        return ReturnResultError(result.stderr.toString());
      }
      return null;
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }
}
