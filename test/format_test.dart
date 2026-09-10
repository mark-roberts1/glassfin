import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/format.dart';

void main() {
  group('clock', () {
    test('omits the hours field below an hour', () {
      // A forty-minute episode reading "0:40:12" looks like a fault at three
      // metres, which is the whole reason this is not one format string.
      expect(clock(const Duration(minutes: 40, seconds: 12)), '40:12');
      expect(clock(const Duration(seconds: 7)), '0:07');
      expect(clock(Duration.zero), '0:00');
    });

    test('adds the hours field above an hour, and pads the minutes', () {
      expect(clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(clock(const Duration(hours: 2, minutes: 30)), '2:30:00');
    });

    test('does not roll over at exactly an hour', () {
      expect(clock(const Duration(minutes: 59, seconds: 59)), '59:59');
      expect(clock(const Duration(hours: 1)), '1:00:00');
    });

    test('clamps a negative duration rather than printing a minus', () {
      // The transport builds "remaining" by subtraction, and a position that
      // has run a frame past the reported duration must not print "-0:-1".
      expect(clock(const Duration(seconds: -5)), '0:00');
    });

    test('handles a duration longer than a day without wrapping', () {
      expect(clock(const Duration(hours: 25, minutes: 1)), '25:01:00');
    });
  });

  group('runtimeLabel', () {
    test('rounds to whole minutes', () {
      expect(runtimeLabel(const Duration(minutes: 92, seconds: 20)), '92 min');
      expect(runtimeLabel(const Duration(minutes: 92, seconds: 40)), '93 min');
    });

    test('is empty when the runtime is unknown or zero', () {
      expect(runtimeLabel(null), '');
      expect(runtimeLabel(Duration.zero), '');
    });
  });
}
