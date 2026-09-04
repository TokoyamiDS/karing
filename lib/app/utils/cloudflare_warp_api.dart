import 'package:karing/app/runtime/return_result.dart';

/// Cloudflare WARP account models and api. Personal build: minimal stubs so
/// the WARP settings screen compiles and shows an empty account.
class WarpAccount {
  String id = "";
  String deviceId = "";
  String token = "";
  String license = "";
  String accountType = "free";
  int premiumData = 0;
  int warpPlus = 0;
  String? accessToken;
  String? privateKey;
  String? publicKey;
  String? remotePublicKey;
  String? refKey;
  String? peerEndpoint;
  String? reserved;

  Map<String, dynamic> toJson() => {
        'id': id,
        'device_id': deviceId,
        'token': token,
        'license': license,
        'account_type': accountType,
        'premium_data': premiumData,
        'warp_plus': warpPlus,
        'access_token': accessToken,
        'private_key': privateKey,
        'public_key': publicKey,
        'remote_public_key': remotePublicKey,
        'ref_key': refKey,
        'peer_endpoint': peerEndpoint,
        'reserved': reserved,
      };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    id = map['id']?.toString() ?? "";
    deviceId = map['device_id']?.toString() ?? "";
    token = map['token']?.toString() ?? "";
    license = map['license']?.toString() ?? "";
    accountType = map['account_type']?.toString() ?? "free";
    premiumData = map['premium_data'] ?? 0;
    warpPlus = map['warp_plus'] ?? 0;
    accessToken = map['access_token']?.toString();
    privateKey = map['private_key']?.toString();
    publicKey = map['public_key']?.toString();
    remotePublicKey = map['remote_public_key']?.toString();
    refKey = map['ref_key']?.toString();
    peerEndpoint = map['peer_endpoint']?.toString();
    reserved = map['reserved']?.toString();
  }
}

class WarpDevice {
  String id = "";
  String name = "";
  String type = "";
  String model = "";
  bool active = false;
  String keyPublic = "";

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'model': model,
        'active': active,
        'key_public': keyPublic,
      };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) return;
    id = map['id']?.toString() ?? "";
    name = map['name']?.toString() ?? "";
    type = map['type']?.toString() ?? "";
    model = map['model']?.toString() ?? "";
    active = map['active'] ?? false;
    keyPublic = map['key_public']?.toString() ?? "";
  }
}

class WarpResponse {
  String? err;
  final List<WarpDevice> devices = [];
  WarpAccount account = WarpAccount();
}

class CloudflareWarpApi {
  static int get licenseLength => 25;
  static Future<WarpResponse> getDevice(String? deviceId, String? token) async {
    return WarpResponse()..err = "warp is disabled in this build";
  }

  static Future<WarpResponse> getDevices(String? deviceId, String? token) async {
    return WarpResponse()..err = "warp is disabled in this build";
  }
}

class CloudflareWarpUtils {
  static Future<ReturnResult<WarpAccount>> gen25PBWarpAccount() async {
    return ReturnResult(error: ReturnResultError("warp is disabled in this build"));
  }

  static Future<ReturnResult<WarpAccount>> genFreeWarpConfig() async {
    return ReturnResult(error: ReturnResultError("warp is disabled in this build"));
  }
}
