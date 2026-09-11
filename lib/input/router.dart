/// **The single place input enters the application.**
///
/// The most load-bearing rule in the project, and the easiest to erode: no
/// widget adds its own global key listener. Everything arrives here, and the
/// playback/navigation split is **total** — while a film is playing this returns
/// before navigation is ever consulted, so the transport owns the controller and
/// nothing underneath can steal a button.
///
/// Ported from `route()` in `glassfin_old/web/src/App.svelte`; see
/// `docs/ui-spec.md` §0.
library;

import 'package:flutter/widgets.dart';

import '../components/transport.dart';
import '../nav/pointer.dart';
import '../nav/registry.dart';
import '../playback/controller.dart';
import 'actions.dart';

/// What the router should do about actions it does not handle itself.
typedef NavigationHandler = bool Function(InputAction action);

class InputRouter {
  const InputRouter({
    required this.playback,
    required this.onNavigate,
    this.menuOpen = false,
    this.onOpenMenu,
    this.onCloseMenu,
    this.settingsOpen = false,
    this.onCloseSettings,
    this.onSearch,
    this.onHome,
    this.onBack,
  });

  /// Null before sign-in, where there is no player yet but the keyboard still
  /// has to reach navigation.
  final PlaybackController? playback;

  /// Directional movement and select, once the playback branch has declined.
  final NavigationHandler onNavigate;

  /// Whether the track menu is showing. While it is, Back closes it rather than
  /// stopping the film, and directions move **inside** it.
  final bool menuOpen;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onCloseMenu;

  /// The gear popover. Modal like the track menu: Back closes it.
  final bool settingsOpen;
  final VoidCallback? onCloseSettings;

  final VoidCallback? onSearch;
  final VoidCallback? onHome;

  /// Pop the route stack. Returns false when there is nothing to pop.
  final bool Function()? onBack;

  /// Returns true if the action was consumed.
  bool handle(InputAction action) {
    // Any semantic action puts the interface back in pad mode, which hides the
    // cursor again and stops hover from stealing focus out from under a D-pad.
    PointerMode.instance.noteAction();

    final player = playback;
    if (player != null && player.isPlaying) {
      // Any button at all revives the transport: the overlay is how the viewer
      // knows the application is alive.
      player.nudgeChrome();
      return _duringPlayback(player, action);
    }
    return _duringNavigation(action);
  }

  /// Priority here is deliberate, and **the order is the behaviour**:
  /// menu → skip offer → open-menu → track cycling → transport.
  ///
  /// So `select` means "take the skip" when one is offered and "pause"
  /// otherwise, because a skip prompt is on screen and pressing the obvious
  /// button should do the obvious thing.
  bool _duringPlayback(PlaybackController playback, InputAction action) {
    // Either menu is modal over the film: while one is up, the only thing that
    // reaches the transport is the button that closes it.
    if (settingsOpen) {
      if (action == InputAction.back ||
          action == InputAction.exit ||
          action == InputAction.menu) {
        onCloseSettings?.call();
        return true;
      }
      return onNavigate(action);
    }

    if (menuOpen) {
      if (action == InputAction.back ||
          action == InputAction.exit ||
          action == InputAction.menu) {
        onCloseMenu?.call();
        return true;
      }
      return onNavigate(action);
    }

    if (playback.skip != null &&
        (action == InputAction.select || action == InputAction.playPause)) {
      playback.takeSkip();
      return true;
    }

    // **The transport is a toolbar, and the picture is not.**
    //
    // With the chrome down there is nothing on screen to move between, so the
    // directions mean what they mean on any player: left and right seek, up
    // reveals the tracks. With the chrome up, focus is inside the transport and
    // the same keys have to move between its rows and buttons instead —
    // otherwise a control is visible and unreachable, which is the dead end the
    // couch bar exists to prevent.
    //
    // **Only the directions and select are positional.** Everything else — back,
    // stop, play/pause, the track cycling, volume — belongs to the transport
    // wherever focus happens to be sitting. Handing those to navigation too is
    // how Back stopped working the moment the chrome came up: `moveFocus` has no
    // case for it, so it returned false and the film carried on.
    // **A scan has to be stoppable by the obvious buttons**, and it has to be
    // stoppable before they mean anything else. While one is running the film is
    // travelling on its own, so OK and play/pause mean "stop here and carry on"
    // rather than what they usually mean — and a direction means "stop, then move
    // the way I asked".
    if (playback.scanning) {
      switch (action) {
        case InputAction.select ||
            InputAction.playPause ||
            InputAction.play ||
            InputAction.pause:
          playback.endScan();
          return true;

        case InputAction.up ||
            InputAction.down ||
            InputAction.left ||
            InputAction.right ||
            InputAction.menu ||
            InputAction.seekForward ||
            InputAction.seekBackward:
          playback.endScan();
          // Falls through to the ordinary handling below, so the direction that
          // stopped the scan also does its usual job. Pressing Left to stop and
          // then having to press it again would feel broken.
          break;

        case InputAction.rewind || InputAction.fastForward:
          // Doubling, or turning round. Handled below.
          break;

        default:
          break;
      }
    }

    final scope = _focusedOverFilm;

    switch (action) {
      case InputAction.up || InputAction.down:
        // Within the chrome, vertical movement crosses its rows — the title bar,
        // the skip offer, the scrub bar, the controls. This is what was missing:
        // anything not recognised above reached the catch-all below and was
        // swallowed, so there was no way off it.
        if (scope != null && onNavigate(action)) return true;
        // Past the top of the chrome, or with the chrome down, Up reveals the
        // tracks. Down has nothing above the picture to reach.
        if (action == InputAction.up) onOpenMenu?.call();
        return true;

      case InputAction.left || InputAction.right:
        // The scrubber is the exception, and deliberately so: it is shaped like a
        // slider, so left and right seek while it holds focus rather than moving
        // off it.
        if (scope == _OverFilm.controls) return onNavigate(action);
        playback.seekBy(action == InputAction.right ? seekStep : -seekStep);
        return true;

      case InputAction.select:
        // Presses whatever has focus; pauses when nothing in the chrome does.
        if (scope != null) return onNavigate(action);
        playback.togglePause();
        return true;

      default:
        break;
    }

    // Everything below is the transport's regardless of focus.
    switch (action) {
      case InputAction.menu:
        onOpenMenu?.call();

      case InputAction.cycleAudio:
        playback.cycleAudio();
      case InputAction.cycleSubtitles:
        playback.cycleSubtitles();
      case InputAction.toggleSubtitles:
        playback.toggleSubtitles();

      case InputAction.playPause || InputAction.play || InputAction.pause:
        playback.togglePause();

      // **Wherever focus is.** A pad's Circle while the chrome is up is still
      // "leave this film", not "move the highlight".
      case InputAction.back || InputAction.stop || InputAction.exit:
        playback.stop();

      case InputAction.seekForward:
        playback.seekBy(seekStep);

      case InputAction.seekBackward:
        playback.seekBy(-seekStep);

      // A pad's shoulder buttons. Each press doubles the rate; see
      // [PlaybackController.scan].
      case InputAction.fastForward:
        playback.scan(1);

      case InputAction.rewind:
        playback.scan(-1);

      // A pad's right thumbstick and a remote's volume keys. Note these are
      // *not* reachable by direction — the volume bar is deliberately not
      // focusable, because left and right in the transport row belong to moving
      // between its buttons. This is how a controller reaches volume at all.
      case InputAction.increaseVolume:
        playback.setVolume(playback.volume + volumeStep);

      case InputAction.decreaseVolume:
        playback.setVolume(playback.volume - volumeStep);

      case InputAction.mute:
        playback.toggleMute();

      default:
        // Everything else is swallowed rather than passed on. This is the total
        // split: up, down, home and search must not navigate a screen the
        // viewer cannot see.
        return true;
    }
    return true;
  }

  bool _duringNavigation(InputAction action) {
    switch (action) {
      case InputAction.search:
        onSearch?.call();
        return true;
      case InputAction.home:
        onHome?.call();
        return true;
      case InputAction.back:
        return onBack?.call() ?? false;
      default:
        return onNavigate(action);
    }
  }
}

/// What kind of thing over the film has focus, if any.
///
/// Everything here answers **up and down the same way** — they move between the
/// things drawn over the picture, and a group left out of this list is a group you
/// cannot navigate away from. That was the bug twice over: the scrub bar, and then
/// the skip offer, both read as "not part of the player", so pressing Down on
/// either did nothing at all.
///
/// They differ only on the horizontal, and only because of what they look like.
enum _OverFilm {
  /// A row of buttons. Every direction moves between them, because that is what a
  /// toolbar does.
  controls,

  /// The scrub bar and the skip offer. Up and down leave; left and right seek,
  /// because the scrubber is shaped like a slider and the skip offer is a single
  /// button with nothing beside it to move to.
  seeking,
}

_OverFilm? get _focusedOverFilm {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return null;
  return switch (NavRegistry.instance.infoFor(focused)?.group) {
    transportGroup || transportTopGroup => _OverFilm.controls,
    transportScrubGroup || skipGroup => _OverFilm.seeking,
    _ => null,
  };
}

/// Turns [InputAction] directions into focus movement.
///
/// Kept separate from the router so that the router stays a pure decision about
/// *who* gets the action, and this stays the decision about what a direction
/// means.
bool moveFocus(BuildContext context, InputAction action) {
  final direction = switch (action) {
    InputAction.up => TraversalDirection.up,
    InputAction.down => TraversalDirection.down,
    InputAction.left => TraversalDirection.left,
    InputAction.right => TraversalDirection.right,
    _ => null,
  };

  if (direction != null) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return NavRegistry.instance.focusSomethingSensible();
    return FocusTraversalGroup.of(context).inDirection(primary, direction);
  }

  if (action == InputAction.select) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final onSelect = NavRegistry.instance.infoFor(primary)?.onSelect;
    if (onSelect == null) return false;
    onSelect();
    return true;
  }

  return false;
}
