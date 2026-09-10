import 'dart:ui';

import 'package:flutter/widgets.dart' show TraversalDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/nav/scoring.dart';

/// A poster-shaped card at a grid position, roughly to the app's real scale.
Rect card(double x, double y) => Rect.fromLTWH(x, y, 300, 450);

void main() {
  // One shelf of three cards, and a second shelf 500px below it.
  final shelfA = [card(0, 100), card(320, 100), card(640, 100)];
  final shelfB = [card(0, 600), card(320, 600), card(640, 600)];

  group('horizontal moves stay on their own row', () {
    test('rejects a candidate with no vertical overlap', () {
      // Directly below and to the right — geometrically a plausible "right",
      // and exactly the move that must not happen. Falling off the end of a
      // shelf into the one below looks like the interface losing your place.
      expect(
        scoreCandidate(shelfA[0], shelfB[1], TraversalDirection.right),
        isNull,
      );
    });

    test('accepts a candidate on the same row', () {
      expect(
        scoreCandidate(shelfA[0], shelfA[1], TraversalDirection.right),
        isNotNull,
      );
    });

    test('a partially overlapping row is still reachable', () {
      // Ragged heights are normal — a still card next to a poster. Any overlap
      // at all counts.
      final shorter = Rect.fromLTWH(320, 400, 300, 200);
      expect(
        scoreCandidate(shelfA[0], shorter, TraversalDirection.right),
        isNotNull,
      );
    });

    test('picks the nearer of two cards to the right', () {
      expect(
        bestCandidate(shelfA[0], [
          shelfA[2],
          shelfA[1],
        ], TraversalDirection.right),
        1, // shelfA[1], the nearer one, despite being listed second
      );
    });

    test('will not move right from the last card in a row', () {
      // Everything else on screen, minus the origin itself.
      final others = [shelfA[0], shelfA[1], ...shelfB];
      expect(
        bestCandidate(shelfA[2], others, TraversalDirection.right),
        isNull,
      );
    });
  });

  group('vertical moves', () {
    test('prefer the aligned column', () {
      final winner = bestCandidate(shelfA[1], shelfB, TraversalDirection.down);
      expect(winner, 1);
    });

    test('reach a non-overlapping candidate, but only past the barrier', () {
      final aligned = scoreCandidate(
        shelfA[0],
        shelfB[0],
        TraversalDirection.down,
      )!;
      final offset = scoreCandidate(
        shelfA[0],
        shelfB[2],
        TraversalDirection.down,
      )!;

      expect(offset, greaterThan(aligned + unalignedPenalty));
      // Unlike a horizontal move, it is still legal: a lone button under an
      // empty stretch of a grid must be reachable from above.
      expect(offset.isFinite, isTrue);
    });

    test('travel dominates gentle misalignment', () {
      // A slightly misaligned card on the nearer row beats a perfectly aligned
      // one further away.
      final near = card(60, 600);
      final far = card(0, 1200);
      expect(bestCandidate(shelfA[0], [far, near], TraversalDirection.down), 1);
    });
  });

  group('direction of travel', () {
    test('rejects anything behind the origin', () {
      expect(
        scoreCandidate(shelfA[1], shelfA[0], TraversalDirection.right),
        isNull,
      );
      expect(
        scoreCandidate(shelfB[0], shelfA[0], TraversalDirection.down),
        isNull,
      );
    });

    test('forgives a sub-pixel backwards step', () {
      // Fractional layout puts a neighbour 0.5px "behind" its own row. Without
      // the tolerance this is a dead end that only appears at some window sizes.
      final ragged = Rect.fromLTWH(319.5, 99.5, 300, 450);
      expect(
        scoreCandidate(
          ragged,
          shelfA[0].shift(const Offset(640, 0)),
          TraversalDirection.right,
        ),
        isNotNull,
      );
      // Travel is measured between the facing edges, so "behind" means the
      // candidate's left edge sits inside the origin's right edge.
      final barelyBehind = Rect.fromLTWH(299.5, 100, 300, 450);
      expect(
        scoreCandidate(shelfA[0], barelyBehind, TraversalDirection.right),
        isNotNull,
      );
    });

    test('rejects a step further back than the tolerance', () {
      final behind = Rect.fromLTWH(297, 100, 300, 450);
      expect(
        scoreCandidate(shelfA[0], behind, TraversalDirection.right),
        isNull,
      );
    });
  });

  group('travel is measured between the facing edges', () {
    // The bug this guards against shipped once. Measuring leading edge to
    // leading edge gives a same-row neighbour a travel of *zero* on a vertical
    // move — legal, and cheaper than anything genuinely above — so Up walked
    // sideways along the shelf and the header was unreachable.
    test('a same-row neighbour is not a legal destination for up or down', () {
      expect(
        scoreCandidate(shelfA[0], shelfA[1], TraversalDirection.up),
        isNull,
      );
      expect(
        scoreCandidate(shelfA[1], shelfA[0], TraversalDirection.up),
        isNull,
      );
      expect(
        scoreCandidate(shelfA[0], shelfA[1], TraversalDirection.down),
        isNull,
      );
    });

    test('a distant header still beats a same-row neighbour', () {
      // Home's chrome pills: far to the right, well above, sharing no column
      // with the first card. They are the only thing up there, and Up must
      // reach them.
      final pill = Rect.fromLTWH(1000, 20, 120, 40);
      final candidates = [shelfA[1], shelfA[2], pill];
      expect(
        bestCandidate(shelfA[0], candidates, TraversalDirection.up),
        2,
      );
    });

    test('the gap between boxes is the distance, not their offset', () {
      // Two candidates whose left edges are equally far away, but one is much
      // wider and therefore starts closer. The nearer *edge* should win.
      final wide = Rect.fromLTWH(320, 100, 600, 450);
      final near = Rect.fromLTWH(310, 100, 100, 450);
      expect(
        travelDistance(shelfA[0], near, TraversalDirection.right),
        lessThan(travelDistance(shelfA[0], wide, TraversalDirection.right)),
      );
    });
  });

  group('ties', () {
    test('break towards the earlier candidate', () {
      // Two identical destinations: registration order decides, not hash order,
      // so navigation is reproducible.
      final a = card(0, 600);
      final b = card(0, 600);
      expect(bestCandidate(shelfA[0], [a, b], TraversalDirection.down), 0);
    });
  });

  test('no legal candidates yields null rather than a bad move', () {
    expect(bestCandidate(shelfA[0], const [], TraversalDirection.down), isNull);
  });
}
