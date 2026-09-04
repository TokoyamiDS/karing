/// iCloud helpers. Only usable on iOS/macOS; functional stub elsewhere.
import 'package:karing/app/runtime/return_result.dart';

class ICloudUtils {
  static Future<bool> available() async {
    return false;
  }

  static Future<ReturnResult<List<String>>> list() async {
    return ReturnResult(error: ReturnResultError("icloud is disabled in this build"));
  }

  static Future<ReturnResultError?> upload(
      {required String relativePath, required String localPath}) async {
    return ReturnResultError("icloud is disabled in this build");
  }

  static Future<ReturnResultError?> download(
      {required String relativePath, required String localPath}) async {
    return ReturnResultError("icloud is disabled in this build");
  }

  static Future<ReturnResultError?> delete(String relativePath) async {
    return ReturnResultError("icloud is disabled in this build");
  }
}
