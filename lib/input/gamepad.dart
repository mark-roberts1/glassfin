/// Gamepads, by FFI to SDL2.
///
/// A port of `glassfin_old/src/input/InputSDL.cpp`. SDL is used for its joystick
/// subsystem and nothing else: no window, no renderer, no audio. The surface is
/// about a dozen C functions and three event structs, which is why the audit
/// called this the cheaper of the two options — a Dart package would have to be
/// trusted to keep reporting the *names* SDL reports, and those names are what
/// `idmatcher` matches on.
///
/// **Synthesised key codes, not button semantics.** A button becomes
/// `KEY_BUTTON_3`, a hat becomes `KEY_HAT_LEFT`, an axis becomes
/// `KEY_AXIS_1_DOWN`. The mapping files are written in that vocabulary and are
/// carried over unchanged, so this layer must speak it exactly.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'pipeline.dart';

// SDL2 constants, from SDL_events.h and SDL_joystick.h.
const int _sdlInitJoystick = 0x00000200;
const int _sdlEnable = 1;

const int _eventJoyAxisMotion = 0x600;
const int _eventJoyHatMotion = 0x602;
const int _eventJoyButtonDown = 0x603;
const int _eventJoyButtonUp = 0x604;
const int _eventJoyDeviceAdded = 0x605;
const int _eventJoyDeviceRemoved = 0x606;

const int _hatCentered = 0x00;
const int _hatUp = 0x01;
const int _hatRight = 0x02;
const int _hatDown = 0x04;
const int _hatLeft = 0x08;

/// How often the event queue is drained. 50ms is the Qt build's interval; a
/// button press is a physical event lasting far longer than that, and polling
/// faster only burns cycles.
const Duration pollInterval = Duration(milliseconds: 50);

/// Where an analogue stick starts counting as a direction, and where it stops.
///
/// **Two thresholds, not one, and that is the whole trick.** A single threshold
/// sitting at one value means a stick resting near it chatters — press, release,
/// press, release, as many times a second as you poll. Requiring a firm push to
/// engage and a near-return to centre to disengage is what makes a thumbstick
/// usable as a D-pad. Both numbers are the Qt build's.
const int axisOnThreshold = 16384;
const int axisOffThreshold = 10000;

/// SDL's event union is 56 bytes. Over-allocated a little so a future field
/// cannot write past the end of it.
const int _eventBufferBytes = 128;

final class _JoyButtonEvent extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int timestamp;
  @Int32()
  external int which;
  @Uint8()
  external int button;
  @Uint8()
  external int state;
  @Uint8()
  external int padding1;
  @Uint8()
  external int padding2;
}

final class _JoyAxisEvent extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int timestamp;
  @Int32()
  external int which;
  @Uint8()
  external int axis;
  @Uint8()
  external int padding1;
  @Uint8()
  external int padding2;
  @Uint8()
  external int padding3;
  @Int16()
  external int value;
  @Uint16()
  external int padding4;
}

final class _JoyHatEvent extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int timestamp;
  @Int32()
  external int which;
  @Uint8()
  external int hat;
  @Uint8()
  external int value;
  @Uint8()
  external int padding1;
  @Uint8()
  external int padding2;
}

final class _JoyDeviceEvent extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int timestamp;
  @Int32()
  external int which;
}

/// The handful of SDL functions this needs.
class _Sdl {
  _Sdl(this.library)
    : init = library.lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'SDL_Init',
      ),
      quit = library.lookupFunction<Void Function(), void Function()>(
        'SDL_Quit',
      ),
      setHint = library
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
            int Function(Pointer<Utf8>, Pointer<Utf8>)
          >('SDL_SetHint'),
      getError = library
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'SDL_GetError',
          ),
      joystickEventState = library
          .lookupFunction<Int32 Function(Int32), int Function(int)>(
            'SDL_JoystickEventState',
          ),
      numJoysticks = library
          .lookupFunction<Int32 Function(), int Function()>('SDL_NumJoysticks'),
      joystickOpen = library
          .lookupFunction<
            Pointer<Void> Function(Int32),
            Pointer<Void> Function(int)
          >('SDL_JoystickOpen'),
      joystickClose = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('SDL_JoystickClose'),
      joystickInstanceId = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('SDL_JoystickInstanceID'),
      joystickName = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('SDL_JoystickName'),
      joystickNumButtons = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('SDL_JoystickNumButtons'),
      joystickNumAxes = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('SDL_JoystickNumAxes'),
      pollEvent = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('SDL_PollEvent');

  final DynamicLibrary library;
  final int Function(int flags) init;
  final void Function() quit;
  final int Function(Pointer<Utf8>, Pointer<Utf8>) setHint;
  final Pointer<Utf8> Function() getError;
  final int Function(int) joystickEventState;
  final int Function() numJoysticks;
  final Pointer<Void> Function(int) joystickOpen;
  final void Function(Pointer<Void>) joystickClose;
  final int Function(Pointer<Void>) joystickInstanceId;
  final Pointer<Utf8> Function(Pointer<Void>) joystickName;
  final int Function(Pointer<Void>) joystickNumButtons;
  final int Function(Pointer<Void>) joystickNumAxes;
  final int Function(Pointer<Void>) pollEvent;

  String get error => getError().toDartString();

  /// Tried in order. The versioned name is what is actually installed; the
  /// unversioned one only exists with the development package. On this machine
  /// the provider is `sdl2-compat`, which implements the SDL2 ABI on top of
  /// SDL3 — the joystick surface used here is identical either way.
  static const candidates = [
    'libSDL2-2.0.so.0',
    'libSDL2.so',
    'libSDL2-2.0.so',
  ];

  static _Sdl? open() {
    for (final name in candidates) {
      try {
        return _Sdl(DynamicLibrary.open(name));
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }
}

/// Polls SDL for joystick events and reports them as key codes.
class Gamepads {
  Gamepads({required this.onInput});

  /// Where events go: the source is the joystick's own name, which is what the
  /// mapping files' `idmatcher` is written against — hence a file per controller
  /// *and* per operating system.
  final void Function(String source, String keycode, KeyState state) onInput;

  _Sdl? _sdl;
  Timer? _poll;
  Pointer<Uint8>? _event;

  /// Instance id → (handle, name). The name is cached because SDL frees it when
  /// the device closes, and a disconnect arrives *after* the device is gone.
  final Map<int, (Pointer<Void>, String)> _joysticks = {};

  /// Which way each axis is currently pushed, keyed by joystick and axis. The Qt
  /// build keyed this on the axis alone, so two pads shared one state.
  final Map<(int, int), bool> _axisUp = {};

  /// Axes whose resting position has been established.
  ///
  /// **A trigger rests at full deflection, not at zero.** L2 and R2 report
  /// -32768 when untouched, which is well past the threshold, so the first event
  /// from each one looks exactly like someone slamming it to the stop. The
  /// original emitted that, and a map that bound `KEY_AXIS_4_UP` would fire it
  /// once on every launch for a button nobody pressed.
  ///
  /// So the first sighting of an axis records where it sits and says nothing. The
  /// cost is that a stick already held when the application starts is ignored
  /// until it is released, which is the better of the two mistakes.
  final Set<(int, int)> _axisSeen = {};

  /// The last non-centred hat direction, per joystick. SDL reports a hat's
  /// release as "centred" with no direction attached, so the direction to send a
  /// key-up for has to be remembered — and without that key-up, a held D-pad
  /// keeps repeating after it is let go.
  final Map<(int, int), String> _lastHat = {};

  bool get running => _poll != null;

  /// True if SDL came up. False is a normal outcome — a machine with no SDL
  /// installed still has a keyboard, and this must not be fatal.
  bool start() {
    if (running) return true;
    if (!Platform.isLinux) return false;

    final sdl = _Sdl.open();
    if (sdl == null) {
      debugPrint('input: no SDL2 library found; gamepads unavailable');
      return false;
    }

    if (sdl.init(_sdlInitJoystick) < 0) {
      debugPrint('input: SDL_Init failed — ${sdl.error}');
      return false;
    }

    // Lets the pad be read while the window is not focused. On a television there
    // is frequently nothing else to focus, and a pad that only works when the
    // compositor agrees is a pad that looks broken.
    //
    // **Reading is not the same as acting.** In Game Mode Steam's menu opens over
    // Glassfin and is driven by the same pad, so InputEngine's FocusGate drops
    // those presses while something else has input — otherwise the X that picks
    // "Exit game" also picks a card in Glassfin. Under gamescope that signal comes
    // from GamescopeFocus, because the window itself is never told.
    final hint = 'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS'.toNativeUtf8();
    final one = '1'.toNativeUtf8();
    sdl.setHint(hint, one);
    calloc.free(hint);
    calloc.free(one);

    sdl.joystickEventState(_sdlEnable);

    _sdl = sdl;
    _event = calloc<Uint8>(_eventBufferBytes);
    _refreshJoysticks();

    // **A timer on this isolate, not a thread.** The Qt build needed a dedicated
    // thread because `SDL_PollEvent` sat in a loop there; here the loop is the
    // timer, each tick drains whatever has queued up and returns immediately.
    // Polling costs one non-blocking call every 50ms, which is not worth an
    // isolate and a port to avoid.
    _poll = Timer.periodic(pollInterval, (_) => _drain());
    return true;
  }

  void stop() {
    _poll?.cancel();
    _poll = null;

    final sdl = _sdl;
    if (sdl != null) {
      for (final (handle, _) in _joysticks.values) {
        sdl.joystickClose(handle);
      }
      sdl.quit();
    }
    _joysticks.clear();
    _axisUp.clear();
    _axisSeen.clear();
    _lastHat.clear();

    final event = _event;
    if (event != null) calloc.free(event);
    _event = null;
    _sdl = null;
  }

  String _nameFor(int which) => _joysticks[which]?.$2 ?? 'unknown joystick';

  /// One tick of the poll loop.
  ///
  /// **Nothing a consumer does may escape into the timer.** An exception thrown
  /// here leaves the periodic timer unscheduled, so a single bad event
  /// permanently kills the pad while the keyboard carries on — which reads as "the
  /// controller stopped working" with nothing to connect it to the error that
  /// caused it. That happened: a stale focus node threw inside the traversal
  /// policy and took the whole poller with it.
  ///
  /// Reported and then dropped, because the alternative is worse. The queue is
  /// drained again in 50ms regardless.
  void _drain() {
    try {
      _pollOnce();
    } on Object catch (error, stack) {
      debugPrint('input: dropped a gamepad event — $error');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
    }
  }

  void _pollOnce() {
    final sdl = _sdl;
    final event = _event;
    if (sdl == null || event == null) return;

    while (sdl.pollEvent(event.cast()) != 0) {
      final type = event.cast<Uint32>().value;
      switch (type) {
        case _eventJoyButtonDown || _eventJoyButtonUp:
          final button = event.cast<_JoyButtonEvent>().ref;
          onInput(
            _nameFor(button.which),
            'KEY_BUTTON_${button.button}',
            type == _eventJoyButtonDown ? KeyState.down : KeyState.up,
          );

        case _eventJoyHatMotion:
          _onHat(event.cast<_JoyHatEvent>().ref);

        case _eventJoyAxisMotion:
          _onAxis(event.cast<_JoyAxisEvent>().ref);

        case _eventJoyDeviceAdded || _eventJoyDeviceRemoved:
          final device = event.cast<_JoyDeviceEvent>().ref;
          debugPrint(
            'input: joystick '
            '${type == _eventJoyDeviceAdded ? "added" : "removed"} '
            '(${device.which})',
          );
          _refreshJoysticks();
      }
    }
  }

  void _onHat(_JoyHatEvent hat) {
    final key = (hat.which, hat.hat);

    final direction = switch (hat.value) {
      _hatUp => 'KEY_HAT_UP',
      _hatDown => 'KEY_HAT_DOWN',
      _hatLeft => 'KEY_HAT_LEFT',
      _hatRight => 'KEY_HAT_RIGHT',
      // A diagonal, which no bundled map claims. Treated as a release so that a
      // held direction cannot be left stuck down by rolling the D-pad round.
      _ => null,
    };

    if (direction == null) {
      // Centred, or a diagonal. Release whatever was last pressed — SDL does not
      // say what is being released, so this is the only way to know.
      final last = _lastHat.remove(key);
      if (last != null) onInput(_nameFor(hat.which), last, KeyState.up);
      if (hat.value != _hatCentered) {
        // Genuinely a diagonal rather than a release; keep the state clean and
        // say so, because a map could reasonably want to handle it one day.
        if (kDebugMode) debugPrint('input: ignoring diagonal hat ${hat.value}');
      }
      return;
    }

    // A change of direction without passing through centre, which a thumb rolling
    // across the pad produces constantly.
    final last = _lastHat[key];
    if (last != null && last != direction) {
      onInput(_nameFor(hat.which), last, KeyState.up);
    }

    _lastHat[key] = direction;
    onInput(_nameFor(hat.which), direction, KeyState.down);
  }

  void _onAxis(_JoyAxisEvent axis) {
    final key = (axis.which, axis.axis);
    final magnitude = axis.value.abs();
    final up = axis.value < 0;
    final current = _axisUp[key];

    String code(bool isUp) => 'KEY_AXIS_${axis.axis}_${isUp ? "UP" : "DOWN"}';

    final firstSighting = _axisSeen.add(key);

    if (magnitude > axisOnThreshold) {
      if (current == null) {
        _axisUp[key] = up;
        // Already deflected the first time we look at it: that is where it lives,
        // not something that just happened.
        if (!firstSighting) {
          onInput(_nameFor(axis.which), code(up), KeyState.down);
        }
      } else if (current != up) {
        // Pushed hard the other way without crossing back through the dead zone.
        onInput(_nameFor(axis.which), code(current), KeyState.up);
        _axisUp[key] = up;
        onInput(_nameFor(axis.which), code(up), KeyState.down);
      }
      return;
    }

    if (magnitude < axisOffThreshold && current != null) {
      _axisUp.remove(key);
      onInput(_nameFor(axis.which), code(current), KeyState.up);
    }
    // Between the two thresholds: deliberately nothing. This is the hysteresis
    // band, and doing nothing in it is the point.
  }

  /// Re-enumerates after a connect or disconnect.
  void _refreshJoysticks() {
    final sdl = _sdl;
    if (sdl == null) return;

    for (final (handle, _) in _joysticks.values) {
      sdl.joystickClose(handle);
    }
    _joysticks.clear();
    // A reopened device may have a different instance id, so any remembered
    // direction now refers to nothing.
    _axisUp.clear();
    _axisSeen.clear();
    _lastHat.clear();

    final count = sdl.numJoysticks();
    for (var index = 0; index < count; index++) {
      final handle = sdl.joystickOpen(index);
      if (handle == nullptr) continue;

      final id = sdl.joystickInstanceId(handle);
      final name = sdl.joystickName(handle).toDartString();
      _joysticks[id] = (handle, name);

      // The name is the thing that decides which mapping file applies, so it is
      // worth a log line: "my pad does nothing" is almost always "no map claims
      // that name".
      debugPrint(
        'input: joystick $id "$name" — '
        '${sdl.joystickNumButtons(handle)} buttons, '
        '${sdl.joystickNumAxes(handle)} axes',
      );
    }
  }
}
