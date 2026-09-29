import 'dart:io';

import 'package:karing/app/utils/path_utils.dart';
import 'package:sqlite3/sqlite3.dart';

/// One aggregated row of traffic: how many bytes went to [host] from
/// [process] over [outbound] on a given day.
class StatisticsTrafficRow {
  final String host;
  final String process;
  final String outbound;
  final int upload;
  final int download;

  const StatisticsTrafficRow({
    required this.host,
    required this.process,
    required this.outbound,
    required this.upload,
    required this.download,
  });

  int get total => upload + download;
}

/// Persistent traffic history behind the Statistics screen.
///
/// The core only reports *currently open* connections, so a connection that
/// closes is gone from the API for good. That is why the history has to be
/// accumulated into a database while connected: without it, "where did my
/// network go" can only ever answer for the connections that happen to be open
/// at the moment you look. Keeping it in sqlite is also what lets the report
/// work after the VPN is stopped — the screen then reads the file and never
/// talks to the core.
class StatisticsManager {
  static Database? _db;
  static String _dbPath = "";

  /// Traffic is bucketed per calendar day, in local time, because the report is
  /// read as "today" / "yesterday" by a person, not as a rolling window.
  static String dayKey(DateTime time) {
    final local = time.toLocal();
    return "${local.year.toString().padLeft(4, '0')}-"
        "${local.month.toString().padLeft(2, '0')}-"
        "${local.day.toString().padLeft(2, '0')}";
  }

  static bool get isOpen => _db != null;

  static String get path => _dbPath;

  /// [path] is only passed by tests; the app always uses the profile's
  /// `datas/statistics.db`.
  static Future<Database> open({String? path}) async {
    if (_db != null) {
      return _db!;
    }
    _dbPath = path ?? await PathUtils.statisticsDBFilePath();
    final dir = Directory(File(_dbPath).parent.path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final db = sqlite3.open(_dbPath);
    // WAL keeps the recorder's frequent small writes from blocking the report's
    // reads; NORMAL is enough because a lost tail only costs statistics.
    db.execute("PRAGMA journal_mode=WAL");
    db.execute("PRAGMA synchronous=NORMAL");
    db.execute("""
      CREATE TABLE IF NOT EXISTS traffic (
        day TEXT NOT NULL,
        host TEXT NOT NULL,
        process TEXT NOT NULL,
        outbound TEXT NOT NULL,
        upload INTEGER NOT NULL DEFAULT 0,
        download INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (day, host, process, outbound)
      )
    """);
    _db = db;
    return db;
  }

  static void close() {
    _db?.close();
    _db = null;
    _dbPath = "";
  }

  /// A second, independent handle for reading a *different* statistics file —
  /// the developer "pick a DB" option. It is deliberately separate from the
  /// open handle so browsing an old file can never redirect the recorder's
  /// writes into it.
  static Database openReadOnly(String path) {
    return sqlite3.open(path, mode: OpenMode.readOnly);
  }

  /// Drops sub-domains and full executable paths before they reach the disk.
  /// `dataDesensitize` defaults to on, so the report answers "where did my
  /// traffic go" without keeping a record of every host a person visited.
  static String desensitizeHost(String host, bool desensitize) {
    if (!desensitize || host.isEmpty) {
      return host;
    }
    if (InternetAddress.tryParse(host) != null) {
      return host;
    }
    final parts = host.split('.');
    if (parts.length <= 2) {
      return host;
    }
    return parts.sublist(parts.length - 2).join('.');
  }

  static String processName(String processPath) {
    if (processPath.isEmpty) {
      return "";
    }
    final normalized = processPath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  /// Adds a sample. [uploadDelta] / [downloadDelta] are byte *increments* since
  /// the previous sample of the same connection, never cumulative totals —
  /// adding totals repeatedly would multiply the history on every poll.
  static void add({
    required DateTime time,
    required String host,
    required String process,
    required String outbound,
    required int uploadDelta,
    required int downloadDelta,
  }) {
    final db = _db;
    if (db == null || (uploadDelta <= 0 && downloadDelta <= 0)) {
      return;
    }
    db.execute(
      """
      INSERT INTO traffic(day, host, process, outbound, upload, download)
      VALUES(?, ?, ?, ?, ?, ?)
      ON CONFLICT(day, host, process, outbound) DO UPDATE SET
        upload = upload + excluded.upload,
        download = download + excluded.download
      """,
      [
        dayKey(time),
        host,
        process,
        outbound,
        uploadDelta,
        downloadDelta,
      ],
    );
  }

  /// Days that actually hold data, newest first — the report's selector is
  /// built from this rather than from a date range so it never offers a day
  /// that would come back empty.
  static List<String> days([Database? db]) {
    final handle = db ?? _db;
    if (handle == null) {
      return [];
    }
    final rows = handle.select(
      "SELECT DISTINCT day FROM traffic ORDER BY day DESC",
    );
    return rows.map((r) => r['day'] as String).toList();
  }

  static StatisticsTrafficRow _rowFrom(Row row) {
    return StatisticsTrafficRow(
      host: row['host'] as String,
      process: row['process'] as String,
      outbound: row['outbound'] as String,
      upload: row['upload'] as int,
      download: row['download'] as int,
    );
  }

  static List<StatisticsTrafficRow> _query(
    String sql,
    List<Object?> args, [
    Database? db,
  ]) {
    final handle = db ?? _db;
    if (handle == null) {
      return [];
    }
    return handle.select(sql, args).map(_rowFrom).toList();
  }

  /// Biggest destinations first — the "where has my network gone mostly" view.
  /// Rows are summed across processes and outbounds so one host is one line.
  static List<StatisticsTrafficRow> topByHost(
    String day, {
    int limit = 50,
    Database? db,
  }) {
    return _query(
      """
      SELECT host, '' AS process, '' AS outbound,
             SUM(upload) AS upload, SUM(download) AS download
      FROM traffic WHERE day = ?
      GROUP BY host
      ORDER BY (SUM(upload) + SUM(download)) DESC
      LIMIT ?
      """,
      [day, limit],
      db,
    );
  }

  /// The same ranking by executable, which is how you find the program that
  /// is actually responsible for the traffic.
  static List<StatisticsTrafficRow> topByProcess(
    String day, {
    int limit = 50,
    Database? db,
  }) {
    return _query(
      """
      SELECT process AS host, process, '' AS outbound,
             SUM(upload) AS upload, SUM(download) AS download
      FROM traffic WHERE day = ?
      GROUP BY process
      ORDER BY (SUM(upload) + SUM(download)) DESC
      LIMIT ?
      """,
      [day, limit],
      db,
    );
  }

  static List<StatisticsTrafficRow> totalsFor(String day, {Database? db}) {
    return _query(
      """
      SELECT '' AS host, '' AS process, '' AS outbound,
             SUM(upload) AS upload, SUM(download) AS download
      FROM traffic WHERE day = ?
      """,
      [day],
      db,
    );
  }

  /// Enforces both retention limits. [cacheDays] is the user's setting;
  /// [cacheSizeLimitMB] is a second, independent cap because a single day of
  /// heavy use can dwarf the age-based budget.
  static void prune({required int cacheDays, int? cacheSizeLimitMB}) {
    final db = _db;
    if (db == null) {
      return;
    }
    final cutoff = dayKey(DateTime.now().subtract(Duration(days: cacheDays)));
    db.execute("DELETE FROM traffic WHERE day < ?", [cutoff]);

    final limitMB = cacheSizeLimitMB ?? 0;
    if (limitMB <= 0) {
      return;
    }
    final limitBytes = limitMB * 1024 * 1024;
    // Drop whole days, oldest first, until the file fits. Deleting part of a
    // day would make the report show a total that never happened.
    while (_fileSizeBytes() > limitBytes) {
      final oldest = db.select(
        "SELECT MIN(day) AS day FROM traffic",
      );
      final day = oldest.isEmpty ? null : oldest.first['day'] as String?;
      if (day == null) {
        break;
      }
      db.execute("DELETE FROM traffic WHERE day = ?", [day]);
      db.execute("VACUUM");
    }
  }

  static int _fileSizeBytes() {
    try {
      final file = File(_dbPath);
      return file.existsSync() ? file.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }
}
