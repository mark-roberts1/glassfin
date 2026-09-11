/// The launcher actions in `org.glassfin.Glassfin.desktop`.
///
/// The desktop entry has offered `--fullscreen` and `--windowed` since it was
/// written, and for a while nothing parsed them — the two menu entries ran the
/// application and silently did nothing different. Worth a test precisely because
/// the contract lives in a file the Dart analyser never sees.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/main.dart';

void main() {
  test('no arguments means a window', () {
    expect(startFullscreen(const []), isFalse);
  });

  test('--fullscreen, as the desktop entry spells it', () {
    expect(startFullscreen(const ['--fullscreen']), isTrue);
  });

  test('--windowed is the default said out loud', () {
    expect(startFullscreen(const ['--windowed']), isFalse);
  });

  test('the last one wins', () {
    expect(startFullscreen(const ['--windowed', '--fullscreen']), isTrue);
    expect(startFullscreen(const ['--fullscreen', '--windowed']), isFalse);
  });

  test('anything else is ignored rather than refused', () {
    // A shell or a Flatpak wrapper may pass arguments of its own, and a media
    // player that will not start because it met an unexpected token is a worse
    // outcome than one that shrugs.
    expect(
      startFullscreen(const ['--enable-features=x', 'nonsense', '-f']),
      isFalse,
    );
    expect(startFullscreen(const ['nonsense', '--fullscreen']), isTrue);
  });
}
