import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/http_utils.dart';

/// A download must not be killed merely for taking a long time.
///
/// `httpDownload` used to race the *entire* transfer — body included — against
/// the per-request deadline. Any download that outlived it died partway and had
/// its partial file deleted, so a slow link could never finish anything large:
/// the reported symptom was "it downloads about 10 MB and then cancels".
///
/// The deadline now covers only the server answering; the transfer itself is
/// guarded against *stalling*.
void main() {
  late HttpServer server;
  late String base;
  late Directory dir;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    dir = await Directory.systemTemp.createTemp('karing_dl_test');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test(
    'a slow but progressing download survives a deadline shorter than the transfer',
    () async {
      // ~4 MB delivered over ~4 s, while the request deadline is 1 s. Under the
      // old code the deadline covered the body, so this could only ever fail.
      const chunkSize = 200 * 1024;
      const chunks = 20;
      server.listen((req) async {
        req.response.headers.contentLength = chunkSize * chunks;
        for (var i = 0; i < chunks; i++) {
          req.response.add(List<int>.filled(chunkSize, 65));
          await req.response.flush();
          await Future.delayed(const Duration(milliseconds: 200));
        }
        await req.response.close();
      });

      final out = '${dir.path}/slow.bin';
      final result = await HttpUtils.httpDownload(
        Uri.parse('$base/slow.bin'),
        out,
        null,
        'test',
        false,
        const Duration(seconds: 1),
      );

      expect(result.error, isNull, reason: result.error?.message);
      expect(
        await File(out).length(),
        chunkSize * chunks,
        reason: 'the whole body must land on disk, not just the first few chunks',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a transfer that goes silent is still abandoned rather than hanging forever',
    () async {
      // Headers arrive, a little data follows, then nothing at all. This must
      // fail on the stall guard — the deadline no longer bounds the body, so
      // without it a dead upstream would hang the download indefinitely.
      server.listen((req) async {
        req.response.headers.contentLength = 10 * 1024 * 1024;
        req.response.add(List<int>.filled(4096, 66));
        await req.response.flush();
        // deliberately never closes
      });

      final out = '${dir.path}/stalled.bin';
      final result = await HttpUtils.httpDownload(
        Uri.parse('$base/stalled.bin'),
        out,
        null,
        'test',
        false,
        const Duration(seconds: 5),
      );

      expect(
        result.error,
        isNotNull,
        reason: 'a silent upstream must not be waited on forever',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('a ranged request asks for the remainder and appends it', () async {
    const part = 100 * 1024;
    String? seenRange;
    server.listen((req) async {
      seenRange = req.headers.value(HttpHeaders.rangeHeader);
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $part-${part * 2 - 1}/${part * 2}',
      );
      req.response.add(List<int>.filled(part, 66)); // 'B'
      await req.response.close();
    });

    final out = '${dir.path}/resume.bin';
    await File(out).writeAsBytes(List<int>.filled(part, 65)); // 'A'

    final result = await HttpUtils.httpDownload(
      Uri.parse('$base/resume.bin'),
      out,
      null,
      'test',
      false,
      const Duration(seconds: 10),
      offset: part,
    );

    expect(result.error, isNull, reason: result.error?.message);
    expect(seenRange, 'bytes=$part-');
    final bytes = await File(out).readAsBytes();
    expect(bytes.length, part * 2, reason: 'the two halves must be joined');
    expect(bytes[0], 65, reason: 'the original prefix must survive');
    expect(bytes[part], 66, reason: 'the resumed half must follow it');
  });

  test('a server that ignores Range replaces the file instead of corrupting it',
      () async {
    const part = 100 * 1024;
    const fresh = 50 * 1024;
    server.listen((req) async {
      // No 206: this server does not support ranges and sends the whole file.
      req.response.statusCode = HttpStatus.ok;
      req.response.add(List<int>.filled(fresh, 67)); // 'C'
      await req.response.close();
    });

    final out = '${dir.path}/norange.bin';
    await File(out).writeAsBytes(List<int>.filled(part, 65)); // stale 'A'

    final result = await HttpUtils.httpDownload(
      Uri.parse('$base/norange.bin'),
      out,
      null,
      'test',
      false,
      const Duration(seconds: 10),
      offset: part,
    );

    expect(result.error, isNull, reason: result.error?.message);
    final bytes = await File(out).readAsBytes();
    expect(
      bytes.length,
      fresh,
      reason: 'appending to a stale partial would produce a corrupt file',
    );
    expect(bytes.every((b) => b == 67), isTrue);
  });
}
