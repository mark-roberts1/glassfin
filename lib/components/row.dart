/// A heading above a horizontally scrolling track of cards.
///
/// Named `MediaRow` rather than `Row`, which Flutter already owns — a screen
/// importing both would silently lay out its columns wrong. The spec calls it
/// Row; see `docs/ui-spec.md` §4.2.
///
/// **Two details here are load-bearing and both look like padding.**
///
///  1. The safe-area inset lives on the *track*, not on the page, so the first
///     card can still scroll flush to the frame edge without being clipped.
///  2. The top inset is [Metrics.focusRoom] rather than a round number, because
///     a scrolling box clips its own overflow — and what gets sliced off is the
///     top of the focus ring, which is the half of the highlight that reads from
///     a sofa.
library;

import 'package:flutter/widgets.dart';

import '../design/metrics.dart';
import '../design/theme.dart';
import '../jellyfin/client.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';
import 'card.dart';

class MediaRow extends StatelessWidget {
  const MediaRow({
    required this.title,
    required this.items,
    required this.client,
    required this.group,
    required this.onSelect,
    this.shape = CardShape.poster,
    this.onFocusItem,
    super.key,
  });

  final String title;
  final List<Item> items;
  final Jellyfin client;
  final String group;
  final CardShape shape;
  final void Function(Item item) onSelect;

  /// Drives the ambient backdrop.
  final void Function(Item item)? onFocusItem;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    // Renders nothing when empty, rather than an empty heading — a shelf with no
    // shelf under it looks like a failure.
    if (items.isEmpty) return const SizedBox.shrink();

    final still = shape == CardShape.still;
    final artHeight = still ? metrics.stillHeight : metrics.posterHeight;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(2.6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            // Indented to the first card while the track itself runs full-bleed
            // off the right edge.
            padding: EdgeInsets.only(
              left: metrics.safeX,
              bottom: Metrics.rem(0.9),
            ),
            child: Text(
              title,
              style: Type.heading.copyWith(color: tokens.inkDim),
            ),
          ),
          SizedBox(
            height: _trackHeight(context, artHeight, still),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(
                left: metrics.safeX,
                right: metrics.safeX,
                top: metrics.focusRoom,
                bottom: Metrics.rem(0.75),
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(width: Metrics.rem(1.1)),
              itemBuilder: (context, index) => MediaCard(
                item: items[index],
                client: client,
                group: group,
                shape: shape,
                // This row scrolls on its own, so coming into it from above or
                // below has to start at the beginning. Anywhere else is a
                // position the viewer never chose.
                enter: GroupEntry.first,
                onSelect: () => onSelect(items[index]),
                onFocus: onFocusItem == null
                    ? null
                    : () => onFocusItem!(items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Artwork, the focus room a card reserves above its label, and the label
  /// itself — which is two lines for a poster and three for a still.
  double _trackHeight(BuildContext context, double artHeight, bool still) {
    final metrics = context.metrics;
    final lineHeight = Type.rem(0.92).fontSize! * 1.45;
    final lines = still ? 3 : 2;
    return artHeight +
        metrics.focusRoom * 2 +
        lineHeight * lines +
        Metrics.rem(0.75);
  }
}
