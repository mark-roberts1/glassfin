/// Keeping the television awake while a film plays.
///
/// Ported from `glassfin_old/src/power/PowerComponent.cpp`, which held an
/// `org.freedesktop.ScreenSaver.Inhibit` cookie and wired it to the player with
/// one line — `setScreensaverEnabled(state != "Playing")`. Two things about that
/// are deliberate rather than incidental, and both are kept here:
///
///  * **A paused film lets the screen blank.** Pausing and walking away is the
///    case that matters, and a still frame left on a panel for an hour is a
///    worse outcome than having to nudge the pad on the way back.
///  * **Nothing above this asks for it.** It hung off playback state at the
///    bottom of the old application, so no screen and no menu had to remember to
///    release it. `docs/native-audit.md` §5 says to keep that wiring, and the way
///    to keep it is to make the call idempotent and then make it from the one
///    place that already knows whether a film is running.
library;

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Holds the screensaver off for as long as something wants it off.
class ScreenKeeper {
  ScreenKeeper({Future<void> Function({required bool enable})? inhibit})
    : _inhibit = inhibit ?? WakelockPlus.toggle;

  /// Injectable so the policy above can be tested without a D-Bus session, and
  /// so a platform with no screensaver service is a configuration rather than a
  /// special case.
  final Future<void> Function({required bool enable}) _inhibit;

  bool _on = false;

  /// Whether the screensaver is currently being held off.
  bool get on => _on;

  /// Asks for the screen to stay awake, or stops asking.
  ///
  /// **Idempotent, and that is the whole design.** This is called from every
  /// notification the playback controller makes — several a second while a film
  /// runs — and does nothing at all unless the answer has changed. That is what
  /// lets the wiring be "ask on every state change" rather than a set of paired
  /// calls somebody has to keep balanced.
  void wanted(bool on) {
    if (on == _on) return;
    _on = on;
    _apply(on);
  }

  Future<void> _apply(bool on) async {
    try {
      await _inhibit(enable: on);
    } on Object catch (error) {
      // A machine with no screensaver service to talk to is a normal machine,
      // and a film is not worth failing over a blanking screen. Logged rather
      // than swallowed: a television that dims twenty minutes in is exactly the
      // kind of fault that gets reported as "it crashed".
      debugPrint('power: could not ${on ? 'inhibit' : 'release'} the '
          'screensaver — $error');

      // Left as requested rather than rolled back. If the inhibit failed there
      // is nothing to release, and if the release failed, claiming we still hold
      // it would mean never trying again.
    }
  }
}
