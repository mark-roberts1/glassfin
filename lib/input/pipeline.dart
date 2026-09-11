/// The funnel every input source empties into.
///
/// One method — [InputPipeline.receive], taking `(source, keycode, state)` —
/// exactly as the Qt build's backends all emitted one signal into
/// `InputComponent::remapInput`. Everything about *when* an action fires lives
/// here: the short/long press split, and the synthetic autorepeat for sources
/// that have none of their own.
///
/// Pure Dart on purpose. It owns timers but no widgets, so the press-and-hold
/// behaviour can be tested without a gamepad, a window, or a frame.
library;

import 'dart:async';

import 'input_map.dart';

/// How a source reports a key.
enum KeyState {
  down,
  up,

  /// A press with no release coming — a CEC deck-control code, an injected
  /// action. Never starts autorepeat, since there would be nothing to stop it.
  pressed,
}

/// Turns key codes into action names.
class InputPipeline {
  InputPipeline({required this.maps, required this.onActions, this.now});

  /// Long enough to be deliberate, short enough not to feel broken. 500ms is
  /// the Qt build's value and it was tuned on a real remote.
  static const longHold = Duration(milliseconds: 500);

  /// The delay before a held key starts repeating, then the interval between
  /// repeats. 60ms is half the fastest press-and-release a person manages, which
  /// is the reasoning recorded in `InputComponent.cpp`.
  static const initialRepeatDelay = Duration(milliseconds: 650);
  static const repeatInterval = Duration(milliseconds: 60);

  final InputMaps maps;

  /// Called with every action name a press produced, in order. May be called
  /// with one action (a resolved hold) or several (a key that means two things).
  final void Function(List<String> actions) onActions;

  /// Overridable so that "hold for 500ms" can be tested in no time at all.
  /// Null means the wall clock.
  final DateTime Function()? now;

  Timer? _repeatTimer;
  List<String> _repeatActions = const [];

  /// The hold currently being timed, and when it started. A press is only a long
  /// press once it has been released, so this has to outlive the key-down.
  MappedHold? _pendingHold;
  DateTime? _holdStarted;

  DateTime _clock() => now?.call() ?? DateTime.now();

  /// Feeds one key event in.
  ///
  /// [synthesiseRepeat] is **false for the keyboard and true for a pad**, and the
  /// distinction matters: an operating system already repeats a held key at the
  /// rate its owner chose, so repeating it again here would double the rate and
  /// override that preference. A joystick repeats nothing at all, so without this
  /// a held D-pad moves the focus exactly one square.
  ///
  /// The Qt build ran the synthetic timer for every source including the
  /// keyboard, and got away with it only because Qt's own key repeat arrived
  /// faster than the 650ms delay and so kept resetting the timer before it could
  /// fire. That is a coincidence of two unrelated numbers, not a design.
  void receive(
    String source,
    String keycode,
    KeyState state, {
    bool synthesiseRepeat = true,
  }) {
    if (state == KeyState.up) {
      _cancelRepeat();
      _resolveHold();
      return;
    }

    final queued = <String>[];
    final repeatable = <String>[];

    for (final mapped in maps.lookUp(source, keycode)) {
      switch (mapped) {
        case MappedActions(:final actions):
          queued.addAll(actions);
          repeatable.addAll(actions);

        case MappedHold(:final long, :final short):
          if (long != null) {
            // Do not restart the clock on a repeat of a key that is still down:
            // a driver or an operating system may well send several downs for
            // one physical press, and each one would reset the hold to zero and
            // make a long press unreachable.
            if (_pendingHold == null) {
              _pendingHold = mapped;
              _holdStarted = _clock();
            }
          } else if (short != null) {
            // No long action to wait for, so there is nothing to decide.
            queued.add(short);
          }
      }
    }

    _repeatActions = repeatable;
    if (repeatable.isNotEmpty &&
        state != KeyState.pressed &&
        synthesiseRepeat) {
      _startRepeat();
    }

    if (queued.isNotEmpty) onActions(queued);
  }

  /// Decides a completed press, now that its duration is known.
  void _resolveHold() {
    final hold = _pendingHold;
    final started = _holdStarted;
    if (hold == null || started == null) return;

    final long = _clock().difference(started) >= longHold;
    _pendingHold = null;
    _holdStarted = null;

    final action = long ? hold.long : hold.short;
    if (action != null) onActions([action]);
  }

  void _startRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = Timer(initialRepeatDelay, () {
      _emitRepeat();
      _repeatTimer = Timer.periodic(repeatInterval, (_) => _emitRepeat());
    });
  }

  void _emitRepeat() {
    if (_repeatActions.isEmpty) return;
    onActions(_repeatActions);
  }

  void _cancelRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _repeatActions = const [];
  }

  /// Stops the clocks. A pipeline that outlives its timers keeps firing actions
  /// into a disposed interface.
  void dispose() {
    _cancelRepeat();
    _pendingHold = null;
    _holdStarted = null;
  }
}
