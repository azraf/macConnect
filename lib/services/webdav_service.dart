import 'dart:io';

import 'package:file/local.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';

import 'webdav_task_handler.dart';

/// How the Mac connects to this device: same WiFi, phone hotspot, or USB.
enum ConnectionType {
  /// Phone and Mac on the same Wi‑Fi network.
  wifi,

  /// Phone is the hotspot; Mac joins the phone’s Wi‑Fi.
  hotspot,

  /// Phone connected to Mac via USB cable (Android only; uses adb forward).
  usb,
}

/// Runs a WebDAV server exposing a "Shared with Mac" folder so macOS Finder
/// can mount it via Connect to Server (⌘K) and read/write/delete files.
class WebDavService {
  static const String prefix = '/dav';
  static const int port = 8080;

  HttpServer? _server;
  String? _sharePath;
  ConnectionType _connectionType = ConnectionType.wifi;

  /// Whether the server is running (main isolate on iOS, foreground service on Android).
  Future<bool> get isRunning async {
    if (Platform.isAndroid) return FlutterForegroundTask.isRunningService;
    return _server != null;
  }

  /// Path on device that is shared (for display / open file manager). Same path on Android & iOS.
  String? get sharePath => _sharePath;

  /// Returns the shared folder path. Use this for opening file manager (works when server off too).
  static Future<String> getSharePath() async {
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) return '${ext.path}/SharedWithMac';
      } catch (_) {}
    }
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/SharedWithMac';
  }

  /// Current connection type (used when building the Mac URL/instructions).
  ConnectionType get connectionType => _connectionType;

  /// Start the WebDAV server. Shares a folder under app documents.
  /// [type] controls how the Mac will connect (WiFi, Hotspot, or USB).
  /// Returns the URL for Mac (null for USB – use localhost + adb instructions).
  /// On Android runs in a foreground service so it keeps running when app is backgrounded.
  Future<String?> start(ConnectionType type) async {
    _connectionType = type;

    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.isRunningService) return _getUrl();
      _sharePath = await getSharePath();
      final dir = Directory(_sharePath!);
      if (!await dir.exists()) await dir.create(recursive: true);
      await FlutterForegroundTask.saveData(key: 'sharePath', value: _sharePath!);
      await FlutterForegroundTask.startService(
        notificationTitle: 'Mac Connect',
        notificationText: 'File share is running — tap to open',
        callback: webDavTaskCallback,
        serviceTypes: [ForegroundServiceTypes.dataSync],
      );
      return _getUrl();
    }

    // iOS (and other platforms): run server in process
    if (_server != null) return _getUrl();

    _sharePath = await getSharePath();
    final dir = Directory(_sharePath!);
    if (!await dir.exists()) await dir.create(recursive: true);

    const fs = LocalFileSystem();
    final davRoot = fs.directory(_sharePath!);
    final config = DAVConfig(
      root: davRoot,
      prefix: prefix,
      allowAnonymous: true,
      readOnly: false,
      verbose: true,
      enableThrottling: false,
    );
    final dav = ShelfDAV.withConfig(config);

    try {
      _server = await shelf_io.serve(
        dav.handler,
        InternetAddress.anyIPv4,
        port,
      );
      _server!.idleTimeout = const Duration(hours: 8);
      return _getUrl();
    } catch (e) {
      _sharePath = null;
      rethrow;
    }
  }

  /// Stop the WebDAV server.
  Future<void> stop() async {
    if (Platform.isAndroid) {
      FlutterForegroundTask.sendDataToTask(WebDavTaskHandler.stopCommand);
      await FlutterForegroundTask.stopService();
      _sharePath = null;
      return;
    }
    final server = _server;
    _server = null;
    _sharePath = null;
    if (server != null) await server.close(force: true);
  }

  /// Get the URL for Mac based on current [connectionType].
  Future<String?> _getUrl() async {
    switch (_connectionType) {
      case ConnectionType.wifi:
        final ip = await _getWifiIp();
        if (ip == null || ip.isEmpty) return null;
        return 'http://$ip:$port$prefix/';
      case ConnectionType.hotspot:
        final ip = await _getHotspotIp();
        if (ip == null || ip.isEmpty) return null;
        return 'http://$ip:$port$prefix/';
      case ConnectionType.usb:
        return null; // Mac uses localhost + adb forward
    }
  }

  /// Get device WiFi IP when phone and Mac are on the same Wi‑Fi.
  Future<String?> _getWifiIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      if (ip != null && ip.isNotEmpty) return ip;
      return _firstNonLoopbackIp();
    } catch (_) {}
    return null;
  }

  /// Get device IP when phone is the hotspot (Mac connects to phone’s Wi‑Fi).
  Future<String?> _getHotspotIp() async {
    try {
      // Prefer common hotspot gateway IPs (phone is the gateway).
      const candidates = ['192.168.43.1', '192.168.42.1', '10.0.0.1', '192.168.178.1'];
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          if (candidates.contains(addr.address)) return addr.address;
        }
      }
      return _firstNonLoopbackIp();
    } catch (_) {}
    return null;
  }

  Future<String?> _firstNonLoopbackIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get current connection URL (null if server not running or IP unknown / USB).
  Future<String?> getConnectionUrl() async {
    if (Platform.isAndroid && await FlutterForegroundTask.isRunningService) return _getUrl();
    if (_server == null) return null;
    return _getUrl();
  }

  /// URL the Mac should use for USB mode (after adb forward on Mac).
  static String get localhostUrl => 'http://127.0.0.1:$port$prefix/';
}
