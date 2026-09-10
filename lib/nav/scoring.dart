/// The directional scoring from `docs/ui-spec.md` §2.2.
///
/// Pure arithmetic on rectangles, deliberately separated from the widget layer
/// so it can be unit-tested directly. Flutter's own directional traversal is not
/// good enough for a ten-foot interface — it happily walks off the end of a
/// carousel into whatever happens to be below it.
library;

import 'dart:ui';

import 'package:flutter/widgets.dart' show TraversalDirection;

/// Forgives sub-pixel layout and lets same-row items with ragged heights still
/// qualify for a horizontal move. Without it, two cards whose facing edges are a
/// hundredth of a pixel apart the wrong way are not reachable from each other.
const double travelTolerance = -1;

/// Cross-axis misalignment is a gentle tiebreaker when the boxes overlap…
const double alignedMisalignmentWeight = 0.2;

/// …and a near-veto when they do not.
const double unalignedMisalignmentWeight = 4;

/// The barrier a non-overlapping candidate must clear. Large enough that any
/// overlapping candidate, however badly aligned, wins first.
const double unalignedPenalty = 1000;

bool _isHorizontal(TraversalDirection direction) =>
    direction == TraversalDirection.left ||
    direction == TraversalDirection.right;

/// Distance from [from] to [to] along the direction of travel.
///
/// **Measured between the two facing edges** — for a move up, from the origin's
/// top to the candidate's bottom — so it is the gap between the boxes rather
/// than the offset between their leading corners.
///
/// This is not a detail. Leading-edge to leading-edge gives a same-row
/// neighbour a travel of *zero* on a vertical move, which clears the tolerance
/// and makes it a legal destination; it then beats anything genuinely above,
/// and pressing Up walks sideways along the row instead of leaving it. Facing
/// edges give that neighbour a large negative travel, so it is rejected outright
/// and the only candidates left are the ones actually in that direction.
double travelDistance(Rect from, Rect to, TraversalDirection direction) {
  final fromNear = switch (direction) {
    TraversalDirection.right => from.right,
    TraversalDirection.left => from.left,
    TraversalDirection.down => from.bottom,
    TraversalDirection.up => from.top,
  };
  final toNear = switch (direction) {
    TraversalDirection.right => to.left,
    TraversalDirection.left => to.right,
    TraversalDirection.down => to.top,
    TraversalDirection.up => to.bottom,
  };
  return direction == TraversalDirection.right ||
          direction == TraversalDirection.down
      ? toNear - fromNear
      : fromNear - toNear;
}

/// How much the two boxes share on the axis perpendicular to travel.
double crossAxisOverlap(Rect a, Rect b, TraversalDirection direction) {
  if (_isHorizontal(direction)) {
    return (a.bottom < b.bottom ? a.bottom : b.bottom) -
        (a.top > b.top ? a.top : b.top);
  }
  return (a.right < b.right ? a.right : b.right) -
      (a.left > b.left ? a.left : b.left);
}

/// Distance between the two boxes' centres on the cross axis.
double crossAxisMisalignment(Rect a, Rect b, TraversalDirection direction) {
  final delta = _isHorizontal(direction)
      ? a.center.dy - b.center.dy
      : a.center.dx - b.center.dx;
  return delta.abs();
}

/// Scores [candidate] as a destination for a move from [origin].
///
/// Lower is better. Returns `null` when the candidate is not a legal
/// destination at all, for one of two reasons:
///
///  * it lies behind the origin in the direction of travel; or
///  * **the move is horizontal and the boxes do not overlap vertically.** This
///    is the "left and right stay on the line you started on" rule. Without it,
///    pressing right at the end of a shelf drops into the shelf below, which
///    from three metres looks like the interface losing your place.
double? scoreCandidate(
  Rect origin,
  Rect candidate,
  TraversalDirection direction,
) {
  final travel = travelDistance(origin, candidate, direction);
  if (travel < travelTolerance) return null;

  final overlap = crossAxisOverlap(origin, candidate, direction);
  if (_isHorizontal(direction) && overlap <= 0) return null;

  final misalignment = crossAxisMisalignment(origin, candidate, direction);
  return overlap > 0
      ? travel + misalignment * alignedMisalignmentWeight
      : travel + misalignment * unalignedMisalignmentWeight + unalignedPenalty;
}

/// The index of the best candidate in [candidates], or `null` if none is legal.
///
/// Ties break towards the earlier entry, so registration order decides between
/// two equally good destinations rather than hash order.
///
/// [candidates] must **not** contain [origin] itself: a zero-travel, fully
/// overlapping box scores 0 and wins every move, which reads as navigation
/// having stopped responding.
int? bestCandidate(
  Rect origin,
  List<Rect> candidates,
  TraversalDirection direction,
) {
  int? winner;
  double? best;
  for (var i = 0; i < candidates.length; i++) {
    final score = scoreCandidate(origin, candidates[i], direction);
    if (score == null) continue;
    if (best == null || score < best) {
      best = score;
      winner = i;
    }
  }
  return winner;
}
