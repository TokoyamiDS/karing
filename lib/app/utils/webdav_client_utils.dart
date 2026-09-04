import 'dart:convert';
import 'dart:io';

import 'package:webdav_client_plus/webdav_client_plus.dart' as wd;

import 'package:karing/app/runtime/return_result.dart';

export 'package:webdav_client_plus/webdav_client_plus.dart' show WebdavClient;

/// WebDAV helpers built on package:webdav_client_plus.
class WebdavClientUtils {
  static Future<ReturnResult<wd.WebdavClient>> connect(
      String? proxyPort, String url, String user, String password) async {
    try {
      final client = wd.WebdavClient.basicAuth(url: url, user: user, pwd: password);
      await client.ping();
      return ReturnResult(data: client);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<ReturnResult<List<String>>> list(wd.WebdavClient client) async {
    try {
      final list = await client.readDir('/');
      final names = <String>[];
      for (final e in list) {
        final p = e.path ?? "";
        if (p.isNotEmpty) {
          var n = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
          n = n.split('/').last;
          if (n.isNotEmpty) {
            names.add(n);
          }
        }
      }
      return ReturnResult(data: names);
    } catch (err) {
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
  }

  static Future<ReturnResultError?> upload(wd.WebdavClient client,
      {required String relativePath, required String localPath}) async {
    try {
      final bytes = await File(localPath).readAsBytes();
      await client.write(relativePath, bytes);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }

  static Future<ReturnResultError?> download(wd.WebdavClient client,
      {required String relativePath, required String localPath}) async {
    try {
      final data = await client.read(relativePath);
      final file = File(localPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }

  static Future<ReturnResultError?> delete(
      wd.WebdavClient client, String relativePath) async {
    try {
      await client.remove(relativePath);
      return null;
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }

  static bool isInnerError(String err) {
    return false;
  }
}
