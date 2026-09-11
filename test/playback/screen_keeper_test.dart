/// When the television is allowed to blank.
///
/// Two decisions live in [ScreenKeeper], and both are inherited rather than
/// invented: a **paused** film lets the screensaver come back, and the call is
/// idempotent so that it can be made from every state change without anybody
/// balancing a pair. See `glassfin_old/src/power/PowerComponent.cpp`, which did
/// the whole thing in `setScreensaverEnabled(state != "Playing")`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/playback/screen_keeper.dart';

/// Records what the platform was actually asked to do, which is the only thing
/// worth asserting — the point of this class is that it asks as rarely as
/// possible.
class _Spy {
  final List<bool> calls = [];
  int failures = 0;

  Future<void> call({required bool enable}) async {
    calls.add(enable);
    if (failures > 0) {
      failures--;
      throw StateError('no screensaver service');
    }
  }
}

void main() {
  test('asks for the screen to stay awake, once', () {
    final spy = _Spy();
    final keeper = ScreenKeeper(inhibit: spy.call);

    keeper.wanted(true);
    expect(spy.calls, [true]);
    expect(keeper.on, isTrue);
  });

  test('repeating the same answer asks nothing at all', () {
    // The reason this can be driven from `notifyListeners`, which fires several
    // times a second while a film runs.
    final spy = _Spy();
    final keeper = ScreenKeeper(inhibit: spy.call);

    keeper.wanted(true);
    for (var i = 0; i < 100; i++) {
      keeper.wanted(true);
    }

    expect(spy.calls, [true]);
  });

  test('releases when it is no longer wanted', () {
    final spy = _Spy();
    final keeper = ScreenKeeper(inhibit: spy.call);

    keeper.wanted(true);
    keeper.wanted(false);
    keeper.wanted(false);

    expect(spy.calls, [true, false]);
    expect(keeper.on, isFalse);
  });

  test('a platform that cannot do it is not an error', () async {
    // A machine with no screensaver service is a normal machine, and a film is
    // not worth failing over a blanking screen. The throw must not escape.
    final spy = _Spy()..failures = 1;
    final keeper = ScreenKeeper(inhibit: spy.call);

    keeper.wanted(true);
    await Future<void>.delayed(Duration.zero);

    expect(spy.calls, [true]);
    // Still recorded as asked for, so a later release is still attempted and the
    // state does not drift from what the caller believes.
    expect(keeper.on, isTrue);
    keeper.wanted(false);
    expect(spy.calls, [true, false]);
  });
}
