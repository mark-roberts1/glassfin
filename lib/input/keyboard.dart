/// Physical keyboard → [InputAction].
///
/// **This is the part the Qt build could not do.** Its `EventFilter` returned
/// true for every key press, so a physical keyboard produced no DOM events at
/// all, case was destroyed by the input mapping, and one key could emit several
/// actions at once. An entire text-entry subsystem existed to work around that.
/// Flutter delivers real key events with real case, so none of it is needed.
///
/// Phase 6 replaces the table below with the mapping engine reading
/// `assets/inputmaps/keyboard.json`, generating the same canonical strings
/// (`"Ctrl+Shift+F"`) that file already expects. This is the walking skeleton's
/// stand-in.
library;

import 'package:flutter/services.dart';

import 'actions.dart';

/// The canonical name for a key press, in the form the input maps use.
///
/// Modifiers in a fixed order so that the string is stable — a map keyed on
/// "Shift+Ctrl+F" and one keyed on "Ctrl+Shift+F" would otherwise be different
/// maps.
String canonicalKeyName(KeyEvent event) {
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  bool held(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
      keys.contains(a) || keys.contains(b);

  final parts = <String>[
    if (held(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight))
      'Ctrl',
    if (held(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight)) 'Alt',
    if (held(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight))
      'Shift',
    if (held(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight)) 'Meta',
    event.logicalKey.keyLabel,
  ];
  return parts.join('+');
}

// Not const: LogicalKeyboardKey overrides ==, which Dart will not allow as a
// constant map key.
final Map<LogicalKeyboardKey, InputAction> _defaultBindings = {
  LogicalKeyboardKey.arrowUp: InputAction.up,
  LogicalKeyboardKey.arrowDown: InputAction.down,
  LogicalKeyboardKey.arrowLeft: InputAction.left,
  LogicalKeyboardKey.arrowRight: InputAction.right,
  LogicalKeyboardKey.enter: InputAction.select,
  LogicalKeyboardKey.numpadEnter: InputAction.select,
  LogicalKeyboardKey.escape: InputAction.back,
  LogicalKeyboardKey.backspace: InputAction.back,
  LogicalKeyboardKey.space: InputAction.playPause,
  LogicalKeyboardKey.home: InputAction.home,
  LogicalKeyboardKey.keyS: InputAction.search,
  LogicalKeyboardKey.mediaPlayPause: InputAction.playPause,
  LogicalKeyboardKey.mediaStop: InputAction.stop,
  LogicalKeyboardKey.mediaTrackNext: InputAction.seekForward,
  LogicalKeyboardKey.mediaTrackPrevious: InputAction.seekBackward,
};

InputAction? actionForKey(KeyEvent event) => _defaultBindings[event.logicalKey];
