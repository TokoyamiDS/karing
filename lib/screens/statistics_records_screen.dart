import 'package:flutter/material.dart';

import 'package:karing/screens/group_screen.dart';

/// Shows per-day traffic statistics from the statistics sqlite db.
class StatisticsRecordsScreen extends StatefulWidget {
  final String dbPath;
  final bool currentDB;
  const StatisticsRecordsScreen(
      {super.key, required this.dbPath, required this.currentDB});

  static RouteSettings routSettings() {
    return const RouteSettings(name: "/statistics_records");
  }

  @override
  State<StatisticsRecordsScreen> createState() =>
      _StatisticsRecordsScreenState();
}

class _StatisticsRecordsScreenState extends State<StatisticsRecordsScreen> {
  List<String> _tables = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.currentDB ? "Statistics" : widget.dbPath),
      ),
      body: const Center(
        child: Text("No statistics available"),
      ),
    );
  }
}
