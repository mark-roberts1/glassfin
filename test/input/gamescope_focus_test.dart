/// gamescope's focus properties, read the way the BC-250 reported them.
///
/// Recorded in Game Mode: `GAMESCOPE_FOCUSED_APP` flipped between Glassfin's
/// shortcut id (3158376258) and Steam's (769) at every open and close of Steam's
/// menu, while `GAMESCOPE_FOCUSED_APP_GFX` stayed Glassfin's.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/input/gamescope_focus.dart';

const _glassfin = 3158376258;

void main() {
  test('Glassfin has input while gamescope says so', () {
    final reading = GamescopeFocusReading();
    expect(reading.update(focusedApp: _glassfin, baseApp: _glassfin), isTrue);
    expect(reading.ownApp, _glassfin);
  });

  test(
    "Steam's menu has input when the focused app is Steam over Glassfin",
    () {
      final reading = GamescopeFocusReading()
        ..update(focusedApp: _glassfin, baseApp: _glassfin);
      expect(
        reading.update(focusedApp: steamAppId, baseApp: _glassfin),
        isFalse,
      );
      expect(reading.update(focusedApp: _glassfin, baseApp: _glassfin), isTrue);
    },
  );

  test("never learns Steam's id as Glassfin's", () {
    // At launch Steam may still be on screen before Glassfin's window is up.
    // Learning 769 there would mute the pad everywhere except Steam's menu.
    final reading = GamescopeFocusReading();
    expect(reading.update(focusedApp: steamAppId, baseApp: steamAppId), isNull);
    expect(reading.ownApp, isNull);

    expect(reading.update(focusedApp: _glassfin, baseApp: _glassfin), isTrue);
    expect(reading.update(focusedApp: steamAppId, baseApp: _glassfin), isFalse);
  });

  test('has no opinion when nothing has input', () {
    final reading = GamescopeFocusReading()
      ..update(focusedApp: _glassfin, baseApp: _glassfin);
    expect(reading.update(focusedApp: 0, baseApp: _glassfin), isNull);
  });

  test('keeps the id it learned when another app is on screen', () {
    // Back in Steam's library with Glassfin still running: the pad is Steam's.
    final reading = GamescopeFocusReading()
      ..update(focusedApp: _glassfin, baseApp: _glassfin);
    expect(
      reading.update(focusedApp: steamAppId, baseApp: steamAppId),
      isFalse,
    );
    expect(reading.ownApp, _glassfin);
  });
}
