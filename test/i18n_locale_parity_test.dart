import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every locale file must carry the same key set as English.
///
/// This is the guard for a failure mode that is otherwise invisible until a
/// user switches language: `sync_locale_keys.py` fills missing keys with the
/// English text, but nothing stops a key from being added to `en` and used in
/// code while some locale is left behind — or a locale being hand-edited into
/// a shape the others do not share. A half-finished localization pass also
/// breaks the build rather than degrading gracefully, because the key and its
/// usage live in different files.
void main() {
  final dir = Directory('lib/i18n');

  Set<String> leavesOf(Map<String, dynamic> node, [String prefix = '']) {
    final out = <String>{};
    node.forEach((key, value) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        out.addAll(leavesOf(value, path));
      } else {
        out.add(path);
      }
    });
    return out;
  }

  Map<String, dynamic> readLocale(File f) =>
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

  test('the i18n directory is where we think it is', () {
    expect(dir.existsSync(), isTrue, reason: 'lib/i18n not found');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.i18n.json'))
        .toList();
    expect(files, isNotEmpty, reason: 'no *.i18n.json found');
  });

  test('every locale has exactly the same keys as English', () {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.i18n.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final en = files.firstWhere((f) => f.path.endsWith('en.i18n.json'));
    final base = leavesOf(readLocale(en));

    final problems = <String>[];
    for (final f in files) {
      if (f.path == en.path) {
        continue;
      }
      final keys = leavesOf(readLocale(f));
      final missing = base.difference(keys);
      final extra = keys.difference(base);
      if (missing.isNotEmpty || extra.isNotEmpty) {
        problems.add(
          '${f.path.split(RegExp(r"[\\/]")).last}: '
          'missing ${missing.length} (${missing.take(3).join(", ")}), '
          'extra ${extra.length} (${extra.take(3).join(", ")})',
        );
      }
    }

    expect(
      problems,
      isEmpty,
      reason:
          'locales diverge from en.i18n.json — run '
          '.workbuddy-ai/sync_locale_keys.py then `dart run slang`:\n'
          '${problems.join("\n")}',
    );
  });
}
