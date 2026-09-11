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

/// How far one nudge of the scroll control moves, as a fraction of the viewport.
///
/// Tuned for **holding** rather than tapping, because that is what a thumbstick
/// is for: the input pipeline repeats a held direction every 60ms, so this works
/// out at a little under one screenful per second, which is about reading pace.
/// A single flick therefore moves only a little.
///
/// The honest limitation: an analogue stick knows how far it has been pushed and
/// this does not, because the input layer turns axes into directions before
/// anything sees them. Velocity-proportional scrolling would need that value
/// carried through, which is a real improvement and a larger change than this.
const double scrollNudge = 0.07;

/// Scrolls the nearest vertically scrolling ancestor of [context].
///
/// **For content, not for controls.** Directional navigation moves between
/// focusable things and scrolls them into view as it goes; this exists for
/// everything that is not focusable and never will be — a film's synopsis, a cast
/// list, the long tail of a detail screen. None of that should be focusable just
/// to be reachable, and leaving it unreachable fails the couch bar just as surely
/// as a dead end does.
///
/// [fraction] is signed: positive scrolls down. Returns whether anything moved,
/// so a caller can let the press mean something else when it did not.
bool scrollVertically(BuildContext context, double fraction) {
  for (final scrollable in _scrollableAncestors(context)) {
    if (axisDirectionToAxis(scrollable.axisDirection) != Axis.vertical) {
      // A card inside a horizontal shelf: keep looking upward for the page.
      continue;
    }

    final position = scrollable.position;
    if (!position.hasPixels || !position.hasContentDimensions) continue;
    // A page that fits on screen is not a page that failed to scroll.
    if (position.maxScrollExtent <= position.minScrollExtent) return false;

    final target = (position.pixels + position.viewportDimension * fraction)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return false;

    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
    } else {
      // Linear, and longer than the 60ms repeat interval on purpose: each nudge
      // replaces the one still running, and an eased curve would decelerate into
      // every replacement and read as juddering rather than scrolling.
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.linear,
      );
    }
    return true;
  }
  return false;
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
