/// One item on a shelf or in a grid.
///
/// Named `MediaCard` rather than `Card` because Material already owns that name,
/// and a screen that imported both would silently get the wrong one. The spec
/// calls it Card; see `docs/ui-spec.md` §4.1.
///
/// **The artwork is the focus target, but the whole box is what gets revealed.**
/// The title and caption are siblings of the focusable, so scrolling only the
/// artwork into view leaves the metadata under the fold — which is why this
/// carries a reveal key.
library;

import 'package:flutter/widgets.dart';

import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../format.dart';
import '../jellyfin/client.dart';
import '../jellyfin/labels.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';

/// Posters for films and series; stills for episodes and anything resumable.
enum CardShape {
  /// 2:3, from `Primary` at 480px.
  poster,

  /// 16:9, from `Thumb` → `Backdrop` → `Primary` at 720px.
  still,
}

class MediaCard extends StatefulWidget {
  const MediaCard({
    required this.item,
    required this.client,
    required this.group,
    this.shape = CardShape.poster,
    this.enter = GroupEntry.nearest,
    this.onSelect,
    this.onFocus,
    super.key,
  });

  final Item item;
  final Jellyfin client;
  final String group;
  final CardShape shape;

  /// [GroupEntry.first] in a scrolling row, where the column you were in means
  /// nothing; the default everywhere else, because a grid is aligned to the page.
  final GroupEntry enter;

  final VoidCallback? onSelect;
  final VoidCallback? onFocus;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  /// Held in the state rather than rebuilt, because a GlobalKey that changes
  /// identity between builds detaches the element it was pointing at.
  final GlobalKey _revealKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;
    final item = widget.item;
    final still = widget.shape == CardShape.still;

    final width = still ? metrics.stillWidth : metrics.posterWidth;
    final height = still ? metrics.stillHeight : metrics.posterHeight;

    final title = itemTitle(item);
    final caption = itemCaption(item);
    final runtime = still ? runtimeLabel(item.runtime) : '';

    return SizedBox(
      key: _revealKey,
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focusable(
            group: widget.group,
            enter: widget.enter,
            onSelect: widget.onSelect,
            onFocus: widget.onFocus,
            revealKey: _revealKey,
            child: (context, focused) => _Artwork(
              item: item,
              client: widget.client,
              shape: widget.shape,
              width: width,
              height: height,
              title: title,
            ),
          ),
          // Cleared by the same amount the artwork grows, so a focused card
          // lifts off its own title instead of sitting on top of it.
          SizedBox(height: metrics.focusRoom),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _line(title, Type.rem(0.92, weight: Type.medium), tokens.ink),
                if (caption.isNotEmpty)
                  _line(caption, Type.rem(0.82), tokens.inkDim),
                if (runtime.isNotEmpty)
                  _line(runtime, Type.rem(0.82), tokens.inkDim),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Single line, ellipsised. A wrapping title would change a card's height and
  /// ripple through the row it sits in.
  Widget _line(String text, TextStyle style, Color colour) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    softWrap: false,
    style: style.copyWith(color: colour),
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.item,
    required this.client,
    required this.shape,
    required this.width,
    required this.height,
    required this.title,
  });

  final Item item;
  final Jellyfin client;
  final CardShape shape;
  final double width;
  final double height;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final url = _imageUrl();
    final progress = _progress();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.raised,
        borderRadius: Radii.br,
        border: Border.all(color: tokens.edge),
      ),
      // The artwork, the resume bar and the tick all have to be clipped to the
      // same rounded box, which is why this is a clip rather than a decoration
      // image on the container above.
      child: ClipRRect(
        borderRadius: Radii.br,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null)
              _Placeholder(title: title)
            else
              Image.network(
                url,
                fit: BoxFit.cover,
                // A slow or missing image should leave the raised box behind it,
                // not a broken-image glyph.
                errorBuilder: (context, error, stack) =>
                    _Placeholder(title: title),
              ),

            // Resume progress sits on the artwork because that is where the eye
            // already is, and it is the one piece of state worth reading before
            // committing to something.
            if (progress > 1 && progress < 99)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ProgressBar(fraction: progress / 100),
              )
            else if (item.userData?.played ?? false)
              const Positioned(top: 8, right: 8, child: _WatchedTick()),
          ],
        ),
      ),
    );
  }

  String? _imageUrl() => switch (shape) {
    CardShape.poster => client.imageUrl(item, maxWidth: 480),
    CardShape.still =>
      client.imageUrl(item, type: 'Thumb', maxWidth: 720) ??
          client.imageUrl(item, type: 'Backdrop', maxWidth: 720) ??
          client.imageUrl(item, maxWidth: 720),
  };

  /// How far through the viewer already is, 0–100.
  double _progress() {
    final played = item.userData?.playedPercentage;
    if (played != null) return played;
    final position = item.userData?.playbackPositionTicks ?? 0;
    final total = item.runTimeTicks ?? 0;
    if (position > 0 && total > 0) return position / total * 100;
    return 0;
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tokens.raised,
    child: Padding(
      padding: EdgeInsets.all(Metrics.rem(1)),
      child: Center(
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Type.rem(0.85).copyWith(color: context.tokens.inkFaint),
        ),
      ),
    ),
  );
}

/// Over the poster, so it takes the colours that work on a photograph rather
/// than the theme's — in either theme.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: ColoredBox(
      color: GlassfinTokens.overArtwork,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: const ColoredBox(color: GlassfinTokens.overAccent),
      ),
    ),
  );
}

/// Also on the poster, so also fixed: a watched tick that inverted with the
/// theme would read as two different states across a library.
class _WatchedTick extends StatelessWidget {
  const _WatchedTick();

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: GlassfinTokens.overInk,
    ),
    child: Text(
      '✓',
      style: Type.rem(0.8).copyWith(color: GlassfinTokens.overOnInk),
    ),
  );
}
