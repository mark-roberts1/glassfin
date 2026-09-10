import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/format.dart';

void main() {
  group('endsAt', () {
    // A fixed "now" so the test does not depend on the clock it runs under.
    final evening = DateTime(2026, 9, 9, 21, 58);

    test('adds the remaining time to the wall clock', () {
      expect(
        endsAt(const Duration(hours: 1, minutes: 13), now: evening),
        'Ends at 11:11 PM',
      );
    });

    test('rolls past midnight into the small hours', () {
      expect(
        endsAt(const Duration(hours: 3), now: evening),
        'Ends at 12:58 AM',
      );
    });

    test('midnight and noon both read as 12, not 0', () {
      expect(
        endsAt(Duration.zero, now: DateTime(2026, 9, 9, 0, 5)),
        'Ends at 12:05 AM',
      );
      expect(
        endsAt(Duration.zero, now: DateTime(2026, 9, 9, 12, 5)),
        'Ends at 12:05 PM',
      );
    });

    test('pads the minutes', () {
      expect(
        endsAt(const Duration(minutes: 4), now: DateTime(2026, 9, 9, 20, 1)),
        'Ends at 8:05 PM',
      );
    });
  });
}
