import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/cloudflare_utils.dart';
import 'package:karing/app/utils/sni_scanner.dart';

void main() {
  group('Cloudflare trace probe', () {
    test('never offers h2 to the HTTP/1.1 trace request', () {
      // Regression: advertising h2 made Cloudflare reply with binary HTTP/2
      // frames to the HTTP/1.1 request written below, so the `fl=`/`colo=`
      // check never matched. Every IP, however healthy, was reported as dead
      // and the Cloudflare scanner returned no results at all.
      expect(kCfTraceAlpn, isNot(contains('h2')));
      expect(kCfTraceAlpn, contains('http/1.1'));
    });
  });

  group('SniScanner.compare', () {
    SniScanResult pair(String ip, int ms, {bool verified = false}) =>
        SniScanResult(
          ip: ip,
          sni: 'example.com',
          latencyMs: ms,
          ok: true,
          verified: verified,
        );

    test('ranks a verified edge ahead of a faster unverified one', () {
      final results = [
        pair('1.1.1.1', 20),
        pair('2.2.2.2', 900, verified: true),
      ]..sort(SniScanner.compare);

      // Only a verified edge can serve the real domain in the Host header, so
      // latency must not outrank it.
      expect(results.first.ip, '2.2.2.2');
      expect(results.first.verified, isTrue);
    });

    test('orders equally-verified pairs by latency', () {
      final results = [
        pair('3.3.3.3', 300, verified: true),
        pair('4.4.4.4', 100, verified: true),
        pair('5.5.5.5', 200, verified: true),
      ]..sort(SniScanner.compare);

      expect(results.map((r) => r.latencyMs), [100, 200, 300]);
    });
  });

  group('SniScanResult.failureReason', () {
    SniScanResult failed(String error) => SniScanResult(
          ip: '1.1.1.1',
          sni: 'example.com',
          latencyMs: 0,
          ok: false,
          error: error,
        );

    test('is empty for a successful pair', () {
      expect(
        SniScanResult(
          ip: '1.1.1.1',
          sni: 'example.com',
          latencyMs: 10,
          ok: true,
        ).failureReason,
        isEmpty,
      );
    });

    test('classifies the failure so the UI can explain an empty scan', () {
      expect(failed('SocketException: Connection timed out').failureReason,
          'timeout');
      expect(failed('Connection reset by peer').failureReason, 'reset');
      expect(failed('HandshakeException: bad certificate').failureReason,
          'handshake');
      expect(failed('SocketException: Host unreachable').failureReason,
          'unreachable');
    });
  });

  group('template probe response parsing', () {
    test('reads the status from a real response head', () {
      expect(
        SniScanner.httpStatusOf('HTTP/1.1 101 Switching Protocols\r\n\r\n'),
        101,
      );
      expect(SniScanner.httpStatusOf('HTTP/1.1 200 OK\r\n\r\n'), 200);
      expect(SniScanner.httpStatusOf('HTTP/1.1 502 Bad Gateway\r\n\r\n'), 502);
      expect(SniScanner.httpStatusOf('HTTP/1.0 400 Bad Request\r\n\r\n'), 400);
    });

    test('returns 0 when there is no status line', () {
      expect(SniScanner.httpStatusOf(''), 0);
      expect(SniScanner.httpStatusOf('garbage'), 0);
    });

    test('rejects Cloudflare zone-error pages', () {
      // These arrive as an ordinary HTTP response, so without this check a
      // dead IP would be recommended as working.
      expect(
        SniScanner.isCloudflareZoneError(
          'HTTP/1.1 403 Forbidden\r\n\r\n<title>Error 1016</title>'
          'error code: 1016',
        ),
        isTrue,
      );
      expect(
        SniScanner.isCloudflareZoneError('error code: 1003'),
        isTrue,
      );
    });

    test('accepts a genuine WebSocket upgrade', () {
      expect(
        SniScanner.isCloudflareZoneError(
          'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
          'Connection: Upgrade\r\n\r\n',
        ),
        isFalse,
      );
    });
  });
}
