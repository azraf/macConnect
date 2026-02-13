import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:open_file_manager/open_file_manager.dart';

import 'screens/about_screen.dart';
import 'screens/help_screen.dart';
import 'services/webdav_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) FlutterForegroundTask.initCommunicationPort();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mac Connect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final WebDavService _webDav = WebDavService();
  ConnectionType _connectionType = ConnectionType.wifi;
  bool _isOn = false;
  String? _connectionUrl;
  String? _error;
  bool _loading = false;

  bool get _isUsb => _connectionType == ConnectionType.usb;
  bool get _usbSupported => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initForegroundTask());
    }
  }

  Future<void> _initForegroundTask() async {
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mac_connect_channel',
        channelName: 'Mac Connect',
        channelDescription: 'Shows when file share is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _toggle(bool value) async {
    if (_loading) return;
    if (_isUsb && !_usbSupported) return;

    setState(() {
      _loading = true;
      _error = null;
      _connectionUrl = null;
    });
    try {
      if (value) {
        final url = await _webDav.start(_connectionType);
        if (!_isUsb && url == null) {
          await _webDav.stop();
          final msg = _connectionType == ConnectionType.hotspot
              ? 'Could not get hotspot IP. Turn on Mobile Hotspot and try again.'
              : 'Could not get Wi‑Fi IP. Connect to the same Wi‑Fi as your Mac and try again.';
          setState(() {
            _isOn = false;
            _error = msg;
          });
        } else {
          setState(() {
            _isOn = true;
            _connectionUrl = url;
          });
        }
      } else {
        await _webDav.stop();
        setState(() => _isOn = false);
      }
    } catch (e) {
      await _webDav.stop();
      setState(() {
        _isOn = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onConnectionTypeChanged(ConnectionType? type) {
    if (type == null) return;
    setState(() {
      _connectionType = type;
      if (_isOn) {
        _webDav.getConnectionUrl().then((url) {
          if (mounted) setState(() => _connectionUrl = url);
        });
      }
    });
  }

  void _copyUrl() {
    final text = _isUsb ? WebDavService.localhostUrl : _connectionUrl;
    if (text == null) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL copied to clipboard')),
    );
  }

  Future<void> _openShareFolderInFileManager() async {
    try {
      final path = await WebDavService.getSharePath();
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      if (Platform.isAndroid) {
        openFileManager(
          androidConfig: AndroidConfig(
            folderType: AndroidFolderType.other,
            folderPath: path,
          ),
          iosConfig: IosConfig(folderPath: 'SharedWithMac'),
        );
      } else {
        openFileManager(iosConfig: IosConfig(folderPath: 'SharedWithMac'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open folder: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = Scaffold(
      appBar: AppBar(
        title: const Text('Mac Connect'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const HelpScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const AboutScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 8),
            const Text(
              'Connection type',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose how your Mac will connect to this device.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            _ConnectionTypeSelector(
              value: _connectionType,
              onChanged: _onConnectionTypeChanged,
              usbSupported: _usbSupported,
            ),
            const SizedBox(height: 24),
            const Text(
              'File transfer mode',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _connectionHint,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  _isOn ? 'On' : 'Off',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _isOn ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 16),
                Switch(
                  value: _isOn,
                  onChanged: (_isUsb && !_usbSupported) ? null : (_loading ? null : _toggle),
                ),
                if (_loading) const SizedBox(width: 12),
                if (_loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(_error!, style: TextStyle(color: Colors.red.shade900))),
                  ],
                ),
              ),
            ],
            if (_isOn) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Shared folder on this device',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The folder shared with your Mac is named "SharedWithMac". '
                'It lives inside this app\'s documents. Files you add here on the phone '
                'appear in Finder; files you add from the Mac appear here.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openShareFolderInFileManager,
                icon: const Icon(Icons.folder_open),
                label: const Text('Open shared folder in file browser'),
              ),
              const SizedBox(height: 24),
              const Text(
                'On your Mac',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ..._macInstructions,
            ],
            const SizedBox(height: 32),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const HelpScreen(),
                    ),
                  ),
                  child: const Text('Help'),
                ),
                Text(
                  ' · ',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 14,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const AboutScreen(),
                    ),
                  ),
                  child: const Text('About'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    return Platform.isAndroid
        ? WithForegroundTask(child: child)
        : child;
  }

  String get _connectionHint {
    switch (_connectionType) {
      case ConnectionType.wifi:
        return 'Turn on when this device and your Mac are on the same Wi‑Fi network.';
      case ConnectionType.hotspot:
        return 'Turn on Mobile Hotspot on this device, connect your Mac to it, then turn this on.';
      case ConnectionType.usb:
        return _usbSupported
            ? 'Connect this device to your Mac with a USB cable, then turn this on.'
            : 'USB connection is supported on Android only. Use Wi‑Fi or Hotspot on this device.';
    }
  }

  List<Widget> get _macInstructions {
    if (_isUsb && _usbSupported) {
      return [
        const Text(
          '1. Connect this device to your Mac with a USB cable.\n'
          '2. On your phone: enable USB debugging (Developer options).\n'
          '3. On your Mac: install ADB if needed, then run in Terminal:',
          style: TextStyle(color: Colors.black87, height: 1.4),
        ),
        const SizedBox(height: 8),
        _CopyableCode('adb forward tcp:8080 tcp:8080'),
        const SizedBox(height: 12),
        const Text(
          '4. Open Finder → Go → Connect to Server (⌘K) and enter the URL below.\n'
          '5. When asked "Connect as:", choose Guest (no password).',
          style: TextStyle(color: Colors.black87, height: 1.4),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _copyUrl,
          child: _UrlChip(WebDavService.localhostUrl),
        ),
        const SizedBox(height: 16),
      const Text(
        'After connecting, you\'ll see the "SharedWithMac" folder. You can open, edit, save, and delete files from Finder.',
        style: TextStyle(color: Colors.black54, height: 1.4),
      ),
      const SizedBox(height: 12),
      Text(
        'If Finder connects but you can\'t create or paste files from Mac, try a WebDAV client like Cyberduck with the same URL. '
        'Use the URL exactly as shown (including http://) and choose Guest when prompted.',
        style: TextStyle(color: Colors.orange.shade800, fontSize: 13, height: 1.3),
      ),
    ];
  }

  if (_connectionUrl == null) return [];

    return [
      const Text(
        '1. Open Finder\n'
        '2. Press ⌘K (or menu Go → Connect to Server)\n'
        '3. Enter this address and click Connect.\n'
        '4. When asked "Connect as:", choose Guest (no password).',
        style: TextStyle(color: Colors.black87, height: 1.4),
      ),
      const SizedBox(height: 12),
      InkWell(
        onTap: _copyUrl,
        child: _UrlChip(_connectionUrl!),
      ),
      const SizedBox(height: 16),
      const Text(
        'After connecting, you\'ll see the "SharedWithMac" folder. You can open, edit, save, and delete files from Finder.',
        style: TextStyle(color: Colors.black54, height: 1.4),
      ),
      const SizedBox(height: 12),
      Text(
        'If Finder connects but you can\'t create or paste files from Mac, try a WebDAV client like Cyberduck with the same URL. '
        'Use the URL exactly as shown (including http://) and choose Guest when prompted.',
        style: TextStyle(color: Colors.orange.shade800, fontSize: 13, height: 1.3),
      ),
    ];
  }
}

class _ConnectionTypeSelector extends StatelessWidget {
  const _ConnectionTypeSelector({
    required this.value,
    required this.onChanged,
    required this.usbSupported,
  });

  final ConnectionType value;
  final ValueChanged<ConnectionType?> onChanged;
  final bool usbSupported;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _OptionTile(
            type: ConnectionType.wifi,
            title: 'Same Wi‑Fi network',
            subtitle: 'Phone and Mac on the same Wi‑Fi',
            icon: Icons.wifi,
            selected: value == ConnectionType.wifi,
            onTap: () => onChanged(ConnectionType.wifi),
          ),
          const Divider(height: 1),
          _OptionTile(
            type: ConnectionType.hotspot,
            title: 'Mobile hotspot',
            subtitle: 'Mac connects to this device\'s Wi‑Fi',
            icon: Icons.mobile_friendly,
            selected: value == ConnectionType.hotspot,
            onTap: () => onChanged(ConnectionType.hotspot),
          ),
          const Divider(height: 1),
          _OptionTile(
            type: ConnectionType.usb,
            title: 'USB cable',
            subtitle: usbSupported
                ? 'Connect with USB Type‑C (Android)'
                : 'Not available on iPhone – use Wi‑Fi or Hotspot',
            icon: Icons.usb,
            selected: value == ConnectionType.usb,
            onTap: usbSupported ? () => onChanged(ConnectionType.usb) : null,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ConnectionType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 28,
                color: onTap == null ? theme.disabledColor : theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: onTap == null ? theme.disabledColor : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onTap == null ? theme.disabledColor : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlChip extends StatelessWidget {
  const _UrlChip(this.url);

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              url,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
              ),
            ),
          ),
          Icon(Icons.copy, size: 20, color: Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }
}

class _CopyableCode extends StatelessWidget {
  const _CopyableCode(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Command copied to clipboard')),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
            Icon(Icons.copy, size: 18, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
