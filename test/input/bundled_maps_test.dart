/// The files in `assets/inputmaps/`, exactly as shipped.
///
/// Every other test in this directory builds its own little mapping. This one
/// reads the real thing off disk, because the files were copied verbatim from the
/// Qt build and the whole promise of Phase 6 is that they keep working unchanged.
/// If a bundled map stops parsing, or a shortcut stops resolving, this is where it
/// shows up — rather than on a sofa with a controller that does nothing.
///
/// Read with [File] rather than through the asset bundle on purpose: it is the
/// files themselves that are the contract, and this way the test says so.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/input/actions.dart';
import 'package:glassfin/input/input_map.dart';
import 'package:glassfin/input/keyboard.dart';

const _directory = 'assets/inputmaps';

InputMaps _loadAll() {
  final files =
      Directory(_directory)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return InputMaps([
    for (final file in files)
      ?InputMapFile.parse(file.uri.pathSegments.last, file.readAsStringSync()),
  ]);
}

List<String> _actions(InputMaps maps, String source, String key) => [
  for (final mapped in maps.lookUp(source, key))
    if (mapped is MappedActions) ...mapped.actions,
];

void main() {
  late InputMaps maps;

  setUpAll(() => maps = _loadAll());

  test('every bundled file parses', () {
    final files = Directory(
      _directory,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'));

    expect(files, isNotEmpty, reason: 'the maps should be where they were');
    for (final file in files) {
      expect(
        () => InputMapFile.parse(file.path, file.readAsStringSync()),
        returnsNormally,
        reason: file.path,
      );
    }
  });

  test('twelve of the thirteen load, and the thirteenth is opt-in', () {
    // Two things at once. Three files are called "Xbox Controller", and keyed on
    // that shared name rather than on the file, two of them would vanish here.
    //
    // The one that is *meant* to be missing is `dualshock4-xbox-emulate.json`,
    // whose `idmatcher` line is commented out: a DS4 in Windows mode is
    // indistinguishable from an Xbox pad, so its header tells you to uncomment
    // the line yourself. A map with no `idmatcher` is disabled, not broken, and
    // that distinction has to survive — loudly warning about this file on every
    // launch would be wrong.
    expect(maps.length, 12);
    expect(
      InputMapFile.parse(
        'dualshock4-xbox-emulate.json',
        File('$_directory/dualshock4-xbox-emulate.json').readAsStringSync(),
      ),
      isNull,
    );
  });

  group('keyboard.json', () {
    test('navigation, including the Shift variants', () {
      expect(_actions(maps, keyboardSource, 'Left'), ['left']);
      expect(_actions(maps, keyboardSource, 'Shift+Left'), ['left']);
      expect(_actions(maps, keyboardSource, 'Up'), ['up']);
      expect(_actions(maps, keyboardSource, 'Return'), ['enter']);
      expect(_actions(maps, keyboardSource, 'Enter'), ['enter']);
    });

    test('Esc and Backspace are a short/long hold', () {
      for (final key in ['Esc', 'Backspace']) {
        final hold = maps.lookUp(keyboardSource, key).single as MappedHold;
        expect(hold.short, 'back', reason: key);
        expect(hold.long, 'exit', reason: key);
      }
    });

    test('a letter both types and acts', () {
      // The multiple-actions semantic, in the place it matters most. The letter
      // comes first and the shortcut second, which is what lets a text field take
      // the character and leave the action unused.
      expect(_actions(maps, keyboardSource, 'p'), ['p', 'play_pause']);
      expect(_actions(maps, keyboardSource, 'P'), ['P', 'play_pause']);
      expect(_actions(maps, keyboardSource, 'a'), ['a', 'cycle_audio']);
      expect(_actions(maps, keyboardSource, 'q'), ['q']);
    });

    test('Space types and pauses', () {
      expect(_actions(maps, keyboardSource, 'Space'), ['space', 'play_pause']);
    });

    test('a digit types itself through the capture group', () {
      expect(_actions(maps, keyboardSource, '7'), ['7']);
    });

    test('the volume keys also type', () {
      expect(_actions(maps, keyboardSource, '='), ['=', 'increase_volume']);
      expect(_actions(maps, keyboardSource, '+'), ['+', 'increase_volume']);
      expect(_actions(maps, keyboardSource, '-'), ['-', 'decrease_volume']);
    });

    test('the modifier shortcuts resolve', () {
      expect(_actions(maps, keyboardSource, 'Ctrl+F'), ['search']);
      expect(_actions(maps, keyboardSource, 'Ctrl+Shift+F'), [
        'host:toggleWebMode',
      ]);
      expect(_actions(maps, keyboardSource, 'F11'), ['host:fullscreen']);
      expect(_actions(maps, keyboardSource, 'Ctrl+W'), ['host:quit']);
      expect(_actions(maps, keyboardSource, 'PgDown'), ['seek_forward']);
      expect(_actions(maps, keyboardSource, 'Ctrl+P'), ['pause']);
    });

    test('media keys from a FLIRC or a Harmony', () {
      expect(_actions(maps, keyboardSource, 'Toggle Media Play/Pause'), [
        'play_pause',
      ]);
      expect(_actions(maps, keyboardSource, 'Media Stop'), ['stop']);
      expect(_actions(maps, keyboardSource, 'Back'), ['back']);
    });
  });

  group('pads', () {
    test('an Xbox pad on Linux gets the Linux axis layout', () {
      // Not the Windows one. The bundled files differ here — right thumbstick is
      // axis 4 on Linux and axis 3 on Windows — and keying the loaded maps on the
      // shared `name` silently handed Linux the wrong file.
      expect(_actions(maps, 'Xbox One', 'KEY_AXIS_4_UP'), ['increase_volume']);
      expect(_actions(maps, 'Xbox One', 'KEY_AXIS_4_DOWN'), ['decrease_volume']);
      expect(_actions(maps, 'Xbox One', 'KEY_BUTTON_0'), ['enter']);
      expect(_actions(maps, 'Xbox One', 'KEY_HAT_UP'), ['up']);
    });

    test('B is back on a tap and home on a hold', () {
      final hold = maps.lookUp('Xbox One', 'KEY_BUTTON_1').single as MappedHold;
      expect(hold.short, 'back');
      expect(hold.long, 'home');
    });

    test('an unbound button yields nothing at all', () {
      // `"KEY_BUTTON_8": ""` — start, deliberately doing nothing.
      expect(maps.lookUp('Xbox One', 'KEY_BUTTON_8'), isEmpty);
    });

    test('a DualShock 4 over Bluetooth', () {
      expect(_actions(maps, 'Wireless Controller', 'KEY_BUTTON_1'), ['enter']);
      expect(_actions(maps, 'Wireless Controller', 'KEY_HAT_LEFT'), ['left']);
      expect(_actions(maps, 'Wireless Controller', 'KEY_AXIS_1_DOWN'), ['down']);
    });

    test('the DualShock 4 layout, as the owner asked for it', () {
      // SDL's gamepad button order, confirmed on hardware — the numbers are not
      // guessable and the file's original comments mislabelled several of them.
      const expected = {
        'KEY_BUTTON_0': 'enter', //      X
        'KEY_BUTTON_2': 'mute', //       Square
        'KEY_BUTTON_3': 'menu', //       Triangle
        'KEY_BUTTON_4': 'host:fullscreen', // Share
        'KEY_BUTTON_6': 'play_pause', // Options
        'KEY_BUTTON_9': 'rewind', //     L1
        'KEY_BUTTON_10': 'fast_forward', // R1
        'KEY_BUTTON_11': 'search', //    Touchpad
        'KEY_AXIS_4_DOWN': 'decrease_volume', // L2
        'KEY_AXIS_5_DOWN': 'increase_volume', // R2
      };

      expected.forEach((key, action) {
        expect(_actions(maps, 'PS4 Controller', key), [action], reason: key);
      });
    });

    test('a DualShock 4 over USB, which renumbers every button', () {
      // Same pad, same actions, different numbers: over USB the kernel reports X
      // as button 0 where Bluetooth reports it as button 1. This is exactly why
      // the two layouts are separate files matched on the reported name, and why
      // `idmatcher` is the thing that has to keep working.
      expect(_actions(maps, 'PS4 Controller', 'KEY_BUTTON_0'), ['enter']);
      expect(_actions(maps, 'Wireless Controller', 'KEY_BUTTON_1'), ['enter']);

      final hold =
          maps.lookUp('PS4 Controller', 'KEY_BUTTON_1').single as MappedHold;
      expect(hold.short, 'back');
      expect(hold.long, 'home');
    });
  });

  group('the actions the maps name', () {
    test('every action a pad can reach is one the interface answers', () {
      // The pads are the couch bar's actual input, so an unrecognised action name
      // in one of those files is a button that does nothing from three metres.
      // `host:` actions are the host's business and checked separately.
      const pads = ['Xbox One', 'Wireless Controller', 'PS4 Controller'];
      const keys = [
        'KEY_BUTTON_0',
        'KEY_BUTTON_1',
        'KEY_BUTTON_2',
        'KEY_BUTTON_3',
        'KEY_BUTTON_4',
        'KEY_BUTTON_5',
        'KEY_HAT_UP',
        'KEY_HAT_DOWN',
        'KEY_HAT_LEFT',
        'KEY_HAT_RIGHT',
        'KEY_AXIS_0_UP',
        'KEY_AXIS_0_DOWN',
        'KEY_AXIS_1_UP',
        'KEY_AXIS_1_DOWN',
      ];

      final unknown = <String>{};
      for (final pad in pads) {
        for (final key in keys) {
          for (final mapped in maps.lookUp(pad, key)) {
            final names = switch (mapped) {
              MappedActions(:final actions) => actions,
              MappedHold(:final short, :final long) => [?short, ?long],
            };
            for (final action in names) {
              if (action.startsWith('host:')) continue;
              if (InputAction.fromId(action) == null) unknown.add('$key → $action');
            }
          }
        }
      }

      // Empty, and one near-miss is worth knowing about: xbox-controller-linux
      // .json misspells `cycle_subtitles` as `cycle_subtitle` on its Y button —
      // but defines `KEY_BUTTON_3` twice, and the second definition (`search`)
      // wins, so the typo is unreachable. Left exactly as the Qt build had it.
      expect(unknown, isEmpty);
    });
  });
}
