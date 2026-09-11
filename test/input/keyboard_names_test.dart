/// The canonical key strings, checked against what `keyboard.json` expects.
///
/// This is the contract that lets the mapping file be carried over unchanged, and
/// it is all in the names: the file is written in Qt's vocabulary, so `Left` and
/// not `Arrow Left`, `Esc` and not `Escape`, `PgUp` and not `Page Up`, and
/// modifiers in Qt's order rather than any sensible one. A name that does not
/// match is a shortcut that silently stops working.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/input/keyboard.dart';

/// A key press, with whatever the engine would have resolved as its character.
String name(
  LogicalKeyboardKey key, {
  String? character,
  Set<LogicalKeyboardKey> held = const {},
}) => canonicalKeyName(
  KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.space,
    logicalKey: key,
    timeStamp: Duration.zero,
    character: character,
  ),
  pressed: held,
);

void main() {
  group('named keys use Qt spellings', () {
    test('arrows', () {
      expect(name(LogicalKeyboardKey.arrowLeft), 'Left');
      expect(name(LogicalKeyboardKey.arrowRight), 'Right');
      expect(name(LogicalKeyboardKey.arrowUp), 'Up');
      expect(name(LogicalKeyboardKey.arrowDown), 'Down');
    });

    test('enter, escape and the page keys', () {
      expect(name(LogicalKeyboardKey.enter, character: '\n'), 'Return');
      expect(name(LogicalKeyboardKey.numpadEnter, character: '\n'), 'Enter');
      expect(name(LogicalKeyboardKey.escape), 'Esc');
      expect(name(LogicalKeyboardKey.pageUp), 'PgUp');
      expect(name(LogicalKeyboardKey.pageDown), 'PgDown');
      expect(name(LogicalKeyboardKey.backspace), 'Backspace');
      expect(name(LogicalKeyboardKey.home), 'Home');
      expect(name(LogicalKeyboardKey.end), 'End');
      expect(name(LogicalKeyboardKey.f11), 'F11');
    });

    test('space is a named key, not a printable character', () {
      // If this returned " " then `"Space": ["space", "play_pause"]` would never
      // match and the spacebar would stop pausing the film — the one keyboard
      // shortcut everybody tries first.
      expect(name(LogicalKeyboardKey.space, character: ' '), 'Space');
    });

    test('media keys', () {
      expect(
        name(LogicalKeyboardKey.mediaPlayPause),
        'Toggle Media Play/Pause',
      );
      expect(name(LogicalKeyboardKey.mediaPlay), 'Media Play');
      expect(name(LogicalKeyboardKey.mediaPause), 'Media Pause');
      expect(name(LogicalKeyboardKey.mediaStop), 'Media Stop');
      expect(name(LogicalKeyboardKey.mediaTrackNext), 'Media Next');
      expect(name(LogicalKeyboardKey.mediaTrackPrevious), 'Media Previous');
      expect(name(LogicalKeyboardKey.mediaRewind), 'Media Rewind');
      expect(name(LogicalKeyboardKey.mediaFastForward), 'Media Fast Forward');
      expect(name(LogicalKeyboardKey.browserBack), 'Back');
    });
  });

  group('printable keys report the character they produced', () {
    test('case survives, which is the whole point of the rebuild', () {
      expect(name(LogicalKeyboardKey.keyA, character: 'a'), 'a');
      expect(
        name(
          LogicalKeyboardKey.keyA,
          character: 'A',
          held: {LogicalKeyboardKey.shiftLeft},
        ),
        'A',
      );
    });

    test('a shifted digit is its symbol, not Shift plus the digit', () {
      // `Shift+1` is `!`. Without this a password containing one cannot be typed.
      expect(name(LogicalKeyboardKey.digit1, character: '1'), '1');
      expect(
        name(
          LogicalKeyboardKey.digit1,
          character: '!',
          held: {LogicalKeyboardKey.shiftLeft},
        ),
        '!',
      );
    });

    test('symbols', () {
      expect(name(LogicalKeyboardKey.equal, character: '='), '=');
      expect(
        name(
          LogicalKeyboardKey.equal,
          character: '+',
          held: {LogicalKeyboardKey.shiftLeft},
        ),
        '+',
      );
      expect(name(LogicalKeyboardKey.minus, character: '-'), '-');
      expect(name(LogicalKeyboardKey.backslash, character: r'\'), r'\');
    });

    test('a keypad digit is the plain digit', () {
      // Qt masked the keypad modifier off as "practically useless".
      expect(name(LogicalKeyboardKey.numpad5, character: '5'), '5');
    });

    test('a key with no character falls back to its label', () {
      expect(name(LogicalKeyboardKey.keyA), 'A');
    });
  });

  group('modifiers', () {
    test('are ordered Meta, Ctrl, Alt, Shift — Qt\'s order, not alphabetical', () {
      // Every one of these strings appears verbatim in keyboard.json. Any other
      // ordering produces a name that matches nothing.
      expect(
        name(
          LogicalKeyboardKey.keyF,
          character: 'f',
          held: {LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft},
        ),
        'Ctrl+Shift+F',
      );
      expect(
        name(
          LogicalKeyboardKey.keyF,
          character: 'f',
          held: {LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.controlLeft},
        ),
        'Meta+Ctrl+F',
      );
      expect(
        name(
          LogicalKeyboardKey.f1,
          held: {
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.altLeft,
            LogicalKeyboardKey.shiftLeft,
          },
        ),
        'Ctrl+Alt+Shift+F1',
      );
      expect(
        name(
          LogicalKeyboardKey.keyA,
          character: 'a',
          held: {LogicalKeyboardKey.altLeft, LogicalKeyboardKey.shiftLeft},
        ),
        'Alt+Shift+A',
      );
    });

    test('a letter in a shortcut is uppercase regardless of what was typed', () {
      // The name comes from the key, not the text, once a significant modifier is
      // held — `Ctrl+A` should fire whether or not Shift happens to be down.
      expect(
        name(
          LogicalKeyboardKey.keyA,
          character: 'a',
          held: {LogicalKeyboardKey.controlLeft},
        ),
        'Ctrl+A',
      );
    });

    test('Shift with a named key is kept', () {
      // `"(Shift\\+)?Left"` in the file expects exactly this.
      expect(
        name(
          LogicalKeyboardKey.arrowLeft,
          held: {LogicalKeyboardKey.shiftLeft},
        ),
        'Shift+Left',
      );
      expect(
        name(LogicalKeyboardKey.f11, held: {LogicalKeyboardKey.shiftLeft}),
        'Shift+F11',
      );
    });

    test('either side of a modifier pair counts', () {
      expect(
        name(
          LogicalKeyboardKey.keyF,
          character: 'f',
          held: {LogicalKeyboardKey.controlRight},
        ),
        'Ctrl+F',
      );
    });
  });
}
