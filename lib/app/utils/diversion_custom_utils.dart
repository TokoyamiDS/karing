import 'dart:convert';
import 'dart:io';

import 'package:karing/app/modules/server_manager.dart' show ServerManager;
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';

/// A diversion rules collection for import/export and presets.
class DiversionCustomRules {
  List<DiversionRulesGroup> rules = [];

  static const String kDirect = "direct";
  static const String kBlock = "block";
  static const String kCurrentSelected = "currentSelected";
  static const String kUrltest = "urltest";
  static const String kNone = "";

  Map<String, dynamic> toJson() => {'rules': rules};

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    final r = map['rules'] ?? [];
    rules = [];
    for (final item in r) {
      final g = DiversionRulesGroup();
      g.fromJson(item);
      rules.add(g);
    }
  }

  DiversionCustomRules clone() {
    final c = DiversionCustomRules();
    c.fromJson(toJson());
    return c;
  }

  static DiversionCustomRules exportRules() {
    final rules = DiversionCustomRules();
    final custom = ServerManager.getDiversionCustomGroup();
    rules.rules.addAll(custom.groups);
    return rules;
  }

  static Future<ReturnResult<DiversionCustomRules>> getFromFile(
      String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      final rules = DiversionCustomRules();
      rules.fromJson(jsonDecode(content));
      return ReturnResult(data: rules);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  Future<ReturnResultError?> importRules(
      DiversionCustomRules imported, bool replace) async {
    if (replace) {
      rules = imported.rules;
      return null;
    }
    for (final group in imported.rules) {
      final exists = rules.any((r) => r.name == group.name);
      if (!exists) {
        rules.add(group);
      }
    }
    return null;
  }
}

/// Region presets for diversion rules.
class DiversionCustomRulesPreset {
  static Future<DiversionCustomRules?> getPreset(String regionCode) async {
    try {
      final code = regionCode.toLowerCase();
      final rules = DiversionCustomRules();
      if (code == 'ir') {
        final block = DiversionRulesGroup();
        block.name = "Adblock IR";
        block.outbound = DiversionCustomRules.kBlock;
        block.switch_ = true;
        block.ruleSetBuildIn = ['geosite:category-ads-ir'];
        final direct = DiversionRulesGroup();
        direct.name = "Iran Direct";
        direct.outbound = DiversionCustomRules.kDirect;
        direct.switch_ = true;
        direct.ruleSetBuildIn = ['geosite:ir', 'geoip:ir'];
        rules.rules.addAll([block, direct]);
        return rules;
      }
      return rules;
    } catch (_) {
      return null;
    }
  }
}


class DiversionCustomRulesHelper {
  static Future<ReturnResultError?> importRulesStatic(
      DiversionCustomRules imported) async {
    final custom = ServerManager.getDiversionCustomGroup();
    for (final group in imported.rules) {
      final exists = custom.groups.any((r) => r.name == group.name);
      if (!exists) {
        custom.groups.add(group);
      }
    }
    await ServerManager.saveDiversionGroupConfig();
    ServerManager.setDirty(true);
    return null;
  }
}