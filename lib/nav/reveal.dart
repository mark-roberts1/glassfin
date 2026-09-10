import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// Room for the focus ring, which is drawn *outside* the box it belongs to. A
/// target flush against the edge of its scroller has a visibly clipped ring.
const double revealMargin = 4;

/// The scroll offset that would reveal a target, or `null` to leave the axis
/// alone.
///
/// The rule, from `docs/ui-spec.md` §2.4: **centre an axis only when the target
/// is not already comfortably visible.** Both simpler rules are wrong in a way
/// that shows up immediately on a television:
///
///  * scrolling to `nearest` parks the newly focused row flush against the edge
///    it came in from, which is exactly where things get clipped;
///  * centring unconditionally scrolls a film's title off the screen in order to
///    centre the Play button, and slams a fully visible carousel sideways for
///    every card a mouse happens to cross.
double? revealOffset({
  required double currentOffset,
  required double viewportExtent,
  required double targetStart,
  required double targetExtent,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  final visibleStart = currentOffset + revealMargin;
  final visibleEnd = currentOffset + viewportExtent - revealMargin;

  final alreadyVisible =
      targetStart >= visibleStart && targetStart + targetExtent <= visibleEnd;
  if (alreadyVisible) return null;

  final centred = targetStart + targetExtent / 2 - viewportExtent / 2;
  final clamped = centred.clamp(minScrollExtent, maxScrollExtent);
  return clamped == currentOffset ? null : clamped;
}

/// Scrolls every scrollable ancestor of [context] so that its box is revealed,
/// applying [revealOffset] per axis.
///
/// [context] should be the box the *viewer* is choosing, which is not always the
/// focusable one. A card's title and runtime are siblings of its artwork, so
/// revealing only the artwork leaves the metadata under the fold — anything
/// where the focusable is smaller than the thing being chosen should pass its
/// outer box here.
///
/// Reveal is driven by directional moves only. Hover and click deliberately do
/// **not** call it: a trackpad already scrolls at the viewer's own pace, and
/// auto-centring under a stationary cursor reads as the row dodging the pointer.
void reveal(BuildContext context, {bool animate = true}) {
  final target = context.findRenderObject();
  if (target is! RenderBox || !target.attached || !target.hasSize) return;

  final animations = !MediaQuery.disableAnimationsOf(context);

  for (final scrollable in _scrollableAncestors(context)) {
    final position = scrollable.position;
    if (!position.hasPixels || !position.hasContentDimensions) continue;

    final viewport = scrollable.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) continue;

    final horizontal =
        axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal;

    // Where the target sits in the scrollable's *content*, derived from the two
    // global positions plus how far the scroller has already travelled. This is
    // simpler than asking the viewport to compute a reveal offset, and it makes
    // the "already visible?" test below obvious.
    final targetGlobal = target.localToGlobal(Offset.zero);
    final viewportGlobal = viewport.localToGlobal(Offset.zero);
    final delta = horizontal
        ? targetGlobal.dx - viewportGlobal.dx
        : targetGlobal.dy - viewportGlobal.dy;

    final offset = revealOffset(
      currentOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      targetStart: position.pixels + delta,
      targetExtent: horizontal ? target.size.width : target.size.height,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    if (offset == null) continue;

    if (animate && animations) {
      position.animateTo(offset, duration: Motion.fast, curve: Motion.ease);
    } else {
      position.jumpTo(offset);
    }
  }
}

/// Every [ScrollableState] above [context], innermost first.
///
/// A card inside a horizontal shelf inside a vertically scrolling page has two,
/// on different axes, and both need moving.
Iterable<ScrollableState> _scrollableAncestors(BuildContext context) sync* {
  var current = context;
  while (true) {
    final scrollable = current.findAncestorStateOfType<ScrollableState>();
    if (scrollable == null) return;
    yield scrollable;
    current = scrollable.context;
  }
}
