/// Keeps a controller from operating Glassfin while another window has focus.
///
/// The pad is read through SDL with background events allowed (see
/// `Gamepads.start`), so it keeps reporting when Steam's menu opens over
/// Glassfin in Game Mode. Without this, every button pressed in Steam's menu
/// also reached Glassfin: the PS button sent it Home, and the X that confirmed
/// "Exit game" selected the first Continue Watching card, so an episode started
/// playing as the app closed. Confirmed on the BC-250 with input logging.
///
/// Pure, so the rules can be tested without SDL or a window. The keyboard never
/// comes through here — a compositor only sends keys to the focused window.
library;

import 'pipeline.dart';

class FocusGate {
  bool _focused = true;

  /// Whether the window has ever been reported focused.
  ///
  /// **No muting until it has.** A session that never reports focus at all
  /// would otherwise start Glassfin "unfocused" and leave the pad dead from
  /// launch — on a television, indistinguishable from a broken controller. That
  /// is a far worse failure than the leak this class exists to stop.
  bool _seenFocus = false;

  /// Keys currently held, tracked whether or not they are admitted, so that a
  /// press which straddles a focus change can be recognised afterwards.
  final Set<(String, String)> _down = {};

  /// Keys that were held when focus came back. Ignored until released: the
  /// press began in another window and was never meant for this one.
  final Set<(String, String)> _awaitingRelease = {};

  /// Whether pad input is currently admitted.
  bool get focused => _focused;

  /// Records a focus report from the window. Returns true when the gate
  /// actually changed state, which is when anything held needs dropping.
  bool setFocused(bool focused) {
    if (focused) _seenFocus = true;
    final effective = focused || !_seenFocus;
    if (effective == _focused) return false;

    _focused = effective;
    _awaitingRelease.clear();
    if (effective) _awaitingRelease.addAll(_down);
    return true;
  }

  /// Whether a key event from a non-keyboard source should reach the pipeline.
  bool admit(String source, String keycode, KeyState state) {
    final key = (source, keycode);
    switch (state) {
      case KeyState.down:
        _down.add(key);
      case KeyState.up:
        _down.remove(key);
      case KeyState.pressed:
        break;
    }

    if (!_focused) return false;

    if (_awaitingRelease.contains(key)) {
      if (state == KeyState.up) _awaitingRelease.remove(key);
      return false;
    }
    return true;
  }
}
