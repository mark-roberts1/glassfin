/// A debug-only screenshot key.
///
/// GNOME on Wayland refuses `org.gnome.Shell.Screenshot` to unsandboxed callers,
/// so there is no way to look at the running interface from outside it. Rather
/// than describing the UI back and forth, **F12 captures the window to a PNG**.
///
/// Compiled out of release builds by the [kDebugMode] guards at both the key
/// handler and here, and it touches nothing the interface depends on: the
/// [RepaintBoundary] it needs is a no-op layer in the tree.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Wraps the root so the whole interface can be rasterised in one go.
final GlobalKey captureKey = GlobalKey();

/// Where captures land. Numbered, because a fixed name means pressing the key
/// four times leaves one file — which is exactly what happened the first time.
const String captureDirectory = '/tmp/glassfin-captures';

Future<void> captureWindow() async {
  if (!kDebugMode) return;
  try {
    final boundary =
        captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      debugPrint('glassfin: capture found no boundary');
      return;
    }
    // Captured at the device pixel ratio so what lands in the file is what the
    // panel actually shows, rather than a logical-pixel approximation of it.
    final image = await boundary.toImage(
      pixelRatio: WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return;

    final directory = Directory(captureDirectory);
    await directory.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('$captureDirectory/$stamp.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    debugPrint('glassfin: captured ${file.path}');
  } catch (error) {
    debugPrint('glassfin: capture failed: $error');
  }
}
