import 'dart:io';

import 'package:file/local.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';

/// Entry point for the foreground task isolate (Android). Must be top-level.
@pragma('vm:entry-point')
void webDavTaskCallback() {
  FlutterForegroundTask.setTaskHandler(WebDavTaskHandler());
}

/// Task handler that runs the WebDAV server in a foreground service isolate (Android).
class WebDavTaskHandler extends TaskHandler {
  static const String stopCommand = 'stop';

  HttpServer? _server;
  static const String _prefix = '/dav';
  static const int _port = 8080;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final sharePath = await FlutterForegroundTask.getData<String>(key: 'sharePath');
    if (sharePath == null || sharePath.isEmpty) return;

    final dir = Directory(sharePath);
    if (!await dir.exists()) await dir.create(recursive: true);

    const fs = LocalFileSystem();
    final davRoot = fs.directory(sharePath);
    final config = DAVConfig(
      root: davRoot,
      prefix: _prefix,
      allowAnonymous: true,
      readOnly: false,
      verbose: true,
      enableThrottling: false,
    );
    final dav = ShelfDAV.withConfig(config);

    _server = await shelf_io.serve(
      dav.handler,
      InternetAddress.anyIPv4,
      _port,
    );
    _server!.idleTimeout = const Duration(hours: 8);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep-alive only; no need to update notification often.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data == stopCommand && _server != null) {
      _server!.close(force: true);
      _server = null;
    }
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
