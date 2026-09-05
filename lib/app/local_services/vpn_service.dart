// ignore_for_file: unused_catch_stack, empty_catches

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:tuple/tuple.dart';
import 'package:vpn_service/proxy_manager.dart' hide NetInterfacesInfo;
import 'package:vpn_service/state.dart';
import 'package:vpn_service/vpn_service.dart';

import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/clash_api.dart';
import 'package:karing/app/utils/app_args.dart';
import 'package:karing/app/utils/app_utils.dart';
import 'package:karing/app/utils/did.dart';
import 'package:karing/app/utils/error_reporter_utils.dart';
import 'package:karing/app/utils/file_utils.dart';
import 'package:karing/app/utils/install_referrer_utils.dart';
import 'package:karing/app/utils/log.dart';
import 'package:karing/app/utils/network_utils.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:karing/app/utils/platform_utils.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

class VPNServiceSetServerOptions {
  String disabledServerError = "";
  String invalidServerError = "";
  String expiredServerError = "";
  Set<String> allOutboundsTags = {};
}

Future<void> _extractRuleSets() async {
  final baseDir = await PathUtils.profileDir();
  final rulesetDir = path.join(baseDir, "ruleset");
  SingboxConfigBuilder.ruleSetBaseDir = rulesetDir;
  const entries = [
    "geosite/ir",
    "geoip/ir",
    "geosite/category-ads-ir",
    "geosite/category-ads-all",
  ];
  for (final entry in entries) {
    final target = File(path.join(rulesetDir, "$entry.srs"));
    if (await target.exists()) {
      continue;
    }
    try {
      final data = await rootBundle.load("assets/datas/$entry.srs");
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } catch (_) {}
  }
}

class VPNService {
  static const localhost = "127.0.0.1";
  static bool _runAsAdmin = false;
  static final bool _systemExtension = true;
  static List<String> _abis = [];
  static ProxyConfig? _currentServer;
  static Process? _windowsProcess;
  static StreamSubscription? _windowsProcessExitSub;
  static bool _windowsStopping = false;

  static final List<
    void Function(FlutterVpnServiceState state, Map<String, String> params)
  >
  onEventStateChanged = [];

  static Future<void> initABI() async {
    if (Platform.isAndroid) {
      String abisAll = await FlutterVpnService.getABIs();
      _abis = abisAll.replaceAll("[", "").replaceAll("]", "").split(",");
    }
  }

  static Future<void> init() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (Platform.isWindows) {
      _runAsAdmin = await FlutterVpnService.isRunAsAdmin();
      FlutterVpnService.firewallAddApp(
        Platform.resolvedExecutable,
        PathUtils.getExeName(),
      );
      FlutterVpnService.firewallAddApp(
        PathUtils.serviceExePath(),
        PathUtils.serviceExeName(),
      );
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
        args: [AppArgs.launchStartup],
      );
    }

    FlutterVpnService.onStateChanged((
      FlutterVpnServiceState state,
      Map<String, String> params,
    ) async {
      if (getSupportSystemProxy()) {
        if (state == FlutterVpnServiceState.disconnected) {
          bool enable = await getSystemProxyEnable();
          if (enable) {
            await FlutterVpnService.cleanSystemProxy();
          }
        }
      }

      for (var callback in onEventStateChanged) {
        callback(state, params);
      }
    });

    if (Platform.isWindows) {
      await stop();
    }
  }

  static Future<void> uninit() async {
    if (PlatformUtils.isPC()) {
      if (SettingManager.getConfig().proxy.disconnectWhenQuit) {
        await stop();
      }
    }
  }

  static List<String> getABIs() {
    return _abis;
  }

  static ReturnResultError? convertErr(VpnServiceResultError? err) {
    if (err == null) {
      return null;
    }
    return ReturnResultError(err.message);
  }

  static ProxyConfig getCurrent() {
    return _currentServer ?? ProxyConfig();
  }

  static void setCurrent(ProxyConfig server) {
    _currentServer = server;
  }

  static Future<bool> getTunMode() async {
    final setting = SettingManager.getConfig();
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return setting.tun.enable;
    }
    return setting.tun.enable;
  }

  static String durationToString(Duration? duration) {
    if (duration == null) {
      return "";
    }
    var microseconds = duration.inMicroseconds;
    var sign = "";
    var negative = microseconds < 0;
    var hours = microseconds ~/ Duration.microsecondsPerHour;
    microseconds = microseconds.remainder(Duration.microsecondsPerHour);
    if (negative) {
      hours = 0 - hours;
      microseconds = 0 - microseconds;
      sign = "-";
    }
    var minutes = microseconds ~/ Duration.microsecondsPerMinute;
    microseconds = microseconds.remainder(Duration.microsecondsPerMinute);
    var minutesPadding = minutes < 10 ? "0" : "";
    var seconds = microseconds ~/ Duration.microsecondsPerSecond;
    microseconds = microseconds.remainder(Duration.microsecondsPerSecond);
    var secondsPadding = seconds < 10 ? "0" : "";
    return "$sign$hours:$minutesPadding$minutes:$secondsPadding$seconds";
  }

  /// Writes the sing-box core config for [current] to [savePath] and prepares
  /// the service config (VpnServiceConfig fields ported from clashmi).
  /// Returns null on success.
  static Future<ReturnResultError?> setServer(
    ProxyConfig current,
    VPNServiceSetServerOptions options,
    SingboxExportType exportType,
    String? host,
    String? secret,
    String savePath,
  ) async {
    if (current.type == kOutboundTypeSpecial && current.raw.isEmpty) {
      return ReturnResultError(options.disabledServerError);
    }
    if (current.groupid.isEmpty) {
      return ReturnResultError(options.invalidServerError);
    }
    await _extractRuleSets();
    final tunMode = await getTunMode();
    final setting = SettingManager.getConfig();
    Log.w(
      "setServer: type=${current.type} tag=${current.tag} groupid=${current.groupid} "
      "rawEmpty=${current.raw.isEmpty} groups=${ServerManager.getConfig().items.length}",
    );

    final config = SingboxConfig();
    final selectOutbound = SingboxConfigBuilder.buildOutbound(current);
    if (selectOutbound == null) {
      return ReturnResultError(options.invalidServerError);
    }

    config.log = SingboxConfigBuilder.log(exportType);
    config.ntp = SingboxConfigBuilder.ntp();
    config.experimental = SingboxConfigBuilder.experimental();

    final dns = SingboxConfigBuilder.dns(tunMode, exportType, null);
    if (dns.error != null) {
      return dns.error;
    }
    config.dns = dns.data;

    config.inbounds = SingboxConfigBuilder.inbounds(tunMode, exportType);

    final allOutBounds = <dynamic>[];
    if (selectOutbound != null) {
      allOutBounds.add(selectOutbound);
    }
    for (final ob in allOutBounds) {
      final tag = (ob is Map ? ob['tag'] : null)?.toString() ?? "";
      if (tag.isNotEmpty) {
        options.allOutboundsTags.add(tag);
      }
    }
    // official behavior: every enabled group's nodes live in the config so
    // the selector covers all subscriptions and per-node pings resolve
    final tuple = Tuple2<List<ProxyConfig>, List<dynamic>>([], []);
    final aggregatedTags = <String>{};
    getOutboundsWithoutUrltest(aggregatedTags, tuple, null);
    for (final tag in aggregatedTags) {
      if (!options.allOutboundsTags.contains(tag)) {
        options.allOutboundsTags.add(tag);
      }
    }
    final existingOutboundTags = allOutBounds
        .map((ob) => (ob is Map ? ob['tag'] : null)?.toString() ?? "")
        .toSet();
    for (final ob in tuple.item2) {
      final tag = (ob is Map ? ob['tag'] : null)?.toString() ?? "";
      if (tag.isNotEmpty && !existingOutboundTags.contains(tag)) {
        allOutBounds.add(ob);
      }
    }
    if (selectOutbound is Map &&
        (current.type == kOutboundTypeUrltest ||
            current.type == kOutboundTypeSelector)) {
      // selector/urltest groups reference member tags; rebuild them over the
      // full aggregated set, excluding structural group tags so the config
      // cannot become circular (e.g. urltest -> urltest).
      final memberTags = options.allOutboundsTags
          .where((t) => !SingboxConfigBuilder.kGroupTags.contains(t))
          .toList();
      selectOutbound['outbounds'] = memberTags;
    }
    if (options.allOutboundsTags.isEmpty) {
      options.allOutboundsTags.add(kOutboundTagDirect);
      allOutBounds.add({'type': 'direct', 'tag': kOutboundTagDirect});
    }

    config.outbounds = SingboxConfigBuilder.outbounds(
      "",
      options.allOutboundsTags,
      {},
      selectOutbound,
      allOutBounds,
      null,
      {},
      exportType,
    );

    config.route = SingboxConfigBuilder.route(
      setting.regionCode,
      "",
      "",
      "",
      [],
      [],
      [],
      tunMode,
      allOutBounds,
      {},
      null,
      [],
      config.inbounds,
      config.dns,
      null,
      setting.chainProxy,
      current.groupid,
      exportType,
    );

    final encoder = const JsonEncoder.withIndent('  ');
    String content = encoder.convert(config.toJson());
    try {
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
    } catch (err) {
      ErrorReporterUtils.tryReportNoSpace(err.toString());
      return ReturnResultError(err.toString());
    }

    final serviceConfig = VpnServiceConfig();
    serviceConfig.control_port = setting.proxy.controlPort;
    serviceConfig.base_dir = await PathUtils.profileDir();
    serviceConfig.work_dir = PathUtils.appAssetsDir();
    serviceConfig.cache_dir = await PathUtils.cacheDir();
    serviceConfig.core_path = savePath;
    serviceConfig.log_path = await PathUtils.serviceLogFilePath();
    serviceConfig.err_path = await PathUtils.serviceStdErrorFilePath();
    serviceConfig.id = await Did.getDid();
    serviceConfig.version = AppUtils.getBuildinVersion();
    serviceConfig.name = AppUtils.getName();
    serviceConfig.secret = setting.proxy.socksLocalPassword;
    serviceConfig.install_refer = await InstallReferrerUtils.getString();
    serviceConfig.prepare = tunMode;
    serviceConfig.wake_lock = setting.ui.wakeLock;
    serviceConfig.auto_connect_at_boot = setting.autoConnectAtBoot;
    serviceConfig.include_all_networks = setting.tun.includeAllNetworks;
    serviceConfig.exclude_local_networks = setting.tun.excludeLocalNetworks;
    serviceConfig.exclude_cellular_services =
        setting.tun.excludeCellularServices;
    serviceConfig.exclude_apns = setting.tun.excludeApns;
    serviceConfig.exclude_device_communication =
        setting.tun.excludeDeviceCommunication;
    serviceConfig.enforce_routes = setting.tun.enforceRoutes;
    serviceConfig.auto_route_use_sub_ranges_by_default =
        setting.tun.autoRouteUseSubRangesByDefault;

    var bundleIdentifier = AppUtils.getBundleId(_systemExtension);
    var uiServerAddress = AppUtils.getName();
    var uiLocalizedDescription = AppUtils.getName();
    if (Platform.isMacOS) {
      if (_systemExtension) {
        uiServerAddress = "$uiServerAddress (system)";
        uiLocalizedDescription = "$uiLocalizedDescription (system)";
      }
    }

    String configFilePath = await PathUtils.serviceConfigFilePath();
    final err = await FlutterVpnService.prepareConfig(
      config: serviceConfig,
      tunnelServicePath: PathUtils.serviceExePath(),
      configFilePath: configFilePath,
      systemExtension: _systemExtension,
      bundleIdentifier: bundleIdentifier,
      controlKind: AppUtils.getControlKind(),
      uiServerAddress: uiServerAddress,
      uiLocalizedDescription: uiLocalizedDescription,
      excludePorts: [setting.proxy.controlPort, setting.proxy.mixedRulePort],
    );
    if (err != null) {
      return convertErr(err);
    }

    File confFile = File(configFilePath);
    bool reinstall = false;
    if (Platform.isIOS || Platform.isMacOS) {
      bool exists = await confFile.exists();
      if (exists) {
        try {
          String oldContent = await confFile.readAsString();
          if (oldContent.isNotEmpty) {
            var configJson = jsonDecode(oldContent);
            VpnServiceConfig configOld = VpnServiceConfig();
            configOld.fromJson(configJson);
            if (serviceConfig.install_refer != configOld.install_refer) {
              reinstall = true;
            }
          }
        } catch (err) {
          Log.w("VPNService.setServer exception ${err.toString()}");
        }
      }
    }

    try {
      await confFile.writeAsString(
        encoder.convert(serviceConfig.toJson()),
        flush: true,
      );
    } catch (err) {
      ErrorReporterUtils.tryReportNoSpace(err.toString());
    }

    if (Platform.isMacOS) {
      ProxyManager().setExcludeDevices({AppUtils.getName()});
    }

    if (reinstall) {
      await uninstall();
    }

    return null;
  }

  static Future<void> prepareFiles() async {}

  static Future<ReturnResultError?> install() async {
    VpnServiceResultError? err = await FlutterVpnService.installService();
    if (err != null) {
      Log.w("VPNService.install err ${err.message.toString()}");
    }
    return convertErr(err);
  }

  static Future<ReturnResultError?> uninstall() async {
    VpnServiceResultError? err = await FlutterVpnService.uninstallService();
    if (err != null) {
      Log.w("VPNService.uninstall err ${err.message.toString()}");
    }
    return convertErr(err);
  }

  static Duration getTimeoutByOutboundCount(int count, bool tunMode) {
    int timeout = 5;
    if (count > 2000) {
      timeout = 15;
    } else if (count > 1000) {
      timeout = 10;
    }
    return Duration(seconds: timeout);
  }

  static String _windowsCoreExePath() {
    return path.join(PathUtils.exeDir(), "sing-box.exe");
  }

  static Future<void> _windowsStopCore() async {
    final process = _windowsProcess;
    _windowsProcess = null;
    _windowsProcessExitSub?.cancel();
    _windowsProcessExitSub = null;
    ClashApi.connectionsStartTime = null;
    ClashApi.resetConnectionsStats();
    if (process != null) {
      _windowsStopping = true;
      try {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 5));
      } catch (err) {
        try {
          await Process.run(
            "taskkill",
            ["/PID", process.pid.toString(), "/T", "/F"],
          );
        } catch (_) {}
      }
      _windowsStopping = false;
    }
    // wait for the listening ports to be released before a respawn
    final setting = SettingManager.getConfig();
    final ports = [setting.proxy.mixedRulePort, setting.proxy.controlPort];
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    outer:
    while (DateTime.now().isBefore(deadline)) {
      for (final port in ports) {
        bool busy = false;
        try {
          final socket = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            port,
          );
          await socket.close();
        } catch (_) {
          busy = true;
        }
        if (busy) {
          await Future.delayed(const Duration(milliseconds: 150));
          continue outer;
        }
      }
      break;
    }
    FlutterVpnService.notifyState(FlutterVpnServiceState.disconnected);
  }

  /// Runs sing-box.exe as a subprocess. sing-box listens on the mixed port;
  /// readiness is detected by polling it.
  static Future<ReturnResultError?> _windowsStartCore(
    Duration timeout,
  ) async {
    await _windowsStopCore();
    final coreExe = _windowsCoreExePath();
    if (!await File(coreExe).exists()) {
      return ReturnResultError("core not found: $coreExe");
    }
    final configPath = await PathUtils.serviceCoreConfigFilePath();
    if (!await File(configPath).exists()) {
      return ReturnResultError("core config not found: $configPath");
    }
    Log.w("_windowsStartCore: exe=$coreExe config=$configPath");
    final logPath = await PathUtils.serviceLogFilePath();
    final errPath = await PathUtils.serviceStdErrorFilePath();
    try {
      final logFile = File(logPath);
      if (await logFile.exists()) {
        await logFile.delete();
      }
      final errFile = File(errPath);
      if (await errFile.exists()) {
        await errFile.delete();
      }
    } catch (_) {}

    final stderrBuffer = StringBuffer();
    Process? process;
    try {
      process = await Process.start(
        coreExe,
        ["run", "-c", configPath, "-D", await PathUtils.profileDir()],
        workingDirectory: await PathUtils.profileDir(),
      );
    } catch (err) {
      Log.w("_windowsStartCore: Process.start failed: $err");
      return ReturnResultError(err.toString());
    }
    Log.w("_windowsStartCore: spawned pid=${process.pid}");
    _windowsProcess = process;
    _windowsStopping = false;
    process.stdout.listen(
      (data) => FileUtils.append(
        logPath,
        utf8.decode(data, allowMalformed: true),
      ),
      onError: (err) {},
    );
    process.stderr.listen(
      (data) {
        try {
          stderrBuffer.write(utf8.decode(data, allowMalformed: true));
          FileUtils.append(errPath, utf8.decode(data, allowMalformed: true));
        } catch (_) {}
      },
      onError: (err) {},
    );
    final spawnedPid = process.pid;
    _windowsProcessExitSub = process.exitCode.asStream().listen((code) async {
      Log.w("_windowsStartCore: process $spawnedPid exited code=$code");
      if (!_windowsStopping) {
        _windowsProcess = null;
        String detail = stderrBuffer.toString().trim();
        if (detail.length > 1024) {
          detail = detail.substring(0, 1024);
        }
        FlutterVpnService.notifyState(
          FlutterVpnServiceState.disconnected,
          detail.isEmpty
              ? {"message": "core exited code=$code"}
              : {"message": detail},
        );
      }
    });

    final deadline = DateTime.now().add(timeout);
    final mixedPort = SettingManager.getConfig().proxy.mixedRulePort;
    while (DateTime.now().isBefore(deadline)) {
      if (_windowsProcess != process) {
        String detail = stderrBuffer.toString().trim();
        if (detail.length > 1024) {
          detail = detail.substring(0, 1024);
        }
        Log.w("_windowsStartCore: poll abort, core gone, detail=$detail");
        return ReturnResultError(
          detail.isEmpty ? "core exited" : detail,
        );
      }
      try {
        final socket = await Socket.connect(
          localhost,
          mixedPort,
          timeout: const Duration(milliseconds: 300),
        );
        socket.destroy();
        Log.w("_windowsStartCore: ready on $mixedPort");
        ClashApi.connectionsStartTime = DateTime.now();
        FlutterVpnService.notifyState(FlutterVpnServiceState.connected);
        return null;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    await _windowsStopCore();
    String detail = stderrBuffer.toString().trim();
    if (detail.length > 2048) {
      detail = detail.substring(0, 2048);
    }
    Log.w("_windowsStartCore: timeout, detail=$detail");
    return ReturnResultError(
      detail.isEmpty ? "service start timeout" : detail,
    );
  }

  /// clashmi: make sure the core listening ports are not blocked by the
  /// windows firewall.
  static Future<void> _firewallAddCorePorts() async {
    if (!Platform.isWindows) {
      return;
    }
    final setting = SettingManager.getConfig();
    await FlutterVpnService.firewallAddPorts(
      [setting.proxy.controlPort, setting.proxy.mixedRulePort],
      path.basename(_windowsCoreExePath()),
    );
  }

  static Future<ReturnResultError?> restart(Duration timeout) async {
    var started = await getStarted();
    if (!started) {
      return null;
    }
    if (Platform.isWindows) {
      await _firewallAddCorePorts();
      final enable = await getSystemProxyEnable();
      ReturnResultError? err = await _windowsStartCore(timeout);
      if (err != null) {
        await stop();
        return err;
      }
      if (enable) {
        await setSystemProxy(true);
      }
      return null;
    }
    final setting = SettingManager.getConfig();
    if (Platform.isIOS || Platform.isMacOS) {
      await FlutterVpnService.setAlwaysOn(false);
    }
    final enable = await getSystemProxyEnable();
    VpnServiceWaitResult result = await FlutterVpnService.restart(timeout);
    if (result.type == VpnServiceWaitType.timeout) {
      await stop();
      return ReturnResultError("service restart timeout");
    }
    if (result.type != VpnServiceWaitType.done) {
      Log.w(
        "VPNService.restart err ${result.type}:${result.err?.message.toString()}",
      );
      await stop();
      return convertErr(result.err);
    }
    String errorPath = await PathUtils.serviceStdErrorFilePath();
    String? content = await FileUtils.readAndDelete(errorPath);
    if (content != null && content.isNotEmpty) {
      await stop();
      return ReturnResultError(content);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      if (setting.alwayOn) {
        await FlutterVpnService.setAlwaysOn(setting.alwayOn);
      }
    }
    if (enable) {
      await setSystemProxy(true);
    }
    return null;
  }

  static Future<ReturnResultError?> start(Duration timeout) async {
    if (Platform.isWindows) {
      await _firewallAddCorePorts();
      ReturnResultError? err = await _windowsStartCore(timeout);
      if (err != null) {
        await stop();
        return err;
      }
      if (SettingManager.getConfig().proxy.autoSetSystemProxy) {
        await setSystemProxy(true);
      }
      return null;
    }
    final setting = SettingManager.getConfig();
    VpnServiceWaitResult result = await FlutterVpnService.start(timeout);
    if (result.type == VpnServiceWaitType.timeout) {
      await stop();
      return ReturnResultError("service start timeout");
    }
    if (result.err != null) {
      Log.w("VPNService.start err ${result.err!.message.toString()}");
      await stop();
      return convertErr(result.err);
    }
    String errorPath = await PathUtils.serviceStdErrorFilePath();
    String? content = await FileUtils.readAndDelete(errorPath);
    if (content != null && content.isNotEmpty) {
      await stop();
      return ReturnResultError(content);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      if (setting.alwayOn) {
        await FlutterVpnService.setAlwaysOn(setting.alwayOn);
      }
    }
    if (setting.proxy.autoSetSystemProxy) {
      await setSystemProxy(true);
    }
    return null;
  }

  static Future<void> stop() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await FlutterVpnService.setAlwaysOn(false);
    }
    await setSystemProxy(false);
    if (Platform.isWindows) {
      await _windowsStopCore();
      return;
    }
    await FlutterVpnService.stop();
  }

  static bool getSupportSystemProxy() {
    return PlatformUtils.isPC();
  }

  static Future<void> setSystemProxy(bool enable) async {
    if (getSupportSystemProxy()) {
      try {
        final options = await getSystemProxyOptions();
        if (options.port == 0) {
          return;
        }
        if (enable) {
          await FlutterVpnService.setSystemProxy(options);
        } else {
          if (await getSystemProxyEnable()) {
            await FlutterVpnService.cleanSystemProxy();
          }
        }
      } catch (err) {
        Log.w("VPNService setSystemProxy exception:${err.toString()}");
      }
    }
  }

  static Future<bool> getSystemProxyEnable() async {
    if (!getSupportSystemProxy()) {
      return false;
    }
    final hostOptionsLocal = getSystemProxyOptionsLocalhost();
    bool enable =
        await FlutterVpnService.getSystemProxyEnable(hostOptionsLocal);
    if (!enable) {
      final hostOptionsLan = await getSystemProxyOptionsLan();
      if (hostOptionsLan != null) {
        enable |=
            await FlutterVpnService.getSystemProxyEnable(hostOptionsLan);
      }
    }
    return enable;
  }

  static bool isRunAsAdmin() {
    return _runAsAdmin;
  }

  static Future<FlutterVpnServiceState> getState() async {
    return await FlutterVpnService.currentState;
  }

  static Future<bool> getStarted() async {
    FlutterVpnServiceState newState = await FlutterVpnService.currentState;
    if (newState == FlutterVpnServiceState.connected) {
      return true;
    }
    return false;
  }

  static Future<List<int?>> getPortsByPrefer(bool preferForward) async {
    var started = await getStarted();
    final mixedPort = SettingManager.getConfig().proxy.mixedRulePort;
    if (started) {
      if (preferForward) {
        return [mixedPort, null];
      }
      return [null, mixedPort];
    }
    return [null];
  }

  static Future<List<int?>> getPortsBySetting(ProxyStrategy strategy) async {
    switch (strategy) {
      case ProxyStrategy.preferProxy:
        return await getPortsByPrefer(true);
      case ProxyStrategy.preferDirect:
        return await getPortsByPrefer(false);
      case ProxyStrategy.onlyProxy:
        final started = await getStarted();
        return started ? [SettingManager.getConfig().proxy.mixedRulePort] : [null];
      case ProxyStrategy.onlyDirect:
        return [null];
    }
  }

  static Future<int?> getPort() async {
    final mixedPort = SettingManager.getConfig().proxy.mixedRulePort;
    var started = await getStarted();
    return started ? mixedPort : null;
  }

  static Future<ReturnResultError?> reload(Duration timeout) async {
    return restart(timeout);
  }

  /// fills [allOutboundsTags] and [allOutbounds] with the outbounds visible
  /// in the generated config (without urltest internals).
  static void getOutboundsWithoutUrltest(
    Set<String> allOutboundsTags,
    Tuple2<List<ProxyConfig>, List<dynamic>>? allOutbounds,
    List<String>? onlyForGroupId,
  ) {
    allOutboundsTags.clear();
    if (allOutbounds != null) {
      allOutbounds.item1.clear();
      allOutbounds.item2.clear();
    }
    for (var item in ServerManager.getConfig().items) {
      if (!item.enable) {
        continue;
      }
      if (onlyForGroupId != null && !onlyForGroupId.contains(item.groupid)) {
        continue;
      }
      for (var server in item.servers) {
        if (server.type == kOutboundTypeUrltest ||
            server.type == kOutboundTypeSelector) {
          continue;
        }
        allOutboundsTags.add(server.tag);
        if (allOutbounds != null) {
          allOutbounds.item1.add(server);
          final outbound = SingboxConfigBuilder.buildOutbound(server);
          if (outbound != null) {
            allOutbounds.item2.add(outbound);
          }
        }
      }
    }
  }

  static List<ProxyConfig> getUrltests(
    Set<String> allOutboundsTags, {
    bool uniTag = true,
    bool includeEmpty = false,
  }) {
    List<ProxyConfig> urltests = [];
    if (uniTag) {
      ProxyConfig pc = ProxyConfig();
      pc.type = kOutboundTypeUrltest;
      pc.groupid = ServerManager.getUrltestGroupId();
      pc.tag = kOutboundTagUrltest;
      pc.outbounds = allOutboundsTags.toList();
      urltests.add(pc);
    }
    for (var urltest in ServerManager.getCustomGroup().urltests) {
      Set<String> tags = {};
      for (var tag in urltest.tags) {
        if (allOutboundsTags.contains(tag)) {
          tags.add(tag);
        }
      }
      for (var regex in urltest.regexs) {
        RegExp? reg;
        try {
          reg = RegExp(regex, caseSensitive: false);
        } catch (err) {
          reg = null;
        }
        if (reg == null) {
          continue;
        }
        for (var tag in allOutboundsTags) {
          if (reg.hasMatch(tag)) {
            tags.add(tag);
          }
        }
      }
      if (!includeEmpty && tags.isEmpty) {
        continue;
      }
      ProxyConfig pc = ProxyConfig();
      pc.type = kOutboundTypeUrltest;
      pc.groupid = ServerManager.getUrltestGroupId();
      pc.tag = urltest.remark;
      pc.outbounds = tags.toList();
      urltests.add(pc);
    }
    return urltests;
  }

  static String getLaunchAtStartupTaskName() {
    return "${AppUtils.getName()} Autorun";
  }

  static Future<ReturnResultError?> setLaunchAtStartup(bool enable) async {
    if (PlatformUtils.isPC()) {
      try {
        if (enable) {
          if (Platform.isWindows) {
            bool admin = isRunAsAdmin();
            await FlutterVpnService.autoStartCreate(
              getLaunchAtStartupTaskName(),
              Platform.resolvedExecutable,
              processArgs: AppArgs.launchStartup,
              runElevated: admin,
            );
            return null;
          }
        } else {
          await FlutterVpnService.autoStartDelete(
              getLaunchAtStartupTaskName());
          await launchAtStartup.disable();
        }
      } catch (err) {
        return ReturnResultError(err.toString());
      }
    }
    return null;
  }

  static Future<bool> getLaunchAtStartup() async {
    if (PlatformUtils.isPC()) {
      try {
        if (Platform.isWindows) {
          if (await FlutterVpnService.autoStartIsActive(
            getLaunchAtStartupTaskName(),
          )) {
            return true;
          }
        }
        return await launchAtStartup.isEnabled();
      } catch (err) {
        return false;
      }
    }
    return false;
  }

  static ProxyOption getSystemProxyOptionsLocalhost() {
    final setting = SettingManager.getConfig();
    return ProxyOption(
      localhost,
      setting.proxy.mixedRulePort,
      setting.proxy.systemProxyBypassDomain.join(','),
    );
  }

  static Future<ProxyOption?> getSystemProxyOptionsLan() async {
    if (!PlatformUtils.isPC()) {
      return null;
    }
    var host = localhost;
    List<NetInterfacesInfo> interfaces = await NetworkUtils.getInterfaces();
    if (interfaces.length == 1) {
      host = interfaces[0].address;
    } else {
      for (var face in interfaces) {
        if (Platform.isMacOS && face.name.startsWith("en")) {
          host = face.address;
          break;
        }
      }
    }
    final setting = SettingManager.getConfig();
    return ProxyOption(
      host,
      setting.proxy.mixedRulePort,
      setting.proxy.systemProxyBypassDomain.join(','),
    );
  }

  static Future<ProxyOption> getSystemProxyOptions() async {
    final setting = SettingManager.getConfig();
    final bypassDomain = setting.proxy.systemProxyBypassDomain.join(',');
    final mixedPort = setting.proxy.mixedRulePort;
    if (Platform.isMacOS) {
      List<NetInterfacesInfo> interfaces = await NetworkUtils.getInterfaces(
        addressType: InternetAddressType.IPv4,
      );
      for (var face in interfaces) {
        if (face.name.startsWith("en")) {
          return ProxyOption(face.address, mixedPort, bypassDomain);
        }
      }
    }
    return ProxyOption(localhost, mixedPort, bypassDomain);
  }
}
