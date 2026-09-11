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
    // the same keys have to move between its buttons instead — otherwise the
    // row is visible and unreachable, which is the dead end the couch bar
    // exists to prevent.
    //
    // The scrubber is the exception, and deliberately so: it is shaped like a
    // slider, so left and right seek while it holds focus.
    if (_inTransportRow) return onNavigate(action);

    if (action == InputAction.up || action == InputAction.menu) {
      onOpenMenu?.call();
      return true;
    }

    switch (action) {
      case InputAction.cycleAudio:
        playback.cycleAudio();
      case InputAction.cycleSubtitles:
        playback.cycleSubtitles();
      case InputAction.toggleSubtitles:
        playback.toggleSubtitles();

      case InputAction.playPause ||
          InputAction.select ||
          InputAction.play ||
          InputAction.pause:
        playback.togglePause();

      case InputAction.back || InputAction.stop || InputAction.exit:
        playback.stop();

      case InputAction.seekForward || InputAction.right:
        playback.seekBy(seekStep);

      case InputAction.seekBackward || InputAction.left:
        playback.seekBy(-seekStep);

      // A pad's right thumbstick and a remote's volume keys. Note these are
      // *not* reachable by direction — the volume bar is deliberately not
      // focusable, because left and right in the transport row belong to moving
      // between its buttons. This is how a controller reaches volume at all.
      case InputAction.increaseVolume:
        playback.setVolume(playback.volume + volumeStep);

      case InputAction.decreaseVolume:
        playback.setVolume(playback.volume - volumeStep);

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

/// Whether focus is on one of the transport's buttons, as opposed to the
/// scrubber, the picture, or a screen hidden behind the film.
bool get _inTransportRow {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return false;
  final group = NavRegistry.instance.infoFor(focused)?.group;
  return group == transportGroup || group == transportTopGroup;
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
