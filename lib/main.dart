import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

/// Phase 0 scaffolding.
///
/// This is not the app; it is a smoke test that proves the whole toolchain is
/// wired up before any real work is built on top of it — the Linux runner
/// builds, `window_manager` controls the window, Space Grotesk loads from
/// `assets/fonts/`, and `media_kit` can actually reach `libmpv.so.2` and report
/// its version. Phase 4 replaces this with the walking skeleton.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1280, 720),
      center: true,
      title: 'Glassfin',
      backgroundColor: Color(0xFF0B0B0D),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(const _ScaffoldingApp());
}

class _ScaffoldingApp extends StatelessWidget {
  const _ScaffoldingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glassfin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Space Grotesk',
        scaffoldBackgroundColor: const Color(0xFF0B0B0D),
      ),
      home: const _ToolchainCheck(),
    );
  }
}

class _ToolchainCheck extends StatefulWidget {
  const _ToolchainCheck();

  @override
  State<_ToolchainCheck> createState() => _ToolchainCheckState();
}

class _ToolchainCheckState extends State<_ToolchainCheck> {
  String? _mpvVersion;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _probeMpv();
  }

  /// Creating a [Player] is what actually dlopen()s libmpv, so a version string
  /// coming back here means the native side is genuinely present and usable —
  /// not merely that the Dart package resolved.
  Future<void> _probeMpv() async {
    final player = Player();
    try {
      final native = player.platform as NativePlayer;
      final version = await native.getProperty('mpv-version');
      debugPrint('glassfin: $version');
      if (mounted) setState(() => _mpvVersion = version);
    } catch (error) {
      debugPrint('glassfin: libmpv probe failed: $error');
      if (mounted) setState(() => _error = error);
    } finally {
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = switch ((_mpvVersion, _error)) {
      (final String version, _) => version,
      (_, final Object error) => 'libmpv unavailable: $error',
      _ => 'probing libmpv…',
    };

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Glassfin',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w500,
                letterSpacing: -1,
                color: Color(0xFFF2F2F0),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              status,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: _error == null
                    ? const Color(0xFF8A8A94)
                    : const Color(0xFFE05252),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
