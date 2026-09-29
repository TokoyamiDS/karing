// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// One finished measurement.
class SpeedTestResult {
  /// Megabits per second.
  double downloadMbps = 0;
  double uploadMbps = 0;
  int downloadBytes = 0;
  int uploadBytes = 0;

  /// Empty when the run succeeded.
  String error = "";

  bool get ok => error.isEmpty && (downloadMbps > 0 || uploadMbps > 0);
}

/// Which half of the test is running, for the UI.
enum SpeedTestPhase { idle, download, upload, done, failed }

/// Which halves to measure.
///
/// Separate modes because they answer different questions and the two phases
/// cost twelve seconds each: someone checking why uploads crawl should not have
/// to sit through a download first.
enum SpeedTestMode { both, download, upload }

/// Lets a caller stop a run in flight.
///
/// A flag rather than a `Future` race: the phases own their sockets, and the
/// only way to unblock a read that is waiting on a stalled link is to close
/// them from the outside. The run checks this between chunks, and a watchdog
/// closes the sockets so a cancel lands even when nothing is arriving.
class SpeedTestCancel {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Measures real throughput through the running proxy.
///
/// Cloudflare's speedtest backend is the target — the same endpoints the
/// speed.cloudflare.com page itself uses:
///
///   GET  /__down?bytes=N   streams N bytes down
///   POST /__up             swallows whatever you send
///
/// Requests go through the app's mixed port when the core is up, so the number
/// reflects what the user actually gets, not the raw link.
///
/// Both phases are time-boxed rather than size-boxed: the point is a quick
/// answer on one tap, and a fixed byte count is either too small on a fast link
/// or stalls forever on a slow one.
class SpeedTest {
  static const String kDownUrl = "https://speed.cloudflare.com/__down?bytes=";
  static const String kUpUrl = "https://speed.cloudflare.com/__up";

  /// How long each half may run.
  static const Duration kPhaseTimeout = Duration(seconds: 12);

  /// Per-request ceiling, so a stall cannot hang the whole test.
  static const Duration kRequestTimeout = Duration(seconds: 20);

  /// Enough for a stable reading on a slow link, small enough not to stall.
  static const int kDownloadBytes = 25 * 1000 * 1000;

  static const int _uploadChunk = 64 * 1024;

  /// Runs the requested halves, download first when both are asked for.
  ///
  /// [onProgress] fires continuously with the live rate in Mbps and the bytes
  /// moved so far, so the caller can show a real-time number rather than a
  /// spinner. [proxyPort] of 0 dials directly.
  static Future<SpeedTestResult> run({
    required int proxyPort,
    SpeedTestMode mode = SpeedTestMode.both,
    SpeedTestCancel? cancel,
    void Function(SpeedTestPhase phase, double mbps, int bytes)? onProgress,
    Duration phaseTimeout = kPhaseTimeout,
  }) async {
    final result = SpeedTestResult();
    try {
      if (mode != SpeedTestMode.upload) {
        final down = await _download(
          proxyPort,
          phaseTimeout,
          (mbps, bytes) =>
              onProgress?.call(SpeedTestPhase.download, mbps, bytes),
          cancel,
        );
        result.downloadBytes = down.$1;
        result.downloadMbps = _mbps(down.$1, down.$2);
        if (down.$1 == 0 && !(cancel?.cancelled ?? false)) {
          result.error = "download: ${down.$3 == 200 ? 'no data' : 'HTTP ${down.$3}'}";
        }
      }

      if (mode != SpeedTestMode.download) {
        final up = await _upload(
          proxyPort,
          phaseTimeout,
          (mbps, bytes) => onProgress?.call(SpeedTestPhase.upload, mbps, bytes),
          cancel,
        );
        result.uploadBytes = up.$1;
        result.uploadMbps = _mbps(up.$1, up.$2);
        if (up.$1 == 0 && result.error.isEmpty && !(cancel?.cancelled ?? false)) {
          result.error = "upload: ${up.$3 == 200 ? 'no data' : 'HTTP ${up.$3}'}";
        }
      }

    } catch (err) {
      result.error = err.toString();
    }
    onProgress?.call(
      result.ok ? SpeedTestPhase.done : SpeedTestPhase.failed,
      0,
      0,
    );
    return result;
  }

  /// Bits per second to megabits per second.
  ///
  /// Measured against the time actually spent moving data, never the phase
  /// window — a test that finishes early (or a link that stalls) would
  /// otherwise be scored against time it never used.
  static double _mbps(int bytes, int elapsedMs) {
    if (bytes <= 0 || elapsedMs <= 0) {
      return 0;
    }
    return bytes * 8 / 1000000 / elapsedMs * 1000;
  }

  /// Closes [client] as soon as [cancel] flips, so a phase waiting on a stalled
  /// link stops promptly instead of sitting out its full window.
  static Timer? _watchdog(HttpClient client, SpeedTestCancel? cancel) {
    if (cancel == null) {
      return null;
    }
    return Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (cancel.cancelled) {
        client.close(force: true);
      }
    });
  }

  static HttpClient _client(int proxyPort) {
    final client = HttpClient();
    // Always state the route, never leave it to the environment. HttpClient
    // honours HTTP_PROXY/HTTPS_PROXY when no findProxy is set, so a desktop user
    // with a proxy exported would otherwise measure something the dialog does
    // not claim to be measuring.
    client.findProxy = (uri) =>
        proxyPort > 0 ? "PROXY 127.0.0.1:$proxyPort" : "DIRECT";
    client.connectionTimeout = const Duration(seconds: 10);
    return client;
  }

  /// Returns (bytes received, milliseconds spent, HTTP status).
  static Future<(int, int, int)> _download(
    int proxyPort,
    Duration window,
    void Function(double, int) onProgress,
    SpeedTestCancel? cancel,
  ) async {
    final client = _client(proxyPort);
    final watchdog = _watchdog(client, cancel);
    var received = 0;
    final sw = Stopwatch()..start();
    try {
      final req = await client
          .getUrl(Uri.parse("$kDownUrl$kDownloadBytes"))
          .timeout(kRequestTimeout);
      final res = await req.close().timeout(kRequestTimeout);
      if (res.statusCode != 200) {
        return (0, sw.elapsedMilliseconds, res.statusCode);
      }
      await for (final chunk in res) {
        if (cancel?.cancelled ?? false) {
          break;
        }
        received += chunk.length;
        final ms = sw.elapsedMilliseconds;
        if (ms > 0) {
          onProgress(received * 8 / 1000000 / ms * 1000, received);
        }
        if (sw.elapsed >= window) {
          break;
        }
      }
      // Stop pulling; the socket is closed below regardless.
      res.detachSocket().then((s) => s.destroy()).catchError((_) {});
    } catch (err) {
      if (received == 0) {
        rethrow;
      }
      // A timeout after moving data is a finished test, not a failure.
    } finally {
      watchdog?.cancel();
      client.close(force: true);
    }
    return (received, sw.elapsedMilliseconds, 200);
  }

  /// Returns (bytes sent, milliseconds spent, HTTP status).
  static Future<(int, int, int)> _upload(
    int proxyPort,
    Duration window,
    void Function(double, int) onProgress,
    SpeedTestCancel? cancel,
  ) async {
    final client = _client(proxyPort);
    final watchdog = _watchdog(client, cancel);
    var sent = 0;
    final sw = Stopwatch()..start();
    try {
      final req = await client.postUrl(Uri.parse(kUpUrl)).timeout(
            kRequestTimeout,
          );
      req.headers.contentType = ContentType.binary;
      // Incompressible: zeros would let a middlebox cheat the measurement.
      final block = Uint8List(_uploadChunk);
      final rnd = Random(1);
      for (var i = 0; i < block.length; i++) {
        block[i] = rnd.nextInt(256);
      }
      while (sw.elapsed < window && !(cancel?.cancelled ?? false)) {
        req.add(block);
        sent += block.length;
        // flush() pushes the buffer to the socket so the live rate is real and
        // the window is measured on the wire, not on buffering.
        await req.flush().timeout(kRequestTimeout);
        final ms = sw.elapsedMilliseconds;
        if (ms > 0) {
          onProgress(sent * 8 / 1000000 / ms * 1000, sent);
        }
      }
      final res = await req.close().timeout(kRequestTimeout);
      if (res.statusCode != 200) {
        return (0, sw.elapsedMilliseconds, res.statusCode);
      }
      await res.drain<void>();
    } catch (err) {
      if (sent == 0) {
        rethrow;
      }
    } finally {
      watchdog?.cancel();
      client.close(force: true);
    }
    return (sent, sw.elapsedMilliseconds, 200);
  }
}
