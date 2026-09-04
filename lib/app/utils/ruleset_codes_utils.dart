import 'dart:io';

import 'package:karing/app/utils/path_utils.dart';
import 'package:karing/i18n/strings.g.dart';

/// Loads rule set codes (geosite/geoip/acl) from bundled asset lists.
/// These codes populate the diversion rule editor pickers.
class RulesetCodesUtils {
  static List<String>? _siteCodes;
  static List<String>? _ipCodes;
  static List<String>? _aclCodes;
  static Map<String, List<String>>? _aclSubCodes;

  static List<String> _listCodes(String dir) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) {
        return [];
      }
      final codes = <String>[];
      for (final f in d.listSync()) {
        if (f is File && f.path.toLowerCase().endsWith('.srs')) {
          codes.add(f.uri.pathSegments.last.replaceAll('.srs', ''));
        }
      }
      codes.sort();
      return codes;
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> siteCodes() async {
    if (_siteCodes != null) return _siteCodes!;
    _siteCodes = _listCodes(await PathUtils.geositeDir());
    return _siteCodes!;
  }

  static Future<List<String>> ipCodes() async {
    if (_ipCodes != null) return _ipCodes!;
    _ipCodes = _listCodes(await PathUtils.geoipDir());
    return _ipCodes!;
  }

  static Future<List<String>> aclCodes() async {
    if (_aclCodes != null) return _aclCodes!;
    _aclCodes = _listCodes(await PathUtils.aclDir());
    return _aclCodes!;
  }

  static Future<Map<String, List<String>>> aclSubCodes() async {
    if (_aclSubCodes != null) return _aclSubCodes!;
    final codes = await aclCodes();
    final map = <String, List<String>>{};
    for (final c in codes) {
      final at = c.indexOf('@');
      if (at > 0) {
        final base = c.substring(0, at);
        map.putIfAbsent(base, () => []).add(c);
      }
    }
    _aclSubCodes = map;
    return _aclSubCodes!;
  }

  static Future<List<int>> siteCodesHashCode() async =>
      (await siteCodes()).map((e) => e.hashCode).toList();

  static Future<List<int>> ipCodesHashCode() async =>
      (await ipCodes()).map((e) => e.hashCode).toList();

  static Future<List<int>> aclCodesHashCode() async =>
      (await aclCodes()).map((e) => e.hashCode).toList();
}
