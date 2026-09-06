import 'dart:io';
import 'package:karing/app/utils/sni_scanner.dart';

Future<void> main() async {
  final scanner = SniScanner();
  final ips = [
    "199.181.197.1",
    "103.160.204.34",
    "185.193.30.94",
    "45.8.211.57",
    "159.112.235.52",
    "170.114.45.239",
    "188.42.88.24",
    "88.216.67.230",
    "45.130.125.75",
    "104.21.33.59",
    "188.114.96.0",
    "188.114.97.6",
  ];
  final snis = SniScanner.defaultSniCandidates.take(6).toList();
  print("scanning ${ips.length} IPs x ${snis.length} SNIs...");
  final results = await scanner.scan(
    ips: ips,
    snis: snis,
    concurrency: 24,
    timeout: Duration(seconds: 5),
  );
  print("working pairs: ${results.length}");
  for (final r in results.take(12)) {
    print("${r.latencyMs}ms  ${r.ip}  ${r.sni}  alpn=${r.alpn}");
  }
  if (results.isEmpty) {
    print("NO WORKING PAIRS");
  }
  exit(0);
}
