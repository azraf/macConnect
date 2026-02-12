import 'package:flutter/material.dart';

/// Help / FAQ screen: what users can and cannot do.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _section(
              context,
              'What is Mac Connect?',
              'Mac Connect lets you connect your iPhone or Android phone to your Mac and transfer files. '
              'Your phone runs a small file server (WebDAV) and your Mac connects to it via Finder (Go → Connect to Server). '
              'Files in the shared folder appear on both sides.',
            ),
            _section(
              context,
              'How can I connect?',
              'You can use:\n'
              '• Same Wi‑Fi — Phone and Mac on the same Wi‑Fi network.\n'
              '• Mobile hotspot — Turn on hotspot on the phone, connect the Mac to it, then turn on the share.\n'
              '• USB cable — Android only: connect with USB, run "adb forward tcp:8080 tcp:8080" on the Mac, then connect to the URL in Finder.',
            ),
            _section(
              context,
              'What can I do?',
              '• Turn on file sharing and get a URL to enter in Mac Finder (⌘K).\n'
              '• Browse, open, and download files from the "SharedWithMac" folder on your Mac.\n'
              '• On Android: keep sharing running when the app is in the background or the screen is locked (notification stays on).\n'
              '• Open the shared folder in your phone\'s file browser using the "Open shared folder in file browser" button.\n'
              '• Use Wi‑Fi, hotspot, or USB (Android) depending on your setup.',
            ),
            _section(
              context,
              'What are the limitations?',
              '• macOS Finder may not allow creating or pasting files into the share (it expects extra WebDAV features). '
              'If that happens, use a WebDAV client like Cyberduck on your Mac with the same URL.\n'
              '• On iPhone/iPad, the share stops when you leave the app or lock the device; iOS does not allow long‑running background servers.\n'
              '• USB connection is only supported on Android, not on iPhone.',
            ),
            _section(
              context,
              'Where are the files stored on my phone?',
              'In a folder named "SharedWithMac" inside the app\'s storage. '
              'On iOS you can see it in the Files app under "On My iPhone" → Mac Connect. '
              'On Android, use "Open shared folder in file browser" to open it in your file manager.',
            ),
            _section(
              context,
              'Connection drops or Mac cannot connect',
              '• Ensure the phone and Mac are on the same Wi‑Fi (or Mac is on the phone\'s hotspot).\n'
              '• Use the URL exactly as shown (including http://).\n'
              '• On Android, allow the app to run in the background and disable battery optimization for Mac Connect if the share stops when the screen is off.',
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black87,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
