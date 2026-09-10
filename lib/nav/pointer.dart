/// Pointer mode, from `docs/ui-spec.md` §2.6.
///
/// **The default is pad**, because a television with no mouse must never show a
/// cursor sitting in the middle of a film. Pointer mode turns the cursor back on
/// and enables hover-to-focus, and any semantic action switches straight back.
///
/// The subtle part is what counts as "the mouse moved". A stationary cursor
/// still receives hover events whenever the content underneath it scrolls — and
/// spatial navigation scrolls content constantly. Treating those as movement
/// would knock a controller session into pointer mode every time the viewer
/// pressed Down, so only a **genuinely changed position** counts.
library;

import 'package:flutter/widgets.dart';

class PointerMode {
  PointerMode._();

  static final PointerMode instance = PointerMode._();

  /// True once a real mouse movement has been seen. Widgets listen to this, so
  /// it is a notifier rather than a plain flag.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  Offset? _lastPosition;

  /// Report a hover. Returns true if this was real movement rather than the
  /// content moving underneath a stationary cursor.
  bool noteMove(Offset position) {
    final last = _lastPosition;
    _lastPosition = position;
    if (last != null && last == position) return false;
    // The first hover of a session is not movement either: it fires as soon as
    // a window opens under wherever the pointer happens to be resting.
    if (last == null) return false;
    active.value = true;
    return true;
  }

  /// Any button press — remote, gamepad or keyboard — means the viewer has put
  /// the mouse down.
  void noteAction() {
    _lastPosition = null;
    active.value = false;
  }

  @visibleForTesting
  void reset() {
    _lastPosition = null;
    active.value = false;
  }
}
