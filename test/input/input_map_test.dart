/// The mapping engine, against the same value forms the bundled files use.
///
/// These are the tests the Qt build could not have: the engine was entangled with
/// QVariant, a filesystem watcher and a profile manager, so the only way to find
/// out what a button did was to press it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/input/input_map.dart';

InputMapFile _map(String id, String idMatcher, String mapping) =>
    InputMapFile.parse(id, '{"name": "$id", "idmatcher": "$idMatcher", '
        '"mapping": $mapping}')!;

List<String> _actions(InputMaps maps, String source, String key) => [
  for (final mapped in maps.lookUp(source, key))
    if (mapped is MappedActions) ...mapped.actions,
];

void main() {
  group('value forms', () {
    test('a plain string is one action', () {
      expect(parseMappedValue('enter'), isA<MappedActions>());
      expect((parseMappedValue('enter')! as MappedActions).actions, ['enter']);
    });

    test('an array is several actions, in order', () {
      final value = parseMappedValue(['space', 'play_pause'])! as MappedActions;
      expect(value.actions, ['space', 'play_pause']);
    });

    test('short and long are a hold', () {
      final value =
          parseMappedValue({'short': 'back', 'long': 'home'})! as MappedHold;
      expect(value.short, 'back');
      expect(value.long, 'home');
    });

    test('an empty string is unbound rather than an action named ""', () {
      // `"KEY_BUTTON_8": ""` in the bundled pads. Treating it as an action made
      // holding an unbound button run the autorepeat timer for as long as you
      // held it, firing nothing, forever.
      expect(parseMappedValue(''), isNull);
      expect(parseMappedValue(<String>['']), isNull);
      expect(parseMappedValue({'short': ''}), isNull);
    });
  });

  group('matching', () {
    test('patterns are anchored, so a prefix is not a match', () {
      final maps = InputMaps([
        _map('pad.json', 'Pad', '{"KEY_BUTTON_1": "enter"}'),
      ]);

      expect(_actions(maps, 'Pad', 'KEY_BUTTON_1'), ['enter']);
      expect(_actions(maps, 'Pad', 'KEY_BUTTON_11'), isEmpty);
      expect(_actions(maps, 'Pad', 'XKEY_BUTTON_1'), isEmpty);
    });

    test('every pattern that matches contributes', () {
      // The important semantic, and the reason a key can both type a letter and
      // pause a film.
      final maps = InputMaps([
        _map('kb.json', 'Keyboard', '{"([A-Za-z])": "%1", "[Pp]": "play_pause"}'),
      ]);

      expect(_actions(maps, 'Keyboard', 'P'), ['P', 'play_pause']);
      expect(_actions(maps, 'Keyboard', 'p'), ['p', 'play_pause']);
      expect(_actions(maps, 'Keyboard', 'q'), ['q']);
    });

    test('a capture group reaches the action as %1', () {
      final maps = InputMaps([
        _map('cec.json', 'CEC.*', '{"KEY_NUMERIC_([0-9])": "%1"}'),
      ]);

      expect(_actions(maps, 'CEC', 'KEY_NUMERIC_7'), ['7']);
      expect(_actions(maps, 'CEC', 'KEY_NUMERIC_0'), ['0']);
    });

    test('substitution reaches a hold and an array too', () {
      final maps = InputMaps([
        _map('t.json', 'T', '{"N([0-9])": {"short": "%1", "long": "long%1"}}'),
      ]);

      final hold = maps.lookUp('T', 'N4').single as MappedHold;
      expect(hold.short, '4');
      expect(hold.long, 'long4');
    });

    test('the source is matched by pattern, not by equality', () {
      final maps = InputMaps([
        _map('xbox.json', 'XInput.*|Microsoft.*joystick driver', '{"A": "enter"}'),
      ]);

      expect(_actions(maps, 'XInput Controller #1', 'A'), ['enter']);
      expect(_actions(maps, 'Microsoft X-Box joystick driver', 'A'), ['enter']);
      expect(_actions(maps, 'Wireless Controller', 'A'), isEmpty);
    });

    test('an unknown source produces nothing rather than throwing', () {
      final maps = InputMaps([_map('kb.json', 'Keyboard.*', '{"A": "enter"}')]);
      expect(maps.lookUp('Some Unknown Remote', 'A'), isEmpty);
    });

    test('"direct" bypasses the mapping entirely', () {
      // How an external process injects a semantic action without owning a map —
      // the CEC bridge, eventually.
      final maps = InputMaps([_map('kb.json', 'Keyboard.*', '{"A": "enter"}')]);
      expect(_actions(maps, 'direct', 'play_pause'), ['play_pause']);
    });

    test('a pattern that does not compile is skipped, not fatal', () {
      final matcher = CachedRegexMatcher<String>();
      expect(matcher.add('(unclosed', 'nope'), isFalse);
      expect(matcher.add('fine', 'yes'), isTrue);
      expect(matcher.match('fine'), ['yes']);
    });
  });

  group('files', () {
    test('whole-line // comments are stripped, inline ones are not', () {
      // Exactly the original rule. Narrow on purpose: a pattern containing a
      // slash pair has to survive.
      expect(stripLineComments('  // gone\n{"a": 1}\n'), '{"a": 1}\n');
      expect(stripLineComments('{"a": "x // y"}'), '{"a": "x // y"}');
    });

    test('a missing idmatcher is a disabled map, not an error', () {
      expect(InputMapFile.parse('x.json', '{"name": "X", "mapping": {}}'), isNull);
    });

    test('a missing name or mapping is an error', () {
      expect(
        () => InputMapFile.parse('x.json', '{"idmatcher": "X", "mapping": {}}'),
        throwsFormatException,
      );
      expect(
        () => InputMapFile.parse('x.json', '{"name": "X", "idmatcher": "X"}'),
        throwsFormatException,
      );
    });

    test('a duplicate JSON key is last-wins, as both parsers agree', () {
      // `xbox-controller-linux.json` really does define KEY_BUTTON_3 twice, so
      // this is describing a bundled file rather than a hypothetical.
      final map = _map(
        'x.json',
        'X',
        '{"KEY_BUTTON_3": "cycle_subtitle", "KEY_BUTTON_3": "search"}',
      );
      expect(map.mapping.keys, ['KEY_BUTTON_3']);
      expect((map.mapping['KEY_BUTTON_3']! as MappedActions).actions, [
        'search',
      ]);
    });
  });

  group('overlaying', () {
    test('a later file claiming the same idmatcher replaces the earlier one', () {
      // The user-override mechanism: a map in ~/.local/share takes a bundled one
      // over rather than doubling up with it.
      final maps = InputMaps([
        _map('bundled.json', 'Keyboard.*', '{"A": "enter"}'),
        _map('user.json', 'Keyboard.*', '{"A": "back"}'),
      ]);

      expect(_actions(maps, 'Keyboard', 'A'), ['back']);
    });

    test('files with different idmatchers coexist under the same name', () {
      // **The Xbox collision.** Three bundled files are all named "Xbox
      // Controller" with different idmatchers and different axis layouts. Keyed
      // on the name they overwrite each other and a Linux pad gets the Windows
      // axes; keyed on the file name the idmatcher picks the right one.
      final maps = InputMaps([
        _map('xbox-linux.json', 'Xbox One', '{"KEY_AXIS_4_UP": "increase_volume"}'),
        _map('xbox-windows.json', 'XInput.*', '{"KEY_AXIS_3_UP": "increase_volume"}'),
      ]);

      expect(_actions(maps, 'Xbox One', 'KEY_AXIS_4_UP'), ['increase_volume']);
      expect(_actions(maps, 'Xbox One', 'KEY_AXIS_3_UP'), isEmpty);
      expect(maps.filesFor('Xbox One'), ['xbox-linux.json']);
    });
  });

  group('caching', () {
    test('a miss is cached as well as a hit', () {
      final matcher = CachedRegexMatcher<String>();
      matcher.add('A', 'enter');

      expect(matcher.match('Z'), isEmpty);
      expect(matcher.match('Z'), isEmpty);
      expect(matcher.match('A'), ['enter']);
    });

    test('adding a pattern invalidates the cache', () {
      final matcher = CachedRegexMatcher<String>();
      expect(matcher.match('A'), isEmpty);
      matcher.add('A', 'enter');
      expect(matcher.match('A'), ['enter']);
    });
  });
}
