import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/statistics_manager.dart';

/// The store is the part of the statistics feature that must not be wrong: it
/// is the only record of traffic that has already left the machine, so a bug
/// here silently loses history that cannot be recovered.
void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    StatisticsManager.close();
    tmp = await Directory.systemTemp.createTemp('karing_stats_test');
    dbPath = '${tmp.path}${Platform.pathSeparator}statistics.db';
    await StatisticsManager.open(path: dbPath);
  });

  tearDown(() async {
    StatisticsManager.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('accumulates increments into one row per destination', () {
    final day = DateTime(2026, 9, 18, 10);
    StatisticsManager.add(
      time: day,
      host: 'example.com',
      process: 'chrome.exe',
      outbound: 'proxy',
      uploadDelta: 100,
      downloadDelta: 900,
    );
    StatisticsManager.add(
      time: day,
      host: 'example.com',
      process: 'chrome.exe',
      outbound: 'proxy',
      uploadDelta: 50,
      downloadDelta: 450,
    );

    final rows = StatisticsManager.topByHost(StatisticsManager.dayKey(day));
    expect(rows.length, 1);
    expect(rows.first.upload, 150);
    expect(rows.first.download, 1350);
    expect(rows.first.total, 1500);
  });

  test('ranks destinations by total bytes, biggest first', () {
    final day = DateTime(2026, 9, 18, 10);
    void add(String host, int bytes) => StatisticsManager.add(
      time: day,
      host: host,
      process: 'chrome.exe',
      outbound: 'proxy',
      uploadDelta: 0,
      downloadDelta: bytes,
    );
    add('small.test', 10);
    add('huge.test', 100000);
    add('medium.test', 5000);

    final rows = StatisticsManager.topByHost(StatisticsManager.dayKey(day));
    expect(rows.map((r) => r.host).toList(), [
      'huge.test',
      'medium.test',
      'small.test',
    ]);
  });

  test('sums one host across processes and outbounds into a single line', () {
    final day = DateTime(2026, 9, 18, 10);
    StatisticsManager.add(
      time: day,
      host: 'example.com',
      process: 'chrome.exe',
      outbound: 'proxy',
      uploadDelta: 0,
      downloadDelta: 100,
    );
    StatisticsManager.add(
      time: day,
      host: 'example.com',
      process: 'firefox.exe',
      outbound: 'direct',
      uploadDelta: 0,
      downloadDelta: 250,
    );

    final rows = StatisticsManager.topByHost(StatisticsManager.dayKey(day));
    expect(rows.length, 1);
    expect(rows.first.total, 350);

    // ...but the per-process view keeps them apart, which is how you find the
    // program responsible.
    final byProcess = StatisticsManager.topByProcess(
      StatisticsManager.dayKey(day),
    );
    expect(byProcess.length, 2);
    expect(byProcess.first.process, 'firefox.exe');
  });

  test('keeps days separate', () {
    StatisticsManager.add(
      time: DateTime(2026, 9, 17, 23, 59),
      host: 'a.test',
      process: 'p',
      outbound: 'proxy',
      uploadDelta: 0,
      downloadDelta: 111,
    );
    StatisticsManager.add(
      time: DateTime(2026, 9, 18, 0, 1),
      host: 'a.test',
      process: 'p',
      outbound: 'proxy',
      uploadDelta: 0,
      downloadDelta: 222,
    );

    final days = StatisticsManager.days();
    expect(days, ['2026-09-18', '2026-09-17']);
    expect(
      StatisticsManager.totalsFor('2026-09-18').first.total,
      222,
    );
    expect(
      StatisticsManager.totalsFor('2026-09-17').first.total,
      111,
    );
  });

  test('a zero-byte sample writes nothing', () {
    final day = DateTime(2026, 9, 18, 10);
    StatisticsManager.add(
      time: day,
      host: 'example.com',
      process: 'chrome.exe',
      outbound: 'proxy',
      uploadDelta: 0,
      downloadDelta: 0,
    );
    expect(StatisticsManager.days(), isEmpty);
  });

  test('prune drops days past the retention window', () {
    final old = DateTime.now().subtract(const Duration(days: 30));
    StatisticsManager.add(
      time: old,
      host: 'old.test',
      process: 'p',
      outbound: 'proxy',
      uploadDelta: 0,
      downloadDelta: 1,
    );
    StatisticsManager.add(
      time: DateTime.now(),
      host: 'new.test',
      process: 'p',
      outbound: 'proxy',
      uploadDelta: 0,
      downloadDelta: 1,
    );

    StatisticsManager.prune(cacheDays: 7);

    final days = StatisticsManager.days();
    expect(days.length, 1);
    expect(
      StatisticsManager.topByHost(days.first).first.host,
      'new.test',
      reason: 'the day inside the window must survive',
    );
  });

  test('desensitize keeps only the registrable domain', () {
    expect(StatisticsManager.desensitizeHost('cdn.a.example.com', true),
        'example.com');
    expect(StatisticsManager.desensitizeHost('example.com', true), 'example.com');
    expect(
      StatisticsManager.desensitizeHost('cdn.a.example.com', false),
      'cdn.a.example.com',
      reason: 'turning the setting off must keep the full host',
    );
    expect(
      StatisticsManager.desensitizeHost('93.184.216.34', true),
      '93.184.216.34',
      reason: 'an IP has no registrable domain to fall back to',
    );
  });

  test('process name is the basename, not the whole path', () {
    expect(
      StatisticsManager.processName(r'C:\Program Files\Chrome\chrome.exe'),
      'chrome.exe',
    );
    expect(StatisticsManager.processName('/usr/bin/curl'), 'curl');
    expect(StatisticsManager.processName(''), '');
  });
}
