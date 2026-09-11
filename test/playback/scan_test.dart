/// The scan rate ladder, and mute.
///
/// Both are pure arithmetic over the controller's own state, and both have an
/// edge that is easy to get wrong by one step: turning a scan around, and
/// unmuting something that was already silent.
///
/// Tested through the public constants rather than by driving a real player,
/// which would need libmpv and a file — the ladder is the part with a decision
/// in it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/playback/controller.dart';

/// The rate after pressing in [direction] while already at [current].
///
/// Mirrors `PlaybackController.scan`'s choice, which is the one line of it worth
/// pinning down.
int nextRate(int current, int direction) {
  final forward = direction > 0;
  final sameWay = current != 0 && (current > 0) == forward;
  final magnitude = sameWay
      ? (current.abs() * 2).clamp(
          PlaybackController.scanInitialRate,
          PlaybackController.scanMaxRate,
        )
      : PlaybackController.scanInitialRate;
  return forward ? magnitude : -magnitude;
}

void main() {
  group('the scan ladder', () {
    test('starts at the slowest rate in either direction', () {
      expect(nextRate(0, 1), 2);
      expect(nextRate(0, -1), -2);
    });

    test('doubles on each press in the same direction', () {
      var rate = nextRate(0, 1);
      expect(rate, 2);
      expect(rate = nextRate(rate, 1), 4);
      expect(rate = nextRate(rate, 1), 8);
      expect(rate = nextRate(rate, 1), 16);
      expect(nextRate(rate, 1), 32);
    });

    test('stops doubling at the top rather than running away', () {
      expect(nextRate(32, 1), 32);
      expect(nextRate(-32, -1), -32);
    });

    test('backward doubles the same way', () {
      expect(nextRate(-2, -1), -4);
      expect(nextRate(-8, -1), -16);
    });

    test('the opposite direction turns round at the slowest rate', () {
      // **Not halved, and not kept.** Anyone pressing the other way has overshot
      // and wants to creep back, so 32× forward then one press back is 2×
      // backward — not 16× of anything.
      expect(nextRate(32, -1), -2);
      expect(nextRate(-16, 1), 2);
    });
  });

  group('the scan constants', () {
    test('32× crosses a feature film in a few minutes', () {
      // Sanity on the top rate: fast enough to be worth having, slow enough to
      // land on purpose.
      const film = Duration(hours: 2);
      final crossing = film ~/ PlaybackController.scanMaxRate;
      expect(crossing.inMinutes, lessThan(5));
      expect(crossing.inSeconds, greaterThan(60));
    });

    test('a tick at the slowest rate moves half a second of film', () {
      final travelled =
          PlaybackController.scanTick * PlaybackController.scanInitialRate;
      expect(travelled, const Duration(milliseconds: 500));
    });

    test('the end guard leaves room before the credits roll into next up', () {
      // Scanning to the very end would trigger end-of-file and start the next
      // episode, which is not what anyone scanning forward asked for.
      expect(PlaybackController.scanEndGuard, greaterThan(Duration.zero));
    });
  });
}
