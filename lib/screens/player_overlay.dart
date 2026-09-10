/// The player — walking-skeleton version.
///
/// **The whole point of the rewrite is visible here.** In the Qt build this was
/// a transparent web page composited over a separate mpv surface, and keeping
/// those two renderers agreeing was the source of every hard bug in the project.
/// Here the video is a widget and the transport is drawn on top of it in the
/// same tree, by the same renderer.
///
/// Phase 5 replaces this with the real transport from `docs/ui-spec.md` §4.6 and
/// the track menu from §4.7.
library;

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../jellyfin/client.dart';
import '../playback/controller.dart';

class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({
    required this.playback,
    required this.client,
    super.key,
  });

  final PlaybackController playback;
  final Jellyfin client;

  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> {
  late final VideoController _video = VideoController(widget.playback.player);

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final metrics = context.metrics;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: const Color(0xFF000000),
          child: Video(
            controller: _video,
            controls: NoVideoControls,
            fill: const Color(0xFF000000),
          ),
        ),

        if (playback.loading || playback.switching)
          const ColoredBox(
            color: GlassfinTokens.overScrim,
            child: Center(child: CircularProgressIndicator()),
          ),

        if (playback.skip != null)
          Positioned(
            right: metrics.safeX,
            bottom: metrics.safeY * 4,
            child: _SkipPrompt(label: playback.skip!.label),
          ),

        if (playback.chromeVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Transport(playback: playback),
          ),
      ],
    );
  }
}

/// Drawn in the theme-invariant `over*` tokens, because it is read against a
/// photograph and a photograph has no light mode.
class _Transport extends StatelessWidget {
  const _Transport({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final position = playback.position;
    final duration = playback.duration;
    final fraction = duration.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.safeX,
        vertical: metrics.safeY,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), GlassfinTokens.overScrim],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            playback.item?.name ?? '',
            style: Type.heading.copyWith(color: GlassfinTokens.overInk),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: GlassfinTokens.overEdge,
              valueColor: const AlwaysStoppedAnimation(
                GlassfinTokens.overAccent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_clock(position)} / ${_clock(duration)}'
            '${playback.paused ? '   ⏸' : ''}',
            style: Type.body.copyWith(color: GlassfinTokens.overInkDim),
          ),
        ],
      ),
    );
  }
}

class _SkipPrompt extends StatelessWidget {
  const _SkipPrompt({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
    decoration: BoxDecoration(
      color: GlassfinTokens.overPanel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: GlassfinTokens.overEdge),
    ),
    child: Text(
      label,
      style: Type.label.copyWith(color: GlassfinTokens.overInk),
    ),
  );
}

String _clock(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  // Films get an hours field; a 40-minute episode should not read "0:40:12".
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
