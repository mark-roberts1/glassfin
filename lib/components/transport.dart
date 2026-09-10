/// The playback transport.
///
/// **Entirely `over*` coloured.** It is read against a film, and the page behind
/// it may be paper — paper-on-picture is illegible at any hour. See
/// `docs/ui-spec.md` §4.6.
///
/// The Qt build drew this over a *separate* mpv surface through a transparent
/// web view, and keeping those two renderers agreeing was the source of every
/// hard bug in that project. Here it is a widget above a widget.
library;

import 'package:flutter/widgets.dart';

import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../format.dart';
import '../jellyfin/labels.dart';
import '../playback/controller.dart';

class PlayerTransport extends StatelessWidget {
  const PlayerTransport({required this.playback, super.key});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final item = playback.item;
    if (item == null) return const SizedBox.shrink();

    final position = playback.position;
    final duration = playback.duration;
    final fraction = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final remaining = duration - position;
    final subtitle = episodeSubtitle(item);

    return AnimatedOpacity(
      opacity: playback.chromeVisible ? 1 : 0,
      duration: Motion.slow,
      curve: Motion.ease,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          metrics.safeX,
          // A deep top inset, because the gradient behind it needs somewhere to
          // fade from — a hard edge across the picture reads as a bug.
          Metrics.rem(6),
          metrics.safeX,
          metrics.safeY + Metrics.rem(1.5),
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              GlassfinTokens.overVideoScrim,
              GlassfinTokens.overVideoScrim.withValues(alpha: 0),
            ],
            stops: const [0.3, 1],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              itemTitle(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.rem(
                1.8,
                weight: Type.medium,
                em: Type.headingEm,
              ).copyWith(color: GlassfinTokens.overInk),
            ),
            if (subtitle.isNotEmpty) ...[
              SizedBox(height: Metrics.rem(0.25)),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.body.copyWith(color: GlassfinTokens.overInkDim),
              ),
            ],
            SizedBox(height: Metrics.rem(1.2)),
            _ScrubBar(
              fraction: fraction,
              elapsed: position,
              remaining: remaining,
            ),
            SizedBox(height: Metrics.rem(1)),
            _Hints(playback: playback),
          ],
        ),
      ),
    );
  }
}

class _ScrubBar extends StatelessWidget {
  const _ScrubBar({
    required this.fraction,
    required this.elapsed,
    required this.remaining,
  });

  final double fraction;
  final Duration elapsed;
  final Duration remaining;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      _Time(clock(elapsed)),
      SizedBox(width: Metrics.rem(1)),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            // Tall enough for the head, which overflows the 5px track.
            height: 14,
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
                // The head is what the eye tracks while seeking; the fill alone
                // is too subtle to follow at a distance.
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
      ),
      SizedBox(width: Metrics.rem(1)),
      // A **minus sign**, U+2212, not a hyphen: a hyphen at this size next to
      // tabular digits reads as part of the number.
      _Time('−${clock(remaining)}'),
    ],
  );
}

class _Time extends StatelessWidget {
  const _Time(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // Wide enough for `h:mm:ss` so the bar does not shift as the clock ticks
    // past a digit boundary.
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

/// What the buttons do, in the terms the remote uses.
class _Hints extends StatelessWidget {
  const _Hints({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final state = playback.switching
        ? 'Changing track…'
        : playback.paused
        ? 'Paused'
        : 'Playing';

    // Weight 500, not real bold: 600 and above synthesise fake bold, which on a
    // television looks like a rendering fault.
    final button = Type.rem(
      0.88,
      weight: Type.medium,
    ).copyWith(color: GlassfinTokens.overInkDim);
    final body = Type.rem(0.88).copyWith(color: GlassfinTokens.overInkFaint);

    return Wrap(
      spacing: Metrics.rem(1.6),
      runSpacing: Metrics.rem(0.4),
      children: [
        Text(state, style: button),
        _Hint(
          button: button,
          name: 'OK',
          body: body,
          what: playback.paused ? 'play' : 'pause',
        ),
        // The double space between the arrows is deliberate: they are two keys,
        // and set tight they read as one glyph.
        _Hint(button: button, name: '←  →', body: body, what: 'skip 30s'),
        _Hint(button: button, name: 'Up', body: body, what: 'audio & subtitles'),
        _Hint(button: button, name: 'Back', body: body, what: 'stop'),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.button,
    required this.name,
    required this.body,
    required this.what,
  });

  final TextStyle button;
  final String name;
  final TextStyle body;
  final String what;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: name, style: button),
        TextSpan(text: ' $what', style: body),
      ],
    ),
  );
}
