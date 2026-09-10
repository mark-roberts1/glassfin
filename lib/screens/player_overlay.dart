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

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final metrics = context.metrics;

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
    group: 'skip',
    visual: FocusVisual.overVideoSurface,
    onSelect: onSelect,
    child: (context, focused) => AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.ease,
      padding: EdgeInsets.symmetric(
        horizontal: Metrics.rem(1.4),
        vertical: Metrics.rem(0.75),
      ),
      decoration: BoxDecoration(
        color: focused
            ? Color.alphaBlend(
                GlassfinTokens.overHighlight,
                GlassfinTokens.overPanel,
              )
            : GlassfinTokens.overPanel,
        borderRadius: Radii.br,
      ),
      child: Text(
        label,
        style: Type.label.copyWith(color: GlassfinTokens.overInk),
      ),
    ),
  );
}
