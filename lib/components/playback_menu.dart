/// Audio and subtitle tracks, over the film.
///
/// **Entirely `over*` coloured**, like the transport it sits above. See
/// `docs/ui-spec.md` §4.7.
///
/// The footnote at the bottom is not decoration: changing a track the server is
/// transcoding tears down the stream and rebuilds it, and without warning that
/// pause reads as a crash.
library;

import 'package:flutter/widgets.dart';

import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';
import '../settings/languages.dart';

class PlaybackMenu extends StatefulWidget {
  const PlaybackMenu({
    required this.audioTracks,
    required this.subtitleTracks,
    required this.audioIndex,
    required this.subtitleIndex,
    required this.onAudio,
    required this.onSubtitle,
    super.key,
  });

  final List<MediaStream> audioTracks;
  final List<MediaStream> subtitleTracks;

  /// Jellyfin's absolute stream indices; null subtitles means off.
  final int? audioIndex;
  final int? subtitleIndex;

  final void Function(int absoluteIndex) onAudio;
  final void Function(int? absoluteIndex) onSubtitle;

  @override
  State<PlaybackMenu> createState() => _PlaybackMenuState();
}

class _PlaybackMenuState extends State<PlaybackMenu> {
  @override
  void initState() {
    super.initState();
    // The groups' contents are rebuilt each time this opens, so their focus
    // memory describes rows that no longer exist. Reset, then focus **by name** —
    // a generic "focus something sensible" would reach past this menu to the
    // screen behind the film.
    NavRegistry.instance.resetGroup('menu-audio');
    NavRegistry.instance.resetGroup('menu-subtitles');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!NavRegistry.instance.focusGroup('menu-audio')) {
        NavRegistry.instance.focusGroup('menu-subtitles');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: GlassfinTokens.overScrim),
        Positioned(
          left: metrics.safeX,
          right: metrics.safeX,
          bottom: metrics.safeY + Metrics.rem(4),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: metrics.menuMaxHeight),
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Column(
                      heading: 'Audio',
                      empty: 'No audio tracks reported.',
                      rows: [
                        for (final track in widget.audioTracks)
                          _Row(
                            label: trackLabel(track),
                            badges: trackBadges(track),
                            current: track.index == widget.audioIndex,
                            group: 'menu-audio',
                            onSelect: () => widget.onAudio(track.index),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: Metrics.rem(3)),
                  Expanded(
                    child: _Column(
                      heading: 'Subtitles',
                      empty: '',
                      rows: [
                        // Off is always first, and always present — a file with
                        // no subtitle tracks still needs the row to say so.
                        _Row(
                          label: 'Off',
                          badges: const [],
                          current: widget.subtitleIndex == null,
                          group: 'menu-subtitles',
                          onSelect: () => widget.onSubtitle(null),
                        ),
                        for (final track in widget.subtitleTracks)
                          _Row(
                            label: trackLabel(track),
                            badges: trackBadges(track),
                            current: track.index == widget.subtitleIndex,
                            group: 'menu-subtitles',
                            onSelect: () => widget.onSubtitle(track.index),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: metrics.safeX,
          bottom: metrics.safeY + Metrics.rem(1.5),
          child: Text(
            'Changing a track the server is transcoding reloads the stream '
            'and takes a moment.',
            style: Type.rem(0.85).copyWith(color: GlassfinTokens.overInkFaint),
          ),
        ),
      ],
    );
  }
}

/// **The server's own `DisplayTitle` is usually the best label** — "English -
/// AAC - 5.1" says more than anything assembled here, and it is what the viewer
/// will see in every other Jellyfin client. The fallback is for streams that
/// carry none.
String trackLabel(MediaStream stream) {
  final title = stream.displayTitle;
  if (title != null && title.isNotEmpty) return title;

  final language = stream.language;
  final codec = stream.codec;
  return [
    language == null || language.isEmpty ? 'Unknown' : languageName(language),
    if (codec != null && codec.isNotEmpty) codec.toUpperCase(),
  ].join(' · ');
}

List<String> trackBadges(MediaStream stream) => [
  if (stream.isDefault) 'Default',
  if (stream.isForced) 'Forced',
  // Worth saying out loud: a burned-in subtitle cannot be turned off without
  // the server rebuilding the stream, which is why picking it costs a pause.
  if (stream.deliveryMethod == DeliveryMethod.encode) 'Burned in',
];

class _Column extends StatelessWidget {
  const _Column({
    required this.heading,
    required this.empty,
    required this.rows,
  });

  final String heading;
  final String empty;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: EdgeInsets.only(bottom: Metrics.rem(0.9)),
        child: Text(
          heading,
          style: Type.rem(1).copyWith(color: GlassfinTokens.overInkDim),
        ),
      ),
      if (rows.isEmpty && empty.isNotEmpty)
        Text(
          empty,
          style: Type.body.copyWith(color: GlassfinTokens.overInkFaint),
        )
      else
        ...rows,
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.badges,
    required this.current,
    required this.group,
    required this.onSelect,
  });

  final String label;
  final List<String> badges;
  final bool current;
  final String group;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: Metrics.rem(0.5)),
    child: Focusable(
      group: group,
      visual: FocusVisual.overVideoSurface,
      onSelect: onSelect,
      child: (context, focused) => AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.ease,
        padding: EdgeInsets.symmetric(
          horizontal: Metrics.rem(1),
          vertical: Metrics.rem(0.7),
        ),
        // No hairline. Every row carrying its own 1px border turned the menu
        // into a stack of boxes; the panel fill alone gives it the same shape
        // with none of the ruling, and focus is the lit row.
        decoration: BoxDecoration(
          color: focused
              ? Color.alphaBlend(
                  GlassfinTokens.overHighlight,
                  GlassfinTokens.overPanel,
                )
              : GlassfinTokens.overPanel,
          borderRadius: Radii.br,
        ),
        child: Row(
          children: [
            // A fixed-width tick column, empty when this is not the current
            // track, so that the labels never shift sideways as the selection
            // moves down the list.
            SizedBox(
              width: Type.body.fontSize!,
              child: Text(
                current ? '✓' : '',
                style: Type.body.copyWith(color: GlassfinTokens.overAccent),
              ),
            ),
            SizedBox(width: Metrics.rem(0.7)),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.body.copyWith(
                  color: GlassfinTokens.overInk,
                  fontWeight: current ? Type.medium : null,
                ),
              ),
            ),
            for (final badge in badges) ...[
              SizedBox(width: Metrics.rem(0.7)),
              _Badge(badge),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: Metrics.rem(0.4),
      vertical: Metrics.rem(0.1),
    ),
    decoration: const BoxDecoration(
      border: Border.fromBorderSide(BorderSide(color: GlassfinTokens.overEdge)),
      borderRadius: Radii.chip,
    ),
    child: Text(
      text,
      style: Type.rem(0.74).copyWith(color: GlassfinTokens.overInkFaint),
    ),
  );
}
