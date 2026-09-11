/// Physical keyboard → the key strings `assets/inputmaps/keyboard.json` expects.
///
/// **This is the part the Qt build could not do.** Its `EventFilter` returned
/// true for every key press, so a physical keyboard produced no DOM events at
/// all, case was destroyed by the input mapping, and one key could emit several
/// actions at once. An entire text-entry subsystem existed to work around that.
/// Flutter delivers real key events with real case, so none of it is needed.
///
/// What *is* still needed is the naming, because the mapping file is carried over
/// unchanged and it is written in Qt's vocabulary: `Left`, `Esc`, `PgUp`,
/// `Toggle Media Play/Pause`, and modifiers in Qt's order. This file reproduces
/// `keyEventToKeyString` from `glassfin_old/src/ui/EventFilter.cpp` closely
/// enough that the JSON needs no edits.
library;

import 'package:flutter/services.dart';

/// Qt's name for the keys whose names are not simply their label.
///
/// Anything absent falls through to [LogicalKeyboardKey.keyLabel], which already
/// agrees with Qt for letters, digits, symbols and the function keys. Entries
/// here are the ones where it does not — Flutter says "Arrow Left" and
/// "Page Up" where the mapping file says `Left` and `PgUp`.
///
/// Not const: [LogicalKeyboardKey] overrides `==`, which Dart will not accept as
/// a constant map key.
final Map<LogicalKeyboardKey, String> _qtKeyNames = {
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.enter: 'Return',
  // Qt calls the keypad one "Enter" and the main one "Return"; the mapping file
  // accepts either, but the distinction is free to keep.
  LogicalKeyboardKey.numpadEnter: 'Enter',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.pageUp: 'PgUp',
  LogicalKeyboardKey.pageDown: 'PgDown',

  // **Space is a named key, not a printable character.** Its label is a single
  // space, which would otherwise send it down the text branch below and make
  // `"Space": ["space", "play_pause"]` dead — the comment in keyboard.json
  // saying so is describing this exact hazard.
  LogicalKeyboardKey.space: 'Space',

  // Keypad equivalents. Qt masked `KeypadModifier` off as "practically
  // useless", so a keypad digit is indistinguishable from the digit row.
  LogicalKeyboardKey.numpad0: '0',
  LogicalKeyboardKey.numpad1: '1',
  LogicalKeyboardKey.numpad2: '2',
  LogicalKeyboardKey.numpad3: '3',
  LogicalKeyboardKey.numpad4: '4',
  LogicalKeyboardKey.numpad5: '5',
  LogicalKeyboardKey.numpad6: '6',
  LogicalKeyboardKey.numpad7: '7',
  LogicalKeyboardKey.numpad8: '8',
  LogicalKeyboardKey.numpad9: '9',
  LogicalKeyboardKey.numpadDecimal: '.',
  LogicalKeyboardKey.numpadAdd: '+',
  LogicalKeyboardKey.numpadSubtract: '-',
  LogicalKeyboardKey.numpadMultiply: '*',
  LogicalKeyboardKey.numpadDivide: '/',

  // Media keys, as they arrive from a FLIRC, a Harmony, or a Linux keyboard's
  // top row. These names are Qt's and are what the mapping file matches on.
  LogicalKeyboardKey.mediaPlayPause: 'Toggle Media Play/Pause',
  LogicalKeyboardKey.mediaPlay: 'Media Play',
  LogicalKeyboardKey.mediaPause: 'Media Pause',
  LogicalKeyboardKey.mediaStop: 'Media Stop',
  LogicalKeyboardKey.mediaTrackNext: 'Media Next',
  LogicalKeyboardKey.mediaTrackPrevious: 'Media Previous',
  LogicalKeyboardKey.mediaRewind: 'Media Rewind',
  LogicalKeyboardKey.mediaFastForward: 'Media Fast Forward',
  LogicalKeyboardKey.browserBack: 'Back',
};

bool _anyHeld(Set<LogicalKeyboardKey> keys, LogicalKeyboardKey a, LogicalKeyboardKey b) =>
    keys.contains(a) || keys.contains(b);

/// The canonical name for a key press, in the form the input maps use.
///
/// Two rules are doing the work, both inherited:
///
/// 1. **Modifiers in Qt's order — Meta, Ctrl, Alt, Shift.** Not alphabetical and
///    not the order anyone would choose; it is the order `QKeySequence` emitted,
///    so it is the order `"Meta+Ctrl+F"` and `"Ctrl+Alt+Shift+F1"` are written in
///    the file. Any other order simply fails to match.
/// 2. **A plain printable key reports the character it produced**, not the key it
///    sits on. With no Ctrl/Alt/Meta held, `a` is `"a"`, `Shift+a` is `"A"`, and
///    `Shift+1` is `"!"` rather than `"Shift+1"` — which is what lets a password
///    be typed. Shift is deliberately *not* prefixed in that case, because the
///    character already accounts for it.
/// [pressed] defaults to what the hardware says is down, and exists as a
/// parameter so the naming can be tested on a constructed event.
String canonicalKeyName(KeyEvent event, {Set<LogicalKeyboardKey>? pressed}) {
  final held = pressed ?? HardwareKeyboard.instance.logicalKeysPressed;
  final ctrl = _anyHeld(held, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight);
  final alt = _anyHeld(held, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight);
  final shift = _anyHeld(held, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight);
  final meta = _anyHeld(held, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight);

  final name = _qtKeyNames[event.logicalKey] ?? event.logicalKey.keyLabel;

  // Shift is not "significant" here: it changes the character, and the character
  // is what gets reported.
  final character = event.character;
  if (!ctrl &&
      !alt &&
      !meta &&
      name.length == 1 &&
      character != null &&
      character.length == 1 &&
      character.codeUnitAt(0) >= 0x20) {
    return character;
  }

  return [
    if (meta) 'Meta',
    if (ctrl) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    name,
  ].join('+');
}

/// The source name a keyboard press is mapped against.
///
/// Matched by `keyboard.json`'s `"idmatcher": "Keyboard.*"`.
const keyboardSource = 'Keyboard';

/// Not const: [LogicalKeyboardKey] overrides `==`.
final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
};

/// Whether this key is only ever a modifier, and so is not a press in its own
/// right.
///
/// Without this, holding Alt reports itself as `"Alt+Alt Left"` — the modifier
/// counted twice, once as the prefix and once as the key. Nothing maps that, so
/// it was harmless, but it filled the log with a string that looks like a naming
/// bug and buried the diagnostics that are not.
bool isModifierKey(LogicalKeyboardKey key) => _modifierKeys.contains(key);
