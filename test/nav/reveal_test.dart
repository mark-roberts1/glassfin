import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/nav/reveal.dart';

/// A 1000px viewport over 5000px of content.
double? offsetFor({
  required double currentOffset,
  required double targetStart,
  double targetExtent = 300,
}) => revealOffset(
  currentOffset: currentOffset,
  viewportExtent: 1000,
  targetStart: targetStart,
  targetExtent: targetExtent,
  minScrollExtent: 0,
  maxScrollExtent: 4000,
);

void main() {
  group('leaves a comfortably visible target alone', () {
    test('when it sits in the middle of the viewport', () {
      // Centring here would scroll a film's title away in order to centre the
      // Play button, which is the specific behaviour the margin rule prevents.
      expect(offsetFor(currentOffset: 0, targetStart: 300), isNull);
    });

    test('when it is inside the viewport by exactly the margin', () {
      expect(
        offsetFor(currentOffset: 0, targetStart: revealMargin),
        isNull,
      );
      expect(
        offsetFor(
          currentOffset: 0,
          targetStart: 1000 - revealMargin - 300,
        ),
        isNull,
      );
    });
  });

  group('centres a target that is not comfortably visible', () {
    test('when it is off the trailing edge', () {
      // Target 1200..1500 in a 0..1000 viewport → centre on 1350.
      expect(offsetFor(currentOffset: 0, targetStart: 1200), 850);
    });

    test('when it is off the leading edge', () {
      expect(offsetFor(currentOffset: 2000, targetStart: 1500), 1150);
    });

    test('when it is only just clipped', () {
      // Flush against the edge with no room for the ring. `nearest` scrolling
      // parks a row exactly here, and the ring is drawn outside the box, so the
      // half of the highlight that reads from a sofa gets sliced off.
      final justInside = 1000 - 300 - revealMargin + 1;
      expect(offsetFor(currentOffset: 0, targetStart: justInside), isNotNull);
    });
  });

  group('clamps to the scroll extent', () {
    test('never scrolls above the start', () {
      // The first card of a shelf cannot be centred; asking for it would leave
      // a gap where the row's leading padding should be.
      expect(offsetFor(currentOffset: 500, targetStart: 0), 0);
    });

    test('never scrolls past the end', () {
      expect(offsetFor(currentOffset: 0, targetStart: 4900), 4000);
    });

    test('reports no move when the clamped result is where we already are', () {
      // Already pinned to the end, focusing the very last card: clamping would
      // otherwise produce a redundant animation to the current position.
      expect(offsetFor(currentOffset: 4000, targetStart: 4900), isNull);
    });
  });

  test('a target taller than the viewport is centred on itself', () {
    // A detail screen's hero. Centring is the least-bad answer; the rule must
    // at least be defined rather than producing a NaN or an unclamped offset.
    final offset = offsetFor(
      currentOffset: 0,
      targetStart: 0,
      targetExtent: 2000,
    );
    expect(offset, 500);
  });
}
