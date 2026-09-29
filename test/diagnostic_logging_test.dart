import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/file_utils.dart';
import 'package:karing/app/utils/log.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';
import 'package:path/path.dart' as path;

/// A diagnostic build has to answer "what did the app actually do?" from a log
/// the user can find and hand over. Two things make that work, and both are
/// pinned here: the core's captured output must survive its very first write,
/// and every log must land in one predictable directory.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('karing_log_test');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('FileUtils.append', () {
    test('creates the file when it does not exist yet', () async {
      final target = path.join(tmp.path, 'core.log');

      final ok = await FileUtils.append(target, 'first line\n');

      expect(ok, isTrue);
      expect(
        await File(target).exists(),
        isTrue,
        reason: 'the core log files are deleted immediately before the core is '
            'spawned, so the first append has to create them — otherwise the '
            "core's entire output is discarded",
      );
      expect(await File(target).readAsString(), 'first line\n');
    });

    test('appends instead of truncating', () async {
      final target = path.join(tmp.path, 'core.log');

      await FileUtils.append(target, 'one\n');
      await FileUtils.append(target, 'two\n');

      expect(await File(target).readAsString(), 'one\ntwo\n');
    });

    test('reports failure for an empty path rather than throwing', () async {
      expect(await FileUtils.append('', 'x'), isFalse);
    });
  });

  group('log location', () {
    test('app, core and core-error logs share one directory', () async {
      final app = await PathUtils.logFilePath();
      final core = await PathUtils.serviceLogFilePath();
      final coreErr = await PathUtils.serviceStdErrorFilePath();

      expect(app, isNotEmpty);
      expect(path.dirname(core), path.dirname(app));
      expect(path.dirname(coreErr), path.dirname(app));
    });

    test('the directory resolves to somewhere writable', () async {
      final dir = await PathUtils.logDir();
      final probe = File(path.join(dir, '.log_write_probe_test'));
      await probe.writeAsString('x', flush: true);
      expect(await probe.exists(), isTrue);
      await probe.delete();
    });
  });

  group('core log level', () {
    test('a diagnostic build asks the core for debug output', () {
      final log = SingboxConfigBuilder.log(SingboxExportType.karing) as Map;

      expect(log['level'], kDiagnosticLogging ? 'debug' : 'warn');
      expect(log['timestamp'], isTrue);
    });
  });
}
