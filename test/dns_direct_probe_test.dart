import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/dns_direct_probe.dart';

bool? _online;

/// The wire format must be a real DNS message (the core is not involved, so a
/// malformed packet looks exactly like a dead server); live probes only run
/// when the machine has any connectivity.
Future<bool> online() async {
  if (_online != null) {
    return _online!;
  }
  try {
    _online = (await InternetAddress.lookup('example.com')
            .timeout(const Duration(seconds: 3)))
        .isNotEmpty;
  } catch (_) {
    _online = false;
  }
  return _online!;
}

void main() {
  test('query is a well-formed DNS message', () {
    final q = DnsDirectProbe.buildQuery('example.com');
    expect(q.length, 29); // 12 header + 13 qname + 4 qtype/qclass
    expect(q.sublist(2, 4), [0x01, 0x00]); // flags: RD
    expect(q.sublist(4, 6), [0x00, 0x01]); // QDCOUNT = 1
    expect(q.sublist(6, 12), [0, 0, 0, 0, 0, 0]); // no answers/authority/additional
    expect(q.sublist(12), <int>[
      7, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, //  "example"
      3, 0x63, 0x6f, 0x6d, //  "com"
      0, //  root label
      0, 1, //  QTYPE = A
      0, 1, //  QCLASS = IN
    ]);
  });

  test('transaction id increments', () {
    final a = DnsDirectProbe.buildQuery('example.com');
    final b = DnsDirectProbe.buildQuery('example.com');
    expect(a.sublist(0, 2), isNot(b.sublist(0, 2)));
  });

  test('DoT query carries the 2-byte stream length', () async {
    final q = DnsDirectProbe.buildQuery('example.com');
    final f = DnsDirectProbe.framedQuery('example.com');
    expect(f.length, q.length + 2);
    expect((f[0] << 8) | f[1], q.length);
  });

  Future<void> probeOk(String server) async {
    if (!await online()) {
      markTestSkipped('no network');
      return;
    }
    final r = await DnsDirectProbe.probe(server, 'gstatic.com');
    if (!r.ok) {
      const networkish = [
        "timeout",
        "unreachable",
        "cannot be reached",
        "no route",
        "refused",
        "resolve",
      ];
      final err = r.error.toLowerCase();
      if (!networkish.any((e) => err.contains(e))) {
        fail('$server -> ${r.error}'); // protocol bug, not a network problem
      }
      markTestSkipped('$server -> ${r.error}');
      return;
    }
    expect(r.latencyMs, greaterThan(0));
  }

  test('udp probe', () => probeOk('udp://1.1.1.1'),
      timeout: const Timeout(Duration(seconds: 30)));
  test('dot probe', () => probeOk('tls://8.8.8.8'),
      timeout: const Timeout(Duration(seconds: 30)));
  test('doh probe', () => probeOk('https://dns.google/dns-query'),
      timeout: const Timeout(Duration(seconds: 30)));
  test('bad server fails instead of hanging', () async {
    final r = await DnsDirectProbe.probe('udp://240.0.0.1', 'gstatic.com',
        timeout: const Duration(seconds: 2));
    expect(r.ok, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('udp probe rejects a spoofed/foreign datagram', () async {
    // Bind a local "resolver" that answers the probe with a datagram whose
    // txid and QR bit do not match: the probe must not count it as healthy
    // (Iranian ISPs inject exactly this kind of reply on UDP/53).
    final server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = server.receive();
        if (dg != null) {
          server.send([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], dg.address, dg.port);
        }
      }
    });
    final r = await DnsDirectProbe.probe(
      'udp://127.0.0.1:${server.port}',
      'example.com',
      timeout: const Duration(seconds: 2),
    );
    server.close();
    expect(r.ok, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('udp probe accepts a matching response', () async {
    final server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = server.receive();
        if (dg == null) return;
        final q = dg.data;
        // echo the query back with QR set and RCODE 0, one answer
        final resp = List<int>.from(q);
        resp[2] = (resp[2] | 0x80) & 0xff;
        resp[3] = resp[3] & 0xf0;
        resp[6] = 0;
        resp[7] = 1;
        server.send(resp, dg.address, dg.port);
      }
    });
    final r = await DnsDirectProbe.probe(
      'udp://127.0.0.1:${server.port}',
      'example.com',
      timeout: const Duration(seconds: 2),
    );
    server.close();
    expect(r.ok, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
