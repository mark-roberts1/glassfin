/// A pad that drives Steam's menu must not also drive Glassfin behind it.
///
/// Found on the BC-250 in Game Mode: the X that confirmed Steam's "Exit game"
/// also selected a Continue Watching card, so an episode started as the app
/// closed. These pin down the gate that stops that, and the one way it must
/// never fail — leaving the pad dead.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/input/focus_gate.dart';
import 'package:glassfin/input/input_map.dart';
import 'package:glassfin/input/pipeline.dart';

const _pad = 'Wireless Controller';

void main() {
  group('the gate', () {
    test('admits everything while focused', () {
      final gate = FocusGate()..setFocused(true);
      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down), isTrue);
      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.up), isTrue);
    });

    test('drops every pad event while another window has focus', () {
      final gate = FocusGate()
        ..setFocused(true)
        ..setFocused(false);

      expect(gate.admit(_pad, 'KEY_HAT_DOWN', KeyState.down), isFalse);
      expect(gate.admit(_pad, 'KEY_HAT_DOWN', KeyState.up), isFalse);
      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down), isFalse);
      expect(gate.admit(_pad, 'KEY_PLAY', KeyState.pressed), isFalse);
    });

    test('never mutes before the window has been reported focused', () {
      // A session that reports no focus at all would otherwise start with the
      // pad dead, which on a television looks exactly like a broken controller.
      final gate = FocusGate();
      expect(gate.setFocused(false), isFalse);
      expect(gate.focused, isTrue);
      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down), isTrue);
    });

    test('reports only real changes', () {
      final gate = FocusGate();
      expect(gate.setFocused(true), isFalse, reason: 'already admitting');
      expect(gate.setFocused(false), isTrue);
      expect(gate.setFocused(false), isFalse);
      expect(gate.setFocused(true), isTrue);
    });

    test('ignores a button held across the return of focus until it is released', () {
      // Pressed in Steam's menu, still down when Glassfin gets focus back: that
      // press was never meant for Glassfin, including its release.
      final gate = FocusGate()
        ..setFocused(true)
        ..setFocused(false);

      gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down);
      gate.setFocused(true);

      expect(
        gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down),
        isFalse,
        reason: 'a repeated down of the same press',
      );
      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.up), isFalse);

      // The next press is a new one, and belongs to Glassfin.
      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down), isTrue);
    });

    test('does not wait for a button already released while unfocused', () {
      final gate = FocusGate()
        ..setFocused(true)
        ..setFocused(false);

      gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down);
      gate.admit(_pad, 'KEY_BUTTON_0', KeyState.up);
      gate.setFocused(true);

      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down), isTrue);
    });

    test('other buttons are unaffected by one being held across focus', () {
      final gate = FocusGate()
        ..setFocused(true)
        ..setFocused(false);
      gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down);
      gate.setFocused(true);

      expect(gate.admit(_pad, 'KEY_HAT_DOWN', KeyState.down), isTrue);
    });

    test('mutes while any source that has seen focus reports it lost', () {
      // Under gamescope the window stays focused while Steam's menu has input.
      final gate = FocusGate()
        ..setFocused(true)
        ..setFocused(true, source: 'gamescope');

      expect(gate.setFocused(false, source: 'gamescope'), isTrue);
      expect(gate.focused, isFalse);
      expect(gate.admit(_pad, 'KEY_BUTTON_0', KeyState.down), isFalse);

      expect(gate.setFocused(true, source: 'gamescope'), isTrue);
      expect(gate.focused, isTrue);
    });

    test('stays muted until every source has focus back', () {
      final gate = FocusGate()
        ..setFocused(true)
        ..setFocused(true, source: 'gamescope')
        ..setFocused(false)
        ..setFocused(false, source: 'gamescope');

      expect(gate.setFocused(true, source: 'gamescope'), isFalse);
      expect(gate.focused, isFalse, reason: 'the window is still unfocused');
      expect(gate.setFocused(true), isTrue);
    });

    test('a source that has never seen focus cannot mute another source', () {
      final gate = FocusGate()..setFocused(true);
      expect(gate.setFocused(false, source: 'gamescope'), isFalse);
      expect(gate.hasSeenFocus('gamescope'), isFalse);
      expect(gate.focused, isTrue);
    });

    test('tracks the same code on two pads separately', () {
      final gate = FocusGate()
        ..setFocused(true)
        ..setFocused(false);
      gate.admit('Pad A', 'KEY_BUTTON_0', KeyState.down);
      gate.setFocused(true);

      expect(gate.admit('Pad B', 'KEY_BUTTON_0', KeyState.down), isTrue);
    });
  });

  group('the pipeline on losing focus', () {
    InputMaps maps(String mapping) => InputMaps([
      InputMapFile.parse(
        'test.json',
        '{"name": "Test", "idmatcher": "Pad", "mapping": $mapping}',
      )!,
    ]);

    test('reset drops a hold being timed instead of firing it', () {
      // The PS button's short press is `home`, fired on release. If Steam's menu
      // takes focus between press and release, that release must not send
      // Glassfin home.
      final emitted = <String>[];
      final pipeline = InputPipeline(
        maps: maps('{"KEY_BUTTON_10": {"short": "home", "long": "menu"}}'),
        onActions: emitted.addAll,
      );

      pipeline.receive('Pad', 'KEY_BUTTON_10', KeyState.down);
      pipeline.reset();
      pipeline.receive('Pad', 'KEY_BUTTON_10', KeyState.up);

      expect(emitted, isEmpty);
    });

    test('reset stops a repeat in flight', () {
      fakeAsync((async) {
        final emitted = <String>[];
        final pipeline = InputPipeline(
          maps: maps('{"KEY_HAT_DOWN": "down"}'),
          onActions: emitted.addAll,
        );

        pipeline.receive('Pad', 'KEY_HAT_DOWN', KeyState.down);
        async.elapse(const Duration(milliseconds: 800));
        pipeline.reset();
        final atReset = emitted.length;

        async.elapse(const Duration(seconds: 1));
        expect(emitted.length, atReset);

        pipeline.dispose();
      });
    });
  });
}
