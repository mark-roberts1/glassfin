/// The player: video, transport, track menu, skip prompt.
///
/// **The whole point of the rewrite is visible here.** In the Qt build this was
/// a transparent web page composited over a separate mpv surface, and keeping
/// those two renderers agreeing was the source of every hard bug in the project
/// — including a compositor that stopped producing frames entirely at *exactly*
/// zero alpha, which is why the old CSS set `rgba(0,0,0,0.004)` rather than
/// nothing. Here the video is a widget and the chrome is drawn on top of it in
/// the same tree, by the same renderer, and none of that exists.
///
/// Everything drawn here uses the `over*` tokens: it is read against a film, and
/// a photograph has no light mode.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../components/playback_menu.dart';
import '../components/player_settings_menu.dart';
import '../components/transport.dart';
import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../nav/pointer.dart';
import '../nav/registry.dart';
import '../playback/controller.dart';

class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({
    required this.playback,
    required this.menuOpen,
    required this.onCloseMenu,
    required this.settingsOpen,
    required this.onOpenMenu,
    required this.onOpenSettings,
    required this.onCloseSettings,
    required this.onStop,
    required this.onToggleFullscreen,
    required this.fullscreen,
    super.key,
  });

  final PlaybackController playback;

  /// Held by the application root rather than here, because the input router
  /// needs to know: while a menu is open, Back closes it instead of stopping
  /// the film.
  final bool menuOpen;
  final VoidCallback onCloseMenu;
  final bool settingsOpen;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenSettings;
  final VoidCallback onCloseSettings;
  final VoidCallback onStop;
  final VoidCallback onToggleFullscreen;
  final bool fullscreen;

  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> {
  late final VideoController _video = VideoController(widget.playback.player);

  /// Which offer the prompt was last focused for.
  ///
  /// Keyed on the segment rather than on "is there an offer", so that the credits
  /// offer later in the same film focuses too — and so that the many rebuilds in
  /// between, one per position tick, do not each steal focus again.
  Duration? _focusedSkip;

  /// Puts focus on the skip offer the moment it appears.
  ///
  /// The prompt arrives unannounced and leaves on its own, and it is the one
  /// thing on screen worth pressing while it is up — so making the viewer travel
  /// to it is asking them to find a button that is about to vanish. Select
  /// already takes the offer from anywhere, so this costs nothing when ignored;
  /// what it buys is that the obvious button is also the focused one.
  ///
  /// After the frame, because the prompt is being inserted into the tree by this
  /// same build and has no focus node to give until it exists.
  void _followSkipOffer() {
    final offer = widget.playback.skip;

    if (offer == null || widget.menuOpen || widget.settingsOpen) {
      _focusedSkip = null;
      return;
    }
    if (_focusedSkip == offer.end) return;
    _focusedSkip = offer.end;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Still worth having by the time the frame lands: a short offer, or a
      // viewer who took it immediately, and there is nothing to focus.
      if (widget.playback.skip == null) return;
      NavRegistry.instance.focusGroup(skipGroup);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final metrics = context.metrics;

    _followSkipOffer();

    return MouseRegion(
      // Moving the mouse revives the transport, exactly as pressing a button
      // does. The Qt build never needed this — it was driven by a remote — but
      // on a desk the mouse *is* the input, and a picture that will not answer
      // it reads as a hung application.
      //
      // Routed through PointerMode so that content moving under a stationary
      // cursor does not count, which would otherwise hold the chrome up forever.
      onHover: (event) {
        if (PointerMode.instance.noteMove(event.position)) {
          playback.nudgeChrome();
        }
      },
      cursor: PointerMode.instance.active.value
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Black behind the picture rather than the page ground: letterbox bars
          // are part of the film, and a paper-coloured frame around a 2.39:1
          // image is the single most obvious way to look wrong.
          ColoredBox(
            color: GlassfinTokens.overOnInk,
            child: Video(
              controller: _video,
              controls: NoVideoControls,
              fill: GlassfinTokens.overOnInk,
            ),
          ),

          if (playback.loading || playback.switching) const _Waiting(),

          if (playback.error != null)
            _Message(text: playback.error!, danger: true),

          if (playback.scanning) _ScanRate(rate: playback.scanRate),

          if (playback.chromeVisible &&
              !widget.menuOpen &&
              !widget.settingsOpen)
            Positioned.fill(
              child: PlayerTransport(
                playback: playback,
                onBack: widget.onStop,
                onSubtitles: widget.onOpenMenu,
                onSettings: widget.onOpenSettings,
                onFullscreen: widget.onToggleFullscreen,
                fullscreen: widget.fullscreen,
              ),
            ),

          // Above the transport, and offered rather than taken unless the viewer
          // asked for automatic skipping.
          if (playback.skip != null && !widget.menuOpen && !widget.settingsOpen)
            Positioned(
              right: metrics.safeX,
              bottom: metrics.safeY + Metrics.rem(9),
              child: _SkipPrompt(
                label: playback.skip!.label,
                onSelect: playback.takeSkip,
              ),
            ),

          if (widget.settingsOpen)
            PlayerSettingsMenu(
              playback: playback,
              onClose: widget.onCloseSettings,
            ),

          if (widget.menuOpen)
            PlaybackMenu(
              audioTracks: playback.audioTracks,
              subtitleTracks: playback.subtitleTracks,
              audioIndex: playback.audioIndex,
              subtitleIndex: playback.subtitleIndex,
              onAudio: (index) {
                playback.setAudioTrack(index);
                widget.onCloseMenu();
              },
              onSubtitle: (index) {
                playback.setSubtitleTrack(index);
                widget.onCloseMenu();
              },
            ),
        ],
      ),
    );
  }
}

/// Shown while the stream is being built or rebuilt. A transcode switch takes a
/// visible moment, and silence during it reads as a crash.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: GlassfinTokens.overScrim,
    child: Center(child: _Message(text: 'Loading…')),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: context.metrics.safeX),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Type.body.copyWith(
          color: danger ? GlassfinTokens.overDanger : GlassfinTokens.overInkDim,
        ),
      ),
    ),
  );
}

/// How fast the film is travelling, and which way.
///
/// **A scan is invisible without this.** The picture is moving and the position
/// is changing, but nothing says whether that is 2× or 32×, so there is no way to
/// judge whether to press again or to stop — and no way to tell a scan from a
/// film that has started behaving oddly. Centred rather than in the transport
/// because it is a mode the player is in, not a detail about the current item.
class _ScanRate extends StatelessWidget {
  const _ScanRate({required this.rate});

  /// Signed: negative is backward. Never zero — the caller only builds this while
  /// a scan is running.
  final int rate;

  @override
  Widget build(BuildContext context) => Center(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: GlassfinTokens.overPanel,
        borderRadius: Radii.br,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Metrics.rem(1.4),
          vertical: Metrics.rem(0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              rate > 0 ? Icons.fast_forward : Icons.fast_rewind,
              size: Type.rem(1.6).fontSize,
              color: GlassfinTokens.overInk,
            ),
            SizedBox(width: Metrics.rem(0.5)),
            Text(
              '${rate.abs()}×',
              style: Type.label.copyWith(color: GlassfinTokens.overInk),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The skip offer.
///
/// Focusable as well as bound to `select`, because the transport's own hint line
/// cannot say everything at once and a visible button is unambiguous.
class _SkipPrompt extends StatelessWidget {
  const _SkipPrompt({required this.label, required this.onSelect});

  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Focusable(
    group: skipGroup,
    // **Growth, not just the wash.** This was `overVideoSurface` — no ring and no
    // scale — on the reasoning that nothing over the film takes a ring. True, but
    // the other things in that category are rows and bars inside a panel, where
    // a change of background reads as a change of focus. This is a single button
    // floating on a photograph with nothing beside it to be brighter *than*, and
    // the wash alone was not enough to tell it apart from its resting state.
    visual: FocusVisual.overVideoControl,
    onSelect: onSelect,
    child: (context, focused) => AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.ease,
      padding: EdgeInsets.symmetric(
        horizontal: Metrics.rem(1.4),
        vertical: Metrics.rem(0.75),
      ),
      decoration: BoxDecoration(
        // **Filled with Paper when focused, not washed with it.** The rest of the
        // player is a row of glyphs on a photograph, where a wash plus growth is
        // enough. This is a one-off offer that appears unannounced and disappears
        // on its own, so it is worth being unmistakable about — and inverting to
        // a solid panel is a stronger signal than any amount of translucency,
        // without introducing the focus ring that nothing over the film takes.
        //
        // [GlassfinTokens.overOnInk] for the label is not decoration: Paper on
        // Paper is invisible, and this pair is the same one a poster's watched
        // tick already uses.
        color: focused ? GlassfinTokens.overInk : GlassfinTokens.overPanel,
        borderRadius: Radii.br,
      ),
      // Animated as well, and with the same curve: the panel fades between two
      // colours over 180ms, and a label that switched instantly would read as a
      // flicker rather than as the same object changing state.
      child: AnimatedDefaultTextStyle(
        duration: Motion.fast,
        curve: Motion.ease,
        style: Type.label.copyWith(
          color: focused ? GlassfinTokens.overOnInk : GlassfinTokens.overInk,
        ),
        child: Text(label),
      ),
    ),
  );
}
