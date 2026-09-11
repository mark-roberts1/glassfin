/// Press-and-hold, and the synthetic autorepeat.
///
/// The tuned constants — 500ms to count as a hold, 650ms then 60ms to repeat —
/// were arrived at on real hardware in the Qt build and are carried over
/// verbatim. What these tests pin down is the *logic* around them, which is where
/// the bugs actually are: which side of a hold fires, what a second key-down
/// while the first is still held does, and which sources repeat at all.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/input/input_map.dart';
import 'package:glassfin/input/pipeline.dart';

InputMaps _maps(String mapping) => InputMaps([
  InputMapFile.parse(
    'test.json',
    '{"name": "Test", "idmatcher": "Pad", "mapping": $mapping}',
  )!,
]);

/// A pipeline with a clock under the test's control.
class _Harness {
  _Harness(String mapping) {
    pipeline = InputPipeline(
      maps: _maps(mapping),
      onActions: emitted.addAll,
      now: () => _now,
    );
  }

  late final InputPipeline pipeline;
  final List<String> emitted = [];
  DateTime _now = DateTime(2026);

  void advance(Duration by) => _now = _now.add(by);

  void down(String key) => pipeline.receive('Pad', key, KeyState.down);
  void up(String key) => pipeline.receive('Pad', key, KeyState.up);
}

void main() {
  group('short and long press', () {
    test('a quick press fires the short action, on release', () {
      final test = _Harness('{"B": {"short": "back", "long": "home"}}');

      test.down('B');
      // **Nothing yet** — which of the two this is cannot be known while the
      // button is still down.
      expect(test.emitted, isEmpty);

      test.advance(const Duration(milliseconds: 120));
      test.up('B');
      expect(test.emitted, ['back']);
    });

    test('a held press fires the long action', () {
      final test = _Harness('{"B": {"short": "back", "long": "home"}}');

      test.down('B');
      test.advance(const Duration(milliseconds: 600));
      test.up('B');
      expect(test.emitted, ['home']);
    });

    test('500ms exactly counts as long', () {
      final test = _Harness('{"B": {"short": "back", "long": "home"}}');
      test.down('B');
      test.advance(InputPipeline.longHold);
      test.up('B');
      expect(test.emitted, ['home']);
    });

    test('a repeated key-down does not restart the hold clock', () {
      // A driver or a compositor may send several downs for one physical press.
      // Resetting the clock on each would make a long press unreachable — you
      // would be holding the button and it would keep deciding you had just
      // started.
      final test = _Harness('{"B": {"short": "back", "long": "home"}}');

      test.down('B');
      for (var tick = 0; tick < 10; tick++) {
        test.advance(const Duration(milliseconds: 80));
        test.down('B');
      }
      test.up('B');
      expect(test.emitted, ['home']);
    });

    test('a hold with only a short action fires immediately', () {
      // Nothing to wait for, so waiting would just feel broken.
      final test = _Harness('{"B": {"short": "back"}}');
      test.down('B');
      expect(test.emitted, ['back']);
    });

    test('a release with no press pending emits nothing', () {
      final test = _Harness('{"B": {"short": "back", "long": "home"}}');
      test.up('B');
      expect(test.emitted, isEmpty);
    });
  });

  group('plain actions', () {
    test('fire on key-down, not on release', () {
      final test = _Harness('{"A": "enter"}');

      test.down('A');
      expect(test.emitted, ['enter']);

      test.up('A');
      expect(test.emitted, ['enter']);
    });

    test('an array fires every action, in order', () {
      final test = _Harness('{"Space": ["space", "play_pause"]}');
      test.down('Space');
      expect(test.emitted, ['space', 'play_pause']);
    });

    test('an unmapped key emits nothing', () {
      final test = _Harness('{"A": "enter"}');
      test.down('Z');
      expect(test.emitted, isEmpty);
    });
  });

  group('autorepeat', () {
    test('a held key repeats after the initial delay', () {
      fakeAsync((async) {
        final emitted = <String>[];
        final pipeline = InputPipeline(
          maps: _maps('{"KEY_HAT_DOWN": "down"}'),
          onActions: emitted.addAll,
        );

        pipeline.receive('Pad', 'KEY_HAT_DOWN', KeyState.down);
        expect(emitted, ['down']);

        // Nothing extra before the delay is up: a tap must move one square.
        async.elapse(const Duration(milliseconds: 600));
        expect(emitted, ['down']);

        async.elapse(const Duration(milliseconds: 100));
        expect(emitted.length, 2);

        // Then every 60ms.
        async.elapse(const Duration(milliseconds: 300));
        expect(emitted.length, greaterThan(5));

        pipeline.receive('Pad', 'KEY_HAT_DOWN', KeyState.up);
        final atRelease = emitted.length;
        async.elapse(const Duration(seconds: 1));
        expect(emitted.length, atRelease, reason: 'release must stop it');

        pipeline.dispose();
      });
    });

    test('the keyboard does not get a synthetic repeat', () {
      // The operating system already repeats a held key at the rate its owner
      // chose. Repeating it again here would double that rate and override the
      // preference — and the Qt build only avoided it by accident, because Qt's
      // own repeat arrived faster than the 650ms delay and kept resetting it.
      fakeAsync((async) {
        final emitted = <String>[];
        final pipeline = InputPipeline(
          maps: _maps('{"Down": "down"}'),
          onActions: emitted.addAll,
        );

        pipeline.receive('Pad', 'Down', KeyState.down, synthesiseRepeat: false);
        async.elapse(const Duration(seconds: 3));
        expect(emitted, ['down']);

        pipeline.dispose();
      });
    });

    test('a press with no release coming never starts repeating', () {
      // A CEC deck-control code has no key-up, so a repeat would never stop.
      fakeAsync((async) {
        final emitted = <String>[];
        final pipeline = InputPipeline(
          maps: _maps('{"KEY_PLAY": "play"}'),
          onActions: emitted.addAll,
        );

        pipeline.receive('Pad', 'KEY_PLAY', KeyState.pressed);
        async.elapse(const Duration(seconds: 3));
        expect(emitted, ['play']);

        pipeline.dispose();
      });
    });

    test('dispose stops a repeat in flight', () {
      fakeAsync((async) {
        final emitted = <String>[];
        final pipeline = InputPipeline(
          maps: _maps('{"KEY_HAT_DOWN": "down"}'),
          onActions: emitted.addAll,
        );

        pipeline.receive('Pad', 'KEY_HAT_DOWN', KeyState.down);
        async.elapse(const Duration(milliseconds: 800));
        expect(emitted.length, greaterThan(1));

        pipeline.dispose();
        final atDispose = emitted.length;
        async.elapse(const Duration(seconds: 2));
        expect(emitted.length, atDispose);
      });
    });

    test('an array value repeats, which the original did not do', () {
      // The Qt build appended only single-string actions to its autorepeat list,
      // because the two forms went down different branches of a type check — an
      // accident of QVariant rather than a decision. Unifying them here turned out
      // to be what the right thumbstick needs: it is mapped to an array, scroll
      // plus volume, and a held stick that moved the page exactly once would be
      // useless.
      fakeAsync((async) {
        final emitted = <String>[];
        final pipeline = InputPipeline(
          maps: _maps('{"KEY_AXIS_3_DOWN": ["scroll_down", "decrease_volume"]}'),
          onActions: emitted.addAll,
        );

        pipeline.receive('Pad', 'KEY_AXIS_3_DOWN', KeyState.down);
        expect(emitted, ['scroll_down', 'decrease_volume']);

        async.elapse(const Duration(milliseconds: 800));
        expect(
          emitted.length,
          greaterThan(2),
          reason: 'a held stick should keep scrolling',
        );
        // Both actions repeat together, so context can keep choosing between them.
        expect(emitted.where((a) => a == 'scroll_down').length, greaterThan(1));
        expect(
          emitted.where((a) => a == 'decrease_volume').length,
          greaterThan(1),
        );

        pipeline.receive('Pad', 'KEY_AXIS_3_DOWN', KeyState.up);
        pipeline.dispose();
      });
    });

    test('an unbound button does not start the repeat timer', () {
      // `"KEY_BUTTON_8": ""` is a real line in the bundled pads. The original
      // read it as an action named "", which fired nothing but did set a 60ms
      // timer running for as long as the button was held.
      fakeAsync((async) {
        final emitted = <String>[];
        final pipeline = InputPipeline(
          maps: _maps('{"KEY_BUTTON_8": ""}'),
          onActions: emitted.addAll,
        );

        pipeline.receive('Pad', 'KEY_BUTTON_8', KeyState.down);
        async.elapse(const Duration(seconds: 3));
        expect(emitted, isEmpty);

        pipeline.dispose();
      });
    });
  });
}
