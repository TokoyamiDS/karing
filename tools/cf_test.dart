import 'dart:io';
import 'package:karing/app/utils/cloudflare_scanner.dart';
import 'package:karing/app/utils/cloudflare_utils.dart';

Future<void> main(List<String> args) async {
  final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 256 : 256;
  final ips = CloudflareScanner.generateCandidates(count);
  print("scanning $count candidate Cloudflare IPs...");
  final scanner = CloudflareScanner();
  final results = await scanner.scan(
    ips: ips,
    concurrency: 24,
    timeout: Duration(seconds: 5),
  );
  print("healthy CF edges: ${results.length}");
  for (final r in results.take(20)) {
    print("${r.latencyMs}ms  ${r.ip}  colo=${r.colo ?? '-'}");
  }
  if (results.isEmpty) {
    print("NO HEALTHY CF EDGES");
  }
  exit(0);
}
