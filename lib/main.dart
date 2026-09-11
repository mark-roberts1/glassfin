import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'design/tokens.dart';
import 'input/input_map_loader.dart';

/// How the window should open.
///
/// The desktop entry offers Fullscreen and Windowed as launcher actions, and the
/// Steam shortcut is the reason the first one matters: Big Picture hands over a
/// television, and starting in a window there means the viewer's first act is to
/// find a keyboard. The flags are read here rather than stored as a setting
/// because they describe *this* launch.
///
/// Anything else on the command line is ignored rather than refused. A desktop
/// shell or a Flatpak wrapper may pass arguments of its own, and a media player
/// that will not start because it was handed an unexpected token is a worse
/// outcome than one that shrugs.
bool startFullscreen(List<String> args) {
  // Last one wins, so `--fullscreen --windowed` does what it reads like.
  var fullscreen = false;
  for (final arg in args) {
    if (arg == '--fullscreen') fullscreen = true;
    if (arg == '--windowed') fullscreen = false;
  }
  return fullscreen;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final fullscreen = startFullscreen(args);

  // Loads libmpv. Everything in lib/playback depends on this having run.
  MediaKit.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(1280, 720),
      center: true,
      title: 'Glassfin',
      // Painted before the first frame, so starting the application in a dark
      // room does not flash white.
      backgroundColor: GlassfinTokens.dark.ground,
    ),
    () async {
      // Before `show`, so the window is never briefly a 1280×720 box in the
      // middle of a television.
      if (fullscreen) await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  // Before the first frame, because an application nobody can press a button in
  // has nothing to show. The files are small and read once; doing this here is
  // what lets everything downstream treat the mapping as simply present.
  final inputMaps = await loadInputMaps();

  // The window is already fullscreen at this point, so the application has to be
  // told — otherwise its own idea of the state is wrong, and the first press of
  // the fullscreen button would try to enter it again rather than leave.
  runApp(GlassfinApp(inputMaps: inputMaps, fullscreen: fullscreen));
}
