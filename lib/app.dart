/// The application root: session state, the route stack, the ambient backdrop,
/// and **the single place input enters the application**.
///
/// The layering here is `docs/ui-spec.md` §0's z-index ladder: ambient backdrop
/// and veil, then the current screen, then the player, then the keyboard sheet,
/// then the overlays. The old build expressed it as `z-index` numbers on fixed
/// elements; here it is the order of a [Stack]'s children, which is the same
/// thing said once instead of nine times.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components/ambient.dart';
import 'components/keyboard.dart';
import 'design/metrics.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'input/keyboard.dart';
import 'input/router.dart';
import 'input/text_entry.dart';
import 'jellyfin/client.dart';
import 'jellyfin/models.dart';
import 'jellyfin/session_store.dart';
import 'nav/policy.dart';
import 'nav/registry.dart';
import 'nav/routes.dart';
import 'playback/controller.dart';
import 'screens/detail_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/login_screen.dart';
import 'screens/player_overlay.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
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

  /// Owned here rather than by the Search screen, so that a search term survives
  /// opening a film and coming back.
  final TextEditingController _searchTerm = TextEditingController();

  String? _deviceId;
  Preferences _preferences = const Preferences();
  SubtitleAppearance _subtitles = const SubtitleAppearance();
  Jellyfin? _client;
  PlaybackController? _playback;
  bool _ready = false;

  RouteStack _routes = RouteStack.initial;
  String? _ambient;
  bool _menuOpen = false;

  /// The keyboard sheet's session, when one is open.
  TextEntrySession? _modalEntry;

  /// Search's session is owned here rather than by the screen for one reason:
  /// **physical typing is routed by this widget**, so the field the keys go into
  /// has to be knowable from here. A session created inside the screen would be
  /// invisible to the key handler, and typing on a real keyboard would silently
  /// do nothing on the one screen most likely to be typed into.
  late final TextEntrySession _searchSession = TextEntrySession(
    label: 'Search',
    controller: _searchTerm,
    placeholder: 'Film or series title',
    persistent: true,
    // Harmless when there are no results: focusing an empty group is a no-op
    // and leaves focus on the key that was pressed.
    onCommit: () => NavRegistry.instance.focusGroup('search-results'),
  );

  /// Whichever field keys should go into: Search's inline one when that screen
  /// is up, the modal sheet's otherwise.
  TextEntrySession? get _activeEntry => _isSearch ? _searchSession : _modalEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  Future<void> _restore() async {
    final deviceId = await _store.deviceId();
    final preferences = await _store.readPreferences();
    final subtitles = await _store.readSubtitleAppearance();
    final credentials = await _store.readCredentials();

    if (!mounted) return;
    setState(() {
      _deviceId = deviceId;
      _preferences = preferences;
      _subtitles = subtitles;
      _ready = true;
    });
    if (credentials != null) _signIn(credentials, persist: false);
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  void _signIn(Credentials credentials, {bool persist = true}) {
    final client = Jellyfin(
      credentials: credentials,
      deviceId: _deviceId ?? 'unknown',
      video: const VideoSettings(),
      audio: const AudioSettings(),
    );

    setState(() {
      _client = client;
      _routes = RouteStack.initial;
      _modalEntry = null;
      _playback = PlaybackController(
        client: client,
        preferences: _preferences,
        video: const VideoSettings(),
        audio: const AudioSettings(),
        subtitles: _subtitles,
      )..addListener(_onPlaybackChanged);
    });

    if (persist) unawaited(_store.writeCredentials(credentials));
  }

  void _signOut() {
    unawaited(_store.clearCredentials());
    _playback?.removeListener(_onPlaybackChanged);
    _playback?.dispose();
    _client?.close();
    // A deep stack full of another account's items should not be waiting after
    // the next sign-in.
    NavRegistry.instance.clear();
    setState(() {
      _client = null;
      _playback = null;
      _routes = RouteStack.initial;
      _ambient = null;
      _modalEntry = null;
      _menuOpen = false;
    });
  }

  void _onPlaybackChanged() {
    // A film that ends or is stopped takes the track menu with it; leaving it up
    // over the screen underneath would be a modal nothing could dismiss.
    if (_menuOpen && !(_playback?.isPlaying ?? false)) _menuOpen = false;
    setState(() {});
  }

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
    _searchTerm.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  void _setPreferences(Preferences next) {
    setState(() => _preferences = next);
    _playback?.updateSettings(preferences: next);
    unawaited(_store.writePreferences(next));
  }

  void _setSubtitles(SubtitleAppearance next) {
    setState(() => _subtitles = next);
    // Applied to mpv immediately, so the effect is visible on a film that is
    // already playing rather than only on the next one.
    _playback?.updateSettings(subtitles: next);
    unawaited(_store.writeSubtitleAppearance(next));
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _push(GlassfinRoute route) => setState(() => _routes = _routes.push(route));

  /// **Episodes play; films and series open their detail screen.**
  ///
  /// An episode in Continue Watching or Next Up is unambiguous. A film has a
  /// resume point worth showing first, and a series has no single obvious
  /// episode to start.
  void _open(Item item) {
    if (item.playsImmediately) {
      _play(item);
      return;
    }
    _push(DetailRoute(item));
  }

  void _play(Item item) {
    setState(() => _menuOpen = false);
    unawaited(_playback?.start(item));
  }

  /// Back, in priority order: the keyboard sheet, then the track menu, then the
  /// route stack. Returns false only when there is genuinely nowhere to go.
  bool _back() {
    // Only the modal sheet, never Search's inline field: that one is part of
    // the screen, so Back there means "leave Search".
    final modal = _modalEntry;
    if (modal != null) {
      setState(() => _modalEntry = null);
      modal.onCancel?.call();
      _restoreFocus();
      return true;
    }
    if (_menuOpen) {
      setState(() => _menuOpen = false);
      return true;
    }
    if (!_routes.canPop) return false;
    setState(() => _routes = _routes.pop());
    _restoreFocus();
    return true;
  }

  /// After anything closes, something must hold focus again — an interface with
  /// nothing highlighted is a dead end, and dead ends are the specific failure
  /// the couch bar exists to prevent.
  void _restoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FocusManager.instance.primaryFocus?.context == null) {
        NavRegistry.instance.focusSomethingSensible();
      }
    });
  }

  void _openTextEntry(TextEntrySession session) =>
      setState(() => _modalEntry = session);

  void _commitTextEntry() {
    final session = _activeEntry;
    if (session == null) return;
    // Search's field is persistent: Done there means "I have finished typing,
    // move to the results", not "close the keyboard".
    if (!session.persistent) setState(() => _modalEntry = null);
    session.onCommit?.call();
    if (!session.persistent) _restoreFocus();
  }

  // ---------------------------------------------------------------------------
  // Building
  // ---------------------------------------------------------------------------

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
          child: ColoredBox(color: tokens.ground, child: _body(tokens)),
        ),
      ),
    );
  }

  Widget _body(GlassfinTokens tokens) {
    if (!_ready) return const SizedBox.expand();

    final client = _client;
    final playback = _playback;

    if (client == null || playback == null) {
      return _InputHost(
        // Nothing is playing on the sign-in screen, but the router still owns
        // the keyboard: text entry and directional movement both come through
        // it.
        playback: null,
        textEntry: _modalEntry,
        onCommitTextEntry: _commitTextEntry,
        onBack: _back,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LoginScreen(
              deviceId: _deviceId ?? 'unknown',
              onSignedIn: _signIn,
              onEditText: _openTextEntry,
            ),
            if (_modalEntry != null)
              _KeyboardSheet(
                session: _modalEntry!,
                onDone: _commitTextEntry,
              ),
          ],
        ),
      );
    }

    final playing = playback.isPlaying;

    return _InputHost(
      playback: playback,
      menuOpen: _menuOpen,
      onOpenMenu: () => setState(() => _menuOpen = true),
      onCloseMenu: () {
        setState(() => _menuOpen = false);
        _restoreFocus();
      },
      onSearch: () => _push(const SearchRoute()),
      onHome: () => setState(() => _routes = _routes.home()),
      onBack: _back,
      textEntry: _activeEntry,
      onCommitTextEntry: _commitTextEntry,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AmbientBackdrop(
            imageUrl: _ambient,
            // Suppressed during playback, and on Detail — which draws its own
            // hero, and would otherwise have two backdrops fighting.
            visible: !playing && !_routes.isDetail,
          ),

          // **Hidden, never unmounted.** Scroll position and focus survive a
          // film, which is the whole reason the player is a layer rather than a
          // route.
          Visibility(
            visible: !playing,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            maintainInteractivity: true,
            child: _screen(client, playback),
          ),

          if (playing)
            PlayerOverlay(
              playback: playback,
              menuOpen: _menuOpen,
              onCloseMenu: () {
                setState(() => _menuOpen = false);
                _restoreFocus();
              },
            ),

          // Above the player: the keyboard is never wanted mid-film, but if a
          // session were somehow left open it must not be buried.
          if (_modalEntry != null)
            _KeyboardSheet(session: _modalEntry!, onDone: _commitTextEntry),
        ],
      ),
    );
  }

  /// Search hosts the keyboard **inline** in its own left pane, so the modal
  /// sheet must not also appear.
  bool get _isSearch => _routes.current is SearchRoute;

  Widget _screen(Jellyfin client, PlaybackController playback) =>
      switch (_routes.current) {
        HomeRoute() => HomeScreen(
          client: client,
          onOpen: _open,
          onLibrary: (library) => _push(LibraryRoute(library)),
          onSearch: () => _push(const SearchRoute()),
          onSettings: () => _push(const SettingsRoute()),
          onAmbient: _setAmbient,
        ),

        SearchRoute() => SearchScreen(
          client: client,
          session: _searchSession,
          onOpen: _open,
          onBack: _back,
          onAmbient: _setAmbient,
        ),

        SettingsRoute() => SettingsScreen(
          preferences: _preferences,
          subtitles: _subtitles,
          credentials: client.credentials,
          onPreferences: _setPreferences,
          onSubtitles: _setSubtitles,
          onSignOut: _signOut,
          onReset: () => _setPreferences(const Preferences()),
          onBack: _back,
        ),

        LibraryRoute(library: final library) => LibraryScreen(
          client: client,
          library: library,
          onOpen: _open,
          onBack: _back,
          onAmbient: _setAmbient,
        ),

        DetailRoute(item: final item) => DetailScreen(
          client: client,
          item: item,
          onPlay: _play,
          onOpen: _open,
          onBack: _back,
        ),
      };

  void _setAmbient(Item item) {
    final url =
        _client?.imageUrl(item, type: 'Backdrop', maxWidth: 1280) ??
        _client?.imageUrl(item, maxWidth: 900);
    if (url == _ambient) return;
    setState(() => _ambient = url);
  }
}

/// The one keyboard listener the application has.
///
/// **No widget adds its own.** This is the most load-bearing rule in the project
/// and the easiest to erode: a second listener anywhere turns the total
/// playback/navigation split into an accident of tree order.
///
/// The router is built **here**, in a context beneath the [FocusTraversalGroup],
/// so that `moveFocus` reaches Glassfin's own policy. Built above it, it would
/// silently find Flutter's default one and the three deliberate navigation
/// behaviours would quietly stop applying.
class _InputHost extends StatelessWidget {
  const _InputHost({
    required this.playback,
    required this.textEntry,
    required this.onCommitTextEntry,
    required this.onBack,
    required this.child,
    this.menuOpen = false,
    this.onOpenMenu,
    this.onCloseMenu,
    this.onSearch,
    this.onHome,
  });

  final PlaybackController? playback;
  final TextEntrySession? textEntry;
  final VoidCallback onCommitTextEntry;
  final bool Function() onBack;
  final Widget child;
  final bool menuOpen;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onCloseMenu;
  final VoidCallback? onSearch;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final router = InputRouter(
      playback: playback,
      onNavigate: (action) => moveFocus(context, action),
      menuOpen: menuOpen,
      onOpenMenu: onOpenMenu,
      onCloseMenu: onCloseMenu,
      onSearch: onSearch,
      onHome: onHome,
      onBack: onBack,
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        // Text entry gets first refusal, exactly as the old `route()` did — but
        // for the opposite reason. There, the shell ate every key and typing had
        // to be reconstructed from actions. Here Flutter delivers real
        // characters with real case, and this is what lets a physical keyboard
        // and the on-screen one write into the same field mid-word.
        final entry = textEntry;
        if (entry != null && _typeInto(entry, event)) {
          return KeyEventResult.handled;
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

  /// True if this key was typing rather than navigation.
  bool _typeInto(TextEntrySession entry, KeyEvent event) {
    // Backspace is mapped to Back everywhere else; while a field is open it
    // deletes, which is what every keyboard in the world does.
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      entry.backspace();
      return true;
    }
    // Enter commits. Note this is keyed on the *physical* Enter rather than on
    // the `select` action, so a remote's OK button still presses whichever
    // on-screen key has focus.
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      onCommitTextEntry();
      return true;
    }

    final character = event.character;
    if (character == null || character.isEmpty) return false;
    // Control characters are not text. Space is, which is why this runs before
    // the action table maps it to play/pause.
    if (character.codeUnitAt(0) < 0x20) return false;
    entry.insert(character);
    return true;
  }
}

/// The modal keyboard, over a scrim.
///
/// Search does not use this — it embeds the same keyboard inline in its own
/// pane, because there the results have to stay visible while you type.
class _KeyboardSheet extends StatelessWidget {
  const _KeyboardSheet({required this.session, required this.onDone});

  final TextEntrySession session;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The page's own ground rather than `overScrim`: this is over the
        // interface, not over a film.
        ColoredBox(color: tokens.ground.withValues(alpha: 0.92)),
        Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: context.metrics.safeX,
              vertical: context.metrics.safeY,
            ),
            child: OnScreenKeyboard(session: session, onDone: onDone),
          ),
        ),
      ],
    );
  }
}
