import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:karing/app/runtime/return_result.dart';

/// Zip helpers built on package:archive.
class ZipUtils {
  static Future<ReturnResult<List<String>>> list2(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final out = <String>[];
      for (final f in archive) {
        out.add(f.name);
      }
      return ReturnResult(data: out);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<List<String>> list(String path) async {
    final out = <String>[];
    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        out.add(f.name);
      }
    } catch (_) {}
    return out;
  }

  static Future<ReturnResultError?> unzip2(
    String path,
    String destDir, {
    Set<String> whiteList = const {},
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final dest = Directory(destDir);
      if (!dest.existsSync()) {
        dest.createSync(recursive: true);
      }
      for (final f in archive) {
        final name = f.name;
        if (name.contains('..') || name.startsWith('/')) {
          continue;
        }
        if (whiteList.isNotEmpty && !whiteList.contains(name)) {
          continue;
        }
        final outPath = '$destDir/$name';
        if (f.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(f.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      return null;
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }

  static Future<bool> unzip(String path, String destDir) async {
    final err = await unzip2(path, destDir);
    return err == null;
  }

  static Future<ReturnResultError?> zip2(
      List<String> files, String destPath) async {
    try {
      final encoder = ZipEncoder();
      final archive = Archive();
      for (final filePath in files) {
        final f = File(filePath);
        if (!f.existsSync()) continue;
        final bytes = await f.readAsBytes();
        final rel = f.uri.pathSegments.last;
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
      final out = File(destPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(encoder.encode(archive) ?? []);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }

  static Future<bool> zip(String srcDir, String destPath) async {
    try {
      final dir = Directory(srcDir);
      if (!dir.existsSync()) {
        return false;
      }
      final encoder = ZipEncoder();
      final archive = Archive();
      final baseLen = srcDir.endsWith('\\') || srcDir.endsWith('/')
          ? srcDir.length
          : srcDir.length + 1;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final rel = entity.path.substring(baseLen).replaceAll('\\', '/');
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
      final out = File(destPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(encoder.encode(archive) ?? []);
      return true;
    } catch (_) {
      return false;
    }
  }
}
