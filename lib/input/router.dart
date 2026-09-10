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

import '../nav/registry.dart';
import '../playback/controller.dart';
import 'actions.dart';

/// What the router should do about actions it does not handle itself.
typedef NavigationHandler = bool Function(InputAction action);

class InputRouter {
  const InputRouter({
    required this.playback,
    required this.onNavigate,
    this.onSearch,
    this.onHome,
    this.onBack,
  });

  final PlaybackController playback;

  /// Directional movement and select, once the playback branch has declined.
  final NavigationHandler onNavigate;

  final VoidCallback? onSearch;
  final VoidCallback? onHome;

  /// Pop the route stack. Returns false when there is nothing to pop.
  final bool Function()? onBack;

  /// Returns true if the action was consumed.
  bool handle(InputAction action) {
    if (playback.isPlaying) {
      // Any button at all revives the transport: the overlay is how the viewer
      // knows the application is alive.
      playback.nudgeChrome();
      return _duringPlayback(action);
    }
    return _duringNavigation(action);
  }

  /// Priority here is deliberate, and the order is the behaviour.
  ///
  /// `select` means "take the skip" when one is offered and "pause" otherwise,
  /// because a skip prompt is on screen and pressing the obvious button should
  /// do the obvious thing.
  bool _duringPlayback(InputAction action) {
    if (playback.skip != null &&
        (action == InputAction.select || action == InputAction.playPause)) {
      playback.takeSkip();
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
