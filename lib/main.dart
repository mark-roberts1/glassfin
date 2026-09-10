import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'design/metrics.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'nav/policy.dart';

/// Phase 0/1 scaffolding.
///
/// This is not the app. It proves the toolchain end to end before real work is
/// built on it — the Linux runner builds, `window_manager` controls the window,
/// Space Grotesk loads from `assets/fonts/`, the design system resolves, and
/// `media_kit` can actually reach `libmpv.so.2`. Phase 4 replaces it with the
/// walking skeleton.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(1280, 720),
      center: true,
      title: 'Glassfin',
      backgroundColor: GlassfinTokens.dark.ground,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(const GlassfinApp());
}

class GlassfinApp extends StatelessWidget {
  const GlassfinApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Dark is the default, not "follow the system": a television in a dark room
    // is the case to be right about. Settings will make this a preference.
    const tokens = GlassfinTokens.dark;

    return GlassfinTheme(
      tokens: tokens,
      child: MaterialApp(
        title: 'Glassfin',
        debugShowCheckedModeBanner: false,
        theme: GlassfinTheme.materialTheme(tokens),
        // One traversal policy for the whole application. Every focusable sits
        // under it, which is what makes "focus is never lost" enforceable rather
        // than aspirational.
        builder: (context, child) => FocusTraversalGroup(
          policy: GlassfinTraversalPolicy(),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const _ToolchainCheck(),
      ),
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
    final tokens = context.tokens;
    final metrics = context.metrics;

    final status = switch ((_mpvVersion, _error)) {
      (final String version, _) => version,
      (_, final Object error) => 'libmpv unavailable: $error',
      _ => 'probing libmpv…',
    };

    return Scaffold(
      backgroundColor: tokens.ground,
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.safeX,
          vertical: metrics.safeY,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Glassfin', style: Type.display.copyWith(color: tokens.ink)),
              const SizedBox(height: 12),
              Text(
                status,
                style: Type.body.copyWith(
                  color: _error == null ? tokens.inkFaint : tokens.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
