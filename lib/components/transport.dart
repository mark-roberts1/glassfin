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
            visual: FocusVisual.overVideoSurface,
            borderRadius: Radii.pill,
            // Select on the scrubber is play/pause, matching the space bar.
            // Seeking from a D-pad is left and right, which the router hands
            // to this group rather than to navigation.
            onSelect: playback.togglePause,
            child: (context, focused) => _Slider(
              active: focused,
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

/// **Both of this transport's sliders**, so that they cannot drift apart.
///
/// The scrub bar and the volume bar are the same control at two lengths: a
/// track, a fill, a head, click and drag to set, and a small growth when the
/// viewer is on it. They were written separately once and immediately diverged —
/// one grew a head and gestures while the other stayed a read-out.
class _Slider extends StatelessWidget {
  const _Slider({
    required this.active,
    required this.fraction,
    required this.onScrub,
  });

  /// Focused for the scrubber, hovered for the volume bar — whichever "the
  /// viewer is on this" means for the input in their hand.
  ///
  /// Active, the bar thickens and its head grows: the same "grow a little"
  /// signal the icon controls use, in the one shape that cannot scale. A
  /// full-width bar under an [AnimatedScale] would push whatever sits either
  /// side of it off their baseline.
  final bool active;

  final double fraction;

  /// Where along the track the viewer pressed or dragged, 0–1.
  final void Function(double fraction) onScrub;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      // **Click and drag to set.** The bar looks exactly like a slider, and a
      // slider that does nothing when you drag it reads as a broken control
      // rather than as one meant for a remote. The D-pad path is elsewhere;
      // this is the same action for the input actually in the viewer's hand.
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _scrub(details.localPosition.dx, constraints.maxWidth),
      onHorizontalDragStart: (details) =>
          _scrub(details.localPosition.dx, constraints.maxWidth),
      onHorizontalDragUpdate: (details) =>
          _scrub(details.localPosition.dx, constraints.maxWidth),
      child: SizedBox(
        // Room for the head at its active size, which overflows the track it
        // runs along. Fixed rather than growing: a bar that changed height
        // would move the whole control row under the viewer.
        height: 20,
        child: Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.ease,
              height: active ? 8 : 5,
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
              left: constraints.maxWidth * fraction - (active ? 9 : 7),
              child: AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.ease,
                width: active ? 18 : 14,
                height: active ? 18 : 14,
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
        _VolumeBar(level: playback.volume, onSet: playback.setVolume),
        SizedBox(width: Metrics.rem(0.6)),
      ],
    );
  }
}

/// The volume bar: **the scrub bar's [_Slider], at 5rem.**
///
/// It was drawn as a read-out beside the button and nothing else, which is the
/// same mistake the scrub bar made: a control shaped exactly like a slider that
/// ignores a drag reads as broken, not as one meant for a remote.
///
/// Deliberately **not** focusable, which is why it grows on hover rather than on
/// focus. Left and right inside the transport row are spoken for by navigation,
/// so a focusable bar would be one the D-pad could land on and then not be able
/// to move — a worse dead end than not stopping there at all. The button beside
/// it is the pad's path, and it wraps through the whole range on its own.
class _VolumeBar extends StatefulWidget {
  const _VolumeBar({required this.level, required this.onSet});

  /// 0–100, mpv's own scale.
  final double level;

  final void Function(double level) onSet;

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: Metrics.rem(5),
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _Slider(
        active: _hovered,
        fraction: (widget.level / 100).clamp(0.0, 1.0),
        onScrub: (at) => widget.onSet(at * 100),
      ),
    ),
  );
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
      visual: FocusVisual.overVideoControl,
      borderRadius: Radii.pill,
      enabled: enabled,
      onSelect: onSelect,
      // No Semantics wrapper here. One inside the focus ring's Stack tripped
      // `!semantics.parentDataDirty` on a window resize, and a screen-reader
      // pass over this application should be designed across the whole
      // interface rather than bolted onto the one component that happens to
      // have icons instead of words.
      child: (context, focused) => AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.ease,
        // Square padding, so the circle is a circle. It was asymmetric while
        // this drew a rounded rectangle, which as an ellipse looks like a
        // mistake rather than a shape.
        padding: EdgeInsets.all(Metrics.rem(0.45)),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused && enabled
              ? GlassfinTokens.overHighlight
              : const Color(0x00000000),
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
