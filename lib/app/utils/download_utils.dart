import 'dart:async';
import 'dart:io';

import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/file_utils.dart';
import 'package:karing/app/utils/http_utils.dart';
import 'package:karing/app/utils/log.dart';

abstract final class DownloadUtils {
  static Future<ReturnResult<HttpHeaders>> download(
    Uri uri,
    String downloadPath,
  ) async {
    List<int?> ports = await VPNService.getPortsByPrefer(true);
    late ReturnResult<HttpHeaders> result;
    var attempt = 0;
    for (var port in ports) {
      // From the second attempt on, keep the bytes already received and ask for
      // only the remainder. The content cannot have changed in the seconds
      // between two attempts, so this is safe — and re-fetching megabytes over a
      // slow link is the difference between finishing and never finishing.
      result = await downloadWithPort(
        uri,
        downloadPath,
        null,
        false,
        port,
        resume: attempt > 0,
      );
      attempt++;
      if (result.error == null) {
        return result;
      }
      if (result.error!.message.contains("404")) {
        break;
      }
    }
    // Nothing succeeded. Drop the partial rather than leave it behind: a later
    // run has no stored validator, so it must not resume against content that
    // may have changed in the meantime.
    await FileUtils.deletePath("$downloadPath.tmp");
    return result;
  }

  static Future<ReturnResult<HttpHeaders>> downloadWithPort(
    Uri uri,
    String downloadPath,
    String? useAgent,
    bool xhwid,
    int? port, {
    Duration? timeout,
    // Continue a partial download left by a previous attempt rather than
    // starting over. Only pass this when the remote content is known not to have
    // changed since those bytes were written.
    bool resume = false,
  }) async {
    String downloadPathTemp = "$downloadPath.tmp";
    int offset = 0;
    if (resume) {
      final partial = File(downloadPathTemp);
      if (await partial.exists()) {
        offset = await partial.length();
      }
    }
    if (offset == 0 && !await FileUtils.deletePath(downloadPathTemp)) {
      return ReturnResult(
        error: ReturnResultError("delete $downloadPathTemp failed"),
      );
    }

    ReturnResult<HttpHeaders> result = await HttpUtils.httpDownload(
      uri,
      downloadPathTemp,
      port,
      useAgent,
      xhwid,
      timeout,
      offset: offset,
    );

    if (result.error != null) {
      // Keep the partial when the caller may resume from it; otherwise clear it.
      if (!resume) {
        await FileUtils.deletePath(downloadPathTemp);
      }
      return ReturnResult(error: ReturnResultError(result.error!.message));
    }
    try {
      var file = File(downloadPathTemp);
      if (await file.exists()) {
        await FileUtils.deletePath(downloadPath);
        await file.rename(downloadPath);
      }
    } catch (err) {
      Log.w(
        "DownloadUtils.download exception ${uri.toString()} ${err.toString()} ",
      );
      return ReturnResult(error: ReturnResultError(err.toString()));
    }
    return result;
  }
}
