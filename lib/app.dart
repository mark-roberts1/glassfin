/// The application root: session state, the single input entry point, and the
/// route stack.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/theme.dart';
import 'design/tokens.dart';
import 'input/keyboard.dart';
import 'input/router.dart';
import 'jellyfin/client.dart';
import 'jellyfin/models.dart';
import 'jellyfin/session_store.dart';
import 'nav/policy.dart';
import 'nav/registry.dart';
import 'playback/controller.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/player_overlay.dart';
import 'settings/audio_settings.dart';
import 'settings/preferences.dart';
import 'settings/subtitle_appearance.dart';
import 'settings/video_settings.dart';

class GlassfinApp extends StatefulWidget {
  const GlassfinApp({super.key});

  @override
  State<GlassfinApp> createState() => _GlassfinAppState();
}

class _GlassfinAppState extends State<GlassfinApp> with WidgetsBindingObserver {
  final SessionStore _store = SessionStore();

  String? _deviceId;
  Preferences _preferences = const Preferences();
  Jellyfin? _client;
  PlaybackController? _playback;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  Future<void> _restore() async {
    final deviceId = await _store.deviceId();
    final preferences = await _store.readPreferences();
    final credentials = await _store.readCredentials();

    if (!mounted) return;
    setState(() {
      _deviceId = deviceId;
      _preferences = preferences;
      _ready = true;
    });
    if (credentials != null) _signIn(credentials, persist: false);
  }

  void _signIn(Credentials credentials, {bool persist = true}) {
    final client = Jellyfin(
      credentials: credentials,
      deviceId: _deviceId ?? 'unknown',
      video: const VideoSettings(),
      audio: const AudioSettings(),
    );

    setState(() {
      _client = client;
      _playback = PlaybackController(
        client: client,
        preferences: _preferences,
        video: const VideoSettings(),
        audio: const AudioSettings(),
        subtitles: const SubtitleAppearance(),
      )..addListener(_onPlaybackChanged);
    });

    if (persist) unawaited(_store.writeCredentials(credentials));
  }

  void _onPlaybackChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Qt build only reported progress on its ten-second timer, so killing
    // the application mid-film threw away up to ten seconds of resume point.
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      unawaited(_playback?.reportProgressNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playback?.removeListener(_onPlaybackChanged);
    _playback?.dispose();
    _client?.close();
    super.dispose();
  }

  GlassfinTokens get _tokens => switch (_preferences.theme) {
    ThemePreference.light => GlassfinTokens.light,
    ThemePreference.dark => GlassfinTokens.dark,
    // Resolved against the platform only when explicitly asked for. Dark is the
    // default, because a television in a dark room is the case to be right
    // about and most shells have no palette preference worth consulting.
    ThemePreference.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.light
          ? GlassfinTokens.light
          : GlassfinTokens.dark,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens;

    return GlassfinTheme(
      tokens: tokens,
      child: MaterialApp(
        title: 'Glassfin',
        debugShowCheckedModeBanner: false,
        theme: GlassfinTheme.materialTheme(tokens),
        home: FocusTraversalGroup(
          policy: GlassfinTraversalPolicy(),
          child: _buildBody(tokens),
        ),
      ),
    );
  }

  Widget _buildBody(GlassfinTokens tokens) {
    if (!_ready) {
      return ColoredBox(color: tokens.ground, child: const SizedBox.expand());
    }

    final client = _client;
    final playback = _playback;

    if (client == null || playback == null) {
      return LoginScreen(deviceId: _deviceId ?? 'unknown', onSignedIn: _signIn);
    }

    return _InputHost(
      playback: playback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          HomeScreen(client: client, playback: playback, onSignOut: _signOut),
          // The player sits above the screen rather than replacing it, so scroll
          // position and focus survive a film.
          if (playback.item != null)
            PlayerOverlay(playback: playback, client: client),
        ],
      ),
    );
  }

  void _signOut() {
    unawaited(_store.clearCredentials());
    _playback?.removeListener(_onPlaybackChanged);
    _playback?.dispose();
    _client?.close();
    // A deep route stack should not be waiting after the next sign-in.
    NavRegistry.instance.clear();
    setState(() {
      _client = null;
      _playback = null;
    });
  }
}

/// Wraps the interface in the one keyboard listener the application has.
class _InputHost extends StatelessWidget {
  const _InputHost({required this.playback, required this.child});

  final PlaybackController playback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final router = InputRouter(
      playback: playback,
      onNavigate: (action) => moveFocus(context, action),
      onBack: () {
        // The walking skeleton has no route stack yet; Phase 5 gives it one.
        return false;
      },
    );

    return Focus(
      autofocus: true,
      // A listener rather than a handler with shortcuts: every key goes through
      // one function, which is the rule this whole file exists to enforce.
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final action = actionForKey(event);
        if (action == null) return KeyEventResult.ignored;
        return router.handle(action)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
