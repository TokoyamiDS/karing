import 'package:flutter/material.dart';

import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/modules/statistics_manager.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/theme_config.dart';
// `Row` is hidden because package:sqlite3 exports its own Row, which would
// otherwise shadow the Flutter widget of the same name.
import 'package:sqlite3/sqlite3.dart' hide Row;

/// Per-day traffic report, ranked by destination and by application.
///
/// Reads only from the statistics database, never from the core, so it keeps
/// working after the VPN is stopped — which is the point of recording the
/// history in the first place.
class StatisticsRecordsScreen extends StatefulWidget {
  final String dbPath;
  final bool currentDB;
  const StatisticsRecordsScreen({
    super.key,
    required this.dbPath,
    required this.currentDB,
  });

  static RouteSettings routSettings() {
    return const RouteSettings(name: "/statistics_records");
  }

  @override
  State<StatisticsRecordsScreen> createState() =>
      _StatisticsRecordsScreenState();
}

class _StatisticsRecordsScreenState extends State<StatisticsRecordsScreen> {
  /// Only set when browsing a *different* file via the developer picker; the
  /// live database is read through the shared handle instead.
  Database? _handle;

  List<String> _days = [];
  String _day = "";
  StatisticsTrafficRow? _total;
  List<StatisticsTrafficRow> _byHost = [];
  List<StatisticsTrafficRow> _byProcess = [];
  bool _loading = true;
  bool _unreadable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _handle?.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _unreadable = false;
    });

    Database? handle;
    if (widget.currentDB) {
      await StatisticsManager.open();
    } else {
      // A picked file may not be a statistics database at all, so this is the
      // one place that has to tolerate a bad input rather than assert.
      try {
        handle = StatisticsManager.openReadOnly(widget.dbPath);
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _unreadable = true;
          _loading = false;
        });
        return;
      }
    }
    _handle = handle;

    final days = StatisticsManager.days(handle);
    if (!mounted) {
      return;
    }
    setState(() {
      _days = days;
      _day = days.isEmpty ? "" : days.first;
      _loading = false;
    });
    _selectDay(_day);
  }

  void _selectDay(String day) {
    if (day.isEmpty) {
      setState(() {
        _day = "";
        _total = null;
        _byHost = [];
        _byProcess = [];
      });
      return;
    }
    final totals = StatisticsManager.totalsFor(day, db: _handle);
    setState(() {
      _day = day;
      _total = totals.isEmpty ? null : totals.first;
      _byHost = StatisticsManager.topByHost(day, db: _handle);
      _byProcess = StatisticsManager.topByProcess(day, db: _handle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tcontext = Translations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.currentDB ? tcontext.meta.statistics : widget.dbPath,
        ),
      ),
      body: _buildBody(tcontext),
    );
  }

  Widget _buildBody(Translations tcontext) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_unreadable) {
      return _centered(tcontext.StatisticsRecordsScreen.noStatisticsAvailable);
    }
    if (_days.isEmpty) {
      // Distinguish "nothing recorded yet" from "recording is switched off",
      // because the second one has an obvious fix and the first does not.
      return _centered(
        SettingManager.getConfig().statistics.enable
            ? tcontext.StatisticsRecordsScreen.noStatisticsAvailable
            : tcontext.StatisticsRecordsScreen.enableHint,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _buildDayPicker(),
        const SizedBox(height: 12),
        _buildSummary(tcontext),
        const SizedBox(height: 16),
        _buildSection(
          tcontext,
          tcontext.StatisticsRecordsScreen.byDestination,
          _byHost,
          (row) => row.host.isEmpty
              ? tcontext.StatisticsRecordsScreen.unknownDestination
              : row.host,
        ),
        const SizedBox(height: 16),
        _buildSection(
          tcontext,
          tcontext.StatisticsRecordsScreen.byApp,
          _byProcess,
          (row) => row.process.isEmpty
              ? tcontext.StatisticsRecordsScreen.unknownDestination
              : row.process,
        ),
      ],
    );
  }

  Widget _centered(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildDayPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final day in _days)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(day),
                selected: day == _day,
                onSelected: (_) => _selectDay(day),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary(Translations tcontext) {
    final total = _total;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tcontext.StatisticsRecordsScreen.total,
                  style: TextStyle(
                    fontSize: ThemeConfig.kFontSizeListSubItem,
                    fontWeight: ThemeConfig.kFontWeightListSubItem,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ProxyConfUtils.convertTrafficToStringDouble(total?.total ?? 0),
                  style: const TextStyle(
                    fontSize: ThemeConfig.kFontSizeTitle,
                    fontWeight: ThemeConfig.kFontWeightTitle,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${tcontext.meta.upload} "
                  "${ProxyConfUtils.convertTrafficToStringDouble(total?.upload ?? 0)}",
                  style: const TextStyle(
                    fontSize: ThemeConfig.kFontSizeListSubItem,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${tcontext.meta.download} "
                  "${ProxyConfUtils.convertTrafficToStringDouble(total?.download ?? 0)}",
                  style: const TextStyle(
                    fontSize: ThemeConfig.kFontSizeListSubItem,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    Translations tcontext,
    String title,
    List<StatisticsTrafficRow> rows,
    String Function(StatisticsTrafficRow) label,
  ) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    // Bars are relative to the largest row in *this* section, so the ranking
    // stays readable whether the top entry is 10 MB or 10 GB.
    final max = rows.first.total == 0 ? 1 : rows.first.total;
    final grandTotal = _total?.total ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: ThemeConfig.kFontSizeListItem,
            fontWeight: ThemeConfig.kFontWeightListItem,
          ),
        ),
        const SizedBox(height: 8),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label(row),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: ThemeConfig.kFontSizeListSubItem,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      grandTotal > 0
                          ? "${ProxyConfUtils.convertTrafficToStringDouble(row.total)}"
                              "  ${(row.total * 100 / grandTotal).toStringAsFixed(1)}%"
                          : ProxyConfUtils.convertTrafficToStringDouble(
                              row.total,
                            ),
                      style: const TextStyle(
                        fontSize: ThemeConfig.kFontSizeListSubItem,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(height: 5, color: Colors.grey.withAlpha(60)),
                      FractionallySizedBox(
                        widthFactor: (row.total / max).clamp(0.0, 1.0),
                        child: Container(
                          height: 5,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
