/// Where the mapping engine meets the router.
///
/// [InputMaps] answers "what does this key mean", [InputPipeline] answers "and
/// when", [InputRouter] answers "who gets it". This binds the three together and
/// is the only object the application has to hold on to.
///
/// It is deliberately the *single* owner of that binding, because the one rule in
/// CLAUDE.md that does the most damage when broken is that input enters at
/// exactly one place.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'actions.dart';
import 'focus_gate.dart';
import 'gamepad.dart';
import 'host_commands.dart';
import 'input_map.dart';
import 'keyboard.dart';
import 'pipeline.dart';
import 'router.dart';

/// Log every key code, mapped or not, in any build.
///
/// **Writing a mapping file requires knowing what the hardware calls its
/// buttons, and only the running application can answer that** — the names and
/// numbers depend on which SDL backend claimed the device, which in turn depends
/// on what else is running. The same DualShock 4 is `PS4 Controller` with twelve
/// buttons on its own, and `Wireless Controller` with thirteen and a different
/// order once Steam has taken the hidraw device and SDL has fallen back to
/// evdev. Neither is guessable, and a release build is exactly where you need to
/// find out, because that is what Steam launches.
///
/// Off unless asked for:
///
///     flatpak run --env=GLASSFIN_LOG_INPUT=1 org.glassfin.Glassfin
final bool logEveryCode =
    Platform.environment['GLASSFIN_LOG_INPUT'] == '1';

class InputEngine {
  InputEngine({
    required this.maps,
    required this.router,
    required this.host,
    this.onText,
  }) {
    _pipeline = InputPipeline(maps: maps, onActions: _dispatch);
    _gamepads = Gamepads(onInput: receive);
    // A machine with no SDL, or no pad, is a normal machine. The keyboard is
    // unaffected either way, so this is never worth failing over.
    _gamepads.start();
  }

  final InputMaps maps;

  /// **A callback rather than an object**, because the router is rebuilt on every
  /// frame from the current playback and menu state, while this engine outlives
  /// all of it — it owns the long-press clock and the autorepeat timer, which a
  /// rebuild must not reset. Asking for the router at the moment an action fires
  /// is what keeps a held button pointed at the application as it is *now*.
  final InputRouter Function() router;

  final HostCommands host;

  /// Where a character-valued action goes: a remote's number keys, typed into
  /// whatever field is open. Null when no field is open.
  ///
  /// The physical keyboard does not come through here — `event.character` reaches
  /// the text field before the mapping is ever consulted — so this exists for the
  /// sources that have no characters of their own. `KEY_NUMERIC_([0-9])` on a CEC
  /// remote is the case it was written for.
  final void Function(String text)? Function()? onText;

  late final InputPipeline _pipeline;
  late final Gamepads _gamepads;
  final FocusGate _focus = FocusGate();

  /// Whether a pad is actually being polled, for the Settings screen to show.
  bool get gamepadsRunning => _gamepads.running;

  /// Tells the engine whether Glassfin's window has focus.
  ///
  /// While it does not, pad input is ignored, so a controller operating Steam's
  /// menu does not also operate Glassfin behind it. See [FocusGate]. [reason] is
  /// only for the log.
  ///
  /// **Always logged**, not only under `GLASSFIN_LOG_INPUT`: whether a given
  /// compositor reports focus at all is the first thing to know when a pad seems
  /// muted, or when this protection seems not to work, and it costs a line per
  /// change.
  void setWindowFocused(bool focused, {String reason = ''}) {
    final suffix = reason.isEmpty ? '' : ' ($reason)';
    if (!_focus.setFocused(focused)) {
      if (!focused && _focus.focused) {
        debugPrint(
          'input: window reported unfocused before ever being focused; '
          'controller left enabled$suffix',
        );
      }
      return;
    }
    if (!focused) _pipeline.reset();
    debugPrint('input: window focus ${focused ? 'gained' : 'lost'}$suffix');
  }

  /// A physical key press. Returns true if the key was ours.
  ///
  /// "Ours" is decided by the mapping file rather than by whether anything
  /// actually happened: a mapped key that the current screen has no use for is
  /// still a key the interface owns, and letting it fall through to Flutter's
  /// default handling is how a remote's Back button ends up also moving focus.
  bool handleKey(KeyEvent event) {
    // A modifier on its own is not a press. Ctrl is half of Ctrl+F, and reporting
    // it as a key in its own right only produces a name — `"Alt+Alt Left"` — that
    // nothing maps and that reads like a bug in the naming.
    if (isModifierKey(event.logicalKey)) return false;

    final name = canonicalKeyName(event);

    // Key-up matters now, which it did not before Phase 6: it is what resolves a
    // short press against a long one, and what stops autorepeat.
    final state = event is KeyUpEvent ? KeyState.up : KeyState.down;

    final mapped = maps.lookUp(keyboardSource, name).isNotEmpty;
    receive(keyboardSource, name, state, synthesiseRepeat: false);
    return mapped;
  }

  /// Input from anything that is not the keyboard — a pad, eventually a CEC
  /// bridge. [source] is matched against each mapping file's `idmatcher`.
  void receive(
    String source,
    String keycode,
    KeyState state, {
    bool synthesiseRepeat = true,
  }) {
    // The keyboard is never gated: a compositor only delivers keys to the window
    // that has focus, so there is nothing to leak.
    final admitted =
        source == keyboardSource || _focus.admit(source, keycode, state);

    if (logEveryCode) {
      debugPrint(
        'input: $source "$keycode" ${state.name}'
        '${admitted ? '' : ' (ignored: not for this window)'}',
      );
    } else if (admitted &&
        state != KeyState.up &&
        maps.lookUp(source, keycode).isEmpty) {
      // The single most useful line when a button does nothing: it separates
      // "the pad is not reporting" from "the pad is reporting something no map
      // claims". **Not debug-only** — a controller that does nothing is a
      // release-build problem on somebody's television, and this costs one line
      // per press that already did nothing.
      debugPrint('input: $source "$keycode" is unmapped');
    }
    if (!admitted) return;
    _pipeline.receive(source, keycode, state, synthesiseRepeat: synthesiseRepeat);
  }

  /// One press can mean several things, so this walks them in the order the
  /// mapping file lists them and stops at the first that is actually consumed.
  ///
  /// That ordering is why `"Space": ["space", "play_pause"]` works: `space` is not
  /// an action this interface knows, so it falls through to `play_pause` — and
  /// when a text field is open the character has already been taken by the field
  /// before the mapping was consulted at all.
  void _dispatch(List<String> actions) {
    final current = router();
    final sink = onText?.call();

    for (final action in actions) {
      if (action.startsWith(hostPrefix)) {
        if (host.run(action)) return;
        continue;
      }

      final semantic = InputAction.fromId(action);
      if (semantic != null) {
        if (current.handle(semantic)) return;
        continue;
      }

      // Not an action this interface answers. A single character is text — that
      // is the whole of how a remote's keypad types. Anything longer is a name
      // from the mapping files that this client has no case for, which is normal
      // and documented in [InputAction.fromId].
      if (sink != null && action.length == 1) {
        sink(action);
        return;
      }
    }
  }

  void dispose() {
    _gamepads.stop();
    _pipeline.dispose();
  }
}
