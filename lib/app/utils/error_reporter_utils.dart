import 'dart:io';

import 'package:karing/app/utils/log.dart';

class ErrorReporterUtils {
  static void Function()? _onNoSpace;
  static bool _reporting = false;

  static void register(void Function()? onNoSpace) {
    _onNoSpace = onNoSpace;
  }

  static bool tryReportNoSpace(String err) {
    bool noSpace = false;
    if (Platform.isWindows) {
      if (err.contains("errno = 112")) {
        noSpace = true;
      }
    } else {
      if (err.contains("No space left on device")) {
        noSpace = true;
      }
    }
    if (!noSpace) {
      return false;
    }
    if (_reporting) {
      return noSpace;
    }
    _reporting = true;
    _onNoSpace?.call();
    _reporting = false;
    return noSpace;
  }

  static void report(String err) {
    Log.w(err);
  }

  static void reportException(dynamic err, [dynamic stacktrace]) {
    Log.w("exception: $err");
  }
}
