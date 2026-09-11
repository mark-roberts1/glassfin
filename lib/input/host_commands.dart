/// Actions prefixed `host:`, which never reach the interface.
///
/// In the Qt build these dispatched into registered native slots, and the list was
/// long: window control, display-mode switching, settings cycling, power
/// management, raw mpv commands, and a deliberate crash for testing. Most of that
/// list described machinery this rebuild does not have — there is no web view to
/// toggle, no page to reload, and the 867 lines of settings-description C++ that
/// `cycle_setting` drove were deleted on purpose.
///
/// What survives is what a keyboard shortcut in `keyboard.json` can still
/// sensibly ask for on a desktop. An unknown `host:` command is a debug line and
/// nothing else, because these names come from a data file that was written for a
/// different application and is carried over unchanged.
library;

import 'package:flutter/foundation.dart';

/// The prefix that marks an action as the host's rather than the interface's.
const String hostPrefix = 'host:';

class HostCommands {
  const HostCommands({this.fullscreen, this.minimize, this.quit});

  final VoidCallback? fullscreen;
  final VoidCallback? minimize;

  /// Ctrl+W and Ctrl+Q. Both `quit` and `close` land here; the Qt build
  /// distinguished them and nothing depended on the difference.
  final VoidCallback? quit;

  /// Runs [action], which must include the `host:` prefix. True if something
  /// happened.
  bool run(String action) {
    if (!action.startsWith(hostPrefix)) return false;

    // Arguments are split off and discarded. Every bundled command that takes
    // one — `cycle_setting main.alwaysOnTop`, `player <mpv command>` — belongs to
    // a subsystem that no longer exists, so parsing them would only make the
    // unsupported cases look supported.
    final command = action.substring(hostPrefix.length).split(' ').first;

    final handler = switch (command) {
      'fullscreen' => fullscreen,
      'minimize' => minimize,
      'quit' || 'close' => quit,
      _ => null,
    };

    if (handler == null) {
      if (kDebugMode) debugPrint('input: no host command "$command"');
      return false;
    }
    handler();
    return true;
  }
}
