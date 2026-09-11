import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'design/tokens.dart';
import 'input/input_map_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      await windowManager.show();
      await windowManager.focus();
    },
  );

  // Before the first frame, because an application nobody can press a button in
  // has nothing to show. The files are small and read once; doing this here is
  // what lets everything downstream treat the mapping as simply present.
  final inputMaps = await loadInputMaps();

  runApp(GlassfinApp(inputMaps: inputMaps));
}
