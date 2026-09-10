/// The playback transport, modelled on the player in Jellyfin Media Player.
///
/// A top bar carrying a way out and the title, a full-width scrubber, and one
/// row of controls: step back, rewind, play/pause, forward, step on, the
/// wall-clock finish time, then subtitles, volume, settings and fullscreen.
///
/// **It keeps the reference's layout and loses its scale.** That player is
/// driven by a mouse; this one has to work from a sofa, so the glyphs are sized
/// for distance and every control is registered for directional navigation.
/// Nothing here is reachable only by pointer.
///
/// Left and right still seek, which is the one piece of the old transport worth
/// keeping — see [transportGroup] for how that coexists with a focusable row.
///
/// Entirely `over*` coloured: it is read against a film, and the page behind it
/// may be paper.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../format.dart';
import '../jellyfin/labels.dart';
import '../jellyfin/models.dart';
import '../playback/controller.dart';

/// The control row. Focus inside it moves between buttons.
const String transportGroup = 'transport';

/// The top bar's back button.
const String transportTopGroup = 'transport-top';

/// The scrubber.
///
/// Deliberately **not** part of [transportGroup]: the input router treats left
/// and right as a seek unless focus is on an actual button, so the scrubber
/// behaves like the slider it looks like while the row behaves like a toolbar.
const String transportScrubGroup = 'transport-scrub';

/// Big enough to hit from three metres. The reference draws these at about 24px
/// for a mouse; this is the same mark at a viewing distance.
double _glyph(BuildContext context) => Metrics.rem(1.9);

class PlayerTransport extends StatelessWidget {
  const PlayerTransport({
    required this.playback,
    required this.onBack,
    required this.onSubtitles,
    required this.onSettings,
    required this.onFullscreen,
    required this.fullscreen,
    super.key,
  });

  final PlaybackController playback;
  final VoidCallback onBack;
  final VoidCallback onSubtitles;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final item = playback.item;
    if (item == null) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: playback.chromeVisible ? 1 : 0,
      duration: Motion.slow,
      curve: Motion.ease,
      child: Column(
        children: [
          _TopBar(item: item, onBack: onBack),
          const Spacer(),
          _BottomBar(
            playback: playback,
            onSubtitles: onSubtitles,
            onSettings: onSettings,
            onFullscreen: onFullscreen,
            fullscreen: fullscreen,
          ),
        ],
      ),
    );
  }
}

/// One line: the way out, and what is playing.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.item, required this.onBack});

  final Item item;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final episode = episodeSubtitle(item);

    return Container(
      padding: EdgeInsets.fromLTRB(
        metrics.safeX,
        metrics.safeY,
        metrics.safeX,
        Metrics.rem(4),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GlassfinTokens.overVideoScrim,
            GlassfinTokens.overVideoScrim.withValues(alpha: 0),
          ],
          stops: const [0.25, 1],
        ),
      ),
      child: Row(
        children: [
          _IconButton(
            icon: Icons.arrow_back,
            semantic: 'Back',
            group: transportTopGroup,
            onSelect: onBack,
          ),
          SizedBox(width: Metrics.rem(1)),
          Expanded(
            child: Text(
              // One line, as the reference sets it: the series carries the
              // episode rather than being stacked above it.
              [itemTitle(item), if (episode.isNotEmpty) episode].join(' — '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.rem(
                1.35,
                em: Type.headingEm,
              ).copyWith(color: GlassfinTokens.overInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.playback,
    required this.onSubtitles,
    required this.onSettings,
    required this.onFullscreen,
    required this.fullscreen,
  });

  final PlaybackController playback;
  final VoidCallback onSubtitles;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Container(
      padding: EdgeInsets.fromLTRB(
        metrics.safeX,
        Metrics.rem(5),
        metrics.safeX,
        metrics.safeY,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            GlassfinTokens.overVideoScrim,
            GlassfinTokens.overVideoScrim.withValues(alpha: 0),
          ],
          stops: const [0.35, 1],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScrubBar(playback: playback),
          SizedBox(height: Metrics.rem(0.8)),
          _Controls(
            playback: playback,
            onSubtitles: onSubtitles,
            onSettings: onSettings,
            onFullscreen: onFullscreen,
            fullscreen: fullscreen,
          ),
        ],
      ),
    );
  }
}

/// Elapsed, the track, and time remaining.
///
/// Focusable, so that left and right seek while it holds focus — the row below
/// takes the same keys to move between buttons.
class _ScrubBar extends StatelessWidget {
  const _ScrubBar({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final duration = playback.duration;
    final fraction = duration.inMilliseconds <= 0
        ? 0.0
        : (playback.position.inMilliseconds / duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Time(clock(playback.position)),
        SizedBox(width: Metrics.rem(1)),
        Expanded(
          child: Focusable(
            group: transportScrubGroup,
            visual: FocusVisual.ringOnlyOverVideo,
            borderRadius: Radii.pill,
            // Select on the scrubber is play/pause, matching the space bar.
            // Seeking from a D-pad is left and right, which the router hands
            // to this group rather than to navigation.
            onSelect: playback.togglePause,
            child: (context, focused) => _Track(
              fraction: fraction,
              onScrub: (at) => playback.seekTo(
                Duration(milliseconds: (duration.inMilliseconds * at).round()),
              ),
            ),
          ),
        ),
        SizedBox(width: Metrics.rem(1)),
        // A minus sign, U+2212, not a hyphen: beside tabular digits a hyphen
        // reads as part of the number.
        _Time('−${clock(playback.remaining)}'),
      ],
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.fraction, required this.onScrub});

  final double fraction;

  /// Where along the track the viewer pressed or dragged, 0–1.
  final void Function(double fraction) onScrub;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      // **Click and drag to seek.** The bar looks exactly like a slider, and a
      // slider that does nothing when you drag it reads as a broken control
      // rather than as one meant for a remote. The D-pad path is left/right;
      // this is the same action for the input actually in the viewer's hand.
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _scrub(details.localPosition.dx, constraints.maxWidth),
      onHorizontalDragStart: (details) =>
          _scrub(details.localPosition.dx, constraints.maxWidth),
      onHorizontalDragUpdate: (details) =>
          _scrub(details.localPosition.dx, constraints.maxWidth),
      child: SizedBox(
        // Room for the head, which overflows the track it runs along.
        height: 16,
        child: Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: 5,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: GlassfinTokens.overTrack,
                  borderRadius: Radii.pill,
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: GlassfinTokens.overInk,
                      borderRadius: Radii.pill,
                    ),
                  ),
                ),
              ),
            ),
            // The head is what the eye tracks while seeking; the fill alone is too
            // subtle to follow at a distance.
            Positioned(
              left: constraints.maxWidth * fraction - 7,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlassfinTokens.overInk,
                  boxShadow: [
                    BoxShadow(
                      offset: Offset(0, 2),
                      blurRadius: 10,
                      color: Color(0xCC000000),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _scrub(double dx, double width) {
    if (width <= 0) return;
    onScrub((dx / width).clamp(0.0, 1.0));
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.playback,
    required this.onSubtitles,
    required this.onSettings,
    required this.onFullscreen,
    required this.fullscreen,
  });

  final PlaybackController playback;
  final VoidCallback onSubtitles;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _IconButton(
        icon: Icons.skip_previous,
        semantic: 'Previous episode',
        group: transportGroup,
        enabled: playback.hasPrevious,
        onSelect: playback.playPrevious,
      ),
      _IconButton(
        icon: Icons.fast_rewind,
        semantic: 'Back 30 seconds',
        group: transportGroup,
        onSelect: () => playback.seekBy(-seekStep),
      ),
      _IconButton(
        icon: playback.paused ? Icons.play_arrow : Icons.pause,
        semantic: playback.paused ? 'Play' : 'Pause',
        group: transportGroup,
        large: true,
        onSelect: playback.togglePause,
      ),
      _IconButton(
        icon: Icons.fast_forward,
        semantic: 'Forward 30 seconds',
        group: transportGroup,
        onSelect: () => playback.seekBy(seekStep),
      ),
      _IconButton(
        icon: Icons.skip_next,
        semantic: 'Next episode',
        group: transportGroup,
        enabled: playback.hasNext,
        onSelect: playback.playNext,
      ),
      SizedBox(width: Metrics.rem(1.2)),
      Text(
        playback.switching ? 'Changing track…' : endsAt(playback.remaining),
        style: Type.rem(0.95).copyWith(color: GlassfinTokens.overInkDim),
      ),

      const Spacer(),

      _IconButton(
        icon: Icons.closed_caption,
        semantic: 'Audio and subtitles',
        group: transportGroup,
        active: playback.subtitleIndex != null,
        onSelect: onSubtitles,
      ),
      _Volume(playback: playback),
      _IconButton(
        icon: Icons.settings,
        semantic: 'Playback settings',
        group: transportGroup,
        onSelect: onSettings,
      ),
      _IconButton(
        icon: fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        semantic: fullscreen ? 'Leave fullscreen' : 'Fullscreen',
        group: transportGroup,
        onSelect: onFullscreen,
      ),
    ],
  );
}

/// Speaker plus a level, as the reference lays it out.
///
/// The level is a readout rather than a drag target: select steps it, because a
/// D-pad cannot drag and a slider that only a mouse can move would fail the bar.
class _Volume extends StatelessWidget {
  const _Volume({required this.playback});

  final PlaybackController playback;

  static const double _step = 10;

  @override
  Widget build(BuildContext context) {
    final muted = playback.volume <= 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconButton(
          icon: muted ? Icons.volume_off : Icons.volume_up,
          semantic: muted ? 'Unmute' : 'Volume',
          group: transportGroup,
          // Wraps to zero at the top, so one button covers the whole range from
          // a remote with no dedicated volume keys.
          onSelect: () => playback.setVolume(
            playback.volume >= 100 ? 0 : playback.volume + _step,
          ),
        ),
        SizedBox(
          width: Metrics.rem(5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 4,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: GlassfinTokens.overTrack,
                  borderRadius: Radii.pill,
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (playback.volume / 100).clamp(0.0, 1.0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: GlassfinTokens.overInk,
                      borderRadius: Radii.pill,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: Metrics.rem(0.6)),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.semantic,
    required this.group,
    required this.onSelect,
    this.enabled = true,
    this.large = false,
    this.active = false,
  });

  final IconData icon;

  /// What this control is, for whoever next reads the row.
  final String semantic;
  final String group;
  final VoidCallback onSelect;
  final bool enabled;

  /// Play/pause, which is the one control anyone reaches for without looking.
  final bool large;

  /// Subtitles currently on: lit in the over-video accent, the same gold the
  /// track menu ticks with.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final size = _glyph(context) * (large ? 1.25 : 1);

    return Focusable(
      group: group,
      visual: FocusVisual.ringOnlyOverVideo,
      borderRadius: Radii.br,
      enabled: enabled,
      onSelect: onSelect,
      // No Semantics wrapper here. One inside the focus ring's Stack tripped
      // `!semantics.parentDataDirty` on a window resize, and a screen-reader
      // pass over this application should be designed across the whole
      // interface rather than bolted onto the one component that happens to
      // have icons instead of words.
      child: (context, focused) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Metrics.rem(0.5),
          vertical: Metrics.rem(0.35),
        ),
        child: Icon(
          icon,
          size: size,
          color: !enabled
              // Dimmed rather than hidden: a control that comes and goes moves
              // everything beside it, and a row that shifts under the viewer is
              // worse than one with a greyed button in it.
              ? GlassfinTokens.overInkFaint.withValues(alpha: 0.35)
              : active
              ? GlassfinTokens.overAccent
              : GlassfinTokens.overInk,
        ),
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // Wide enough for `h:mm:ss`, so the track does not shift as the clock
    // crosses a digit boundary.
    constraints: BoxConstraints(minWidth: Type.rem(0.95).fontSize! * 3.6),
    child: Text(
      text,
      style: Type.rem(0.95).copyWith(
        color: GlassfinTokens.overInkDim,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}
