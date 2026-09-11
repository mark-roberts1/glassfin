/// Getting the mapping files off disk and into an [InputMaps].
///
/// Split from `input_map.dart` so that the engine itself stays free of Flutter
/// and of the filesystem, and can be tested on strings.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'input_map.dart';

/// Loads the bundled maps, then lets the user's own overlay them.
///
/// The order is the whole point: a file in `~/.local/share/glassfin/inputmaps/`
/// claiming the same `idmatcher` as a bundled one replaces it, so a remote can be
/// remapped without a build. That was a documented feature of the Qt build and
/// stays one.
///
/// **Not ported: the filesystem watcher.** The original reloaded mappings the
/// moment a file changed, and also copied every bundled map into an `examples/`
/// directory so there was something to crib from. Both are conveniences for
/// editing maps by hand; neither is needed to *use* one, and a watcher means a
/// reload path through a running interface. Worth adding the day someone
/// actually sits down to write a map.
Future<InputMaps> loadInputMaps({Directory? userDirectory}) async {
  final maps = InputMaps(const []);

  for (final asset in await _bundledMapAssets()) {
    final text = await rootBundle.loadString(asset);
    _addParsed(maps, _fileName(asset), text, asset);
  }

  final directory = userDirectory ?? await _userMapDirectory();
  if (directory != null && directory.existsSync()) {
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      _addParsed(
        maps,
        _fileName(file.path),
        file.readAsStringSync(),
        file.path,
      );
    }
  }

  if (kDebugMode) {
    debugPrint('input: loaded ${maps.length} mapping files');
  }
  return maps;
}

void _addParsed(InputMaps maps, String id, String text, String where) {
  try {
    final file = InputMapFile.parse(id, text);
    // Null means no `idmatcher`, which is how a map is deliberately switched
    // off. Silent, exactly as before.
    if (file != null) maps.add(file);
  } on FormatException catch (error) {
    // Loud, because a map that does not parse is a map whose buttons silently
    // do nothing — and that is indistinguishable from a broken controller.
    debugPrint('input: ignoring $where — ${error.message}');
  }
}

/// Every bundled mapping file, from the asset manifest rather than a hardcoded
/// list — `assets/inputmaps/` is declared as a directory in pubspec.yaml, so
/// adding a map is adding a file.
Future<List<String>> _bundledMapAssets() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets =
      manifest
          .listAssets()
          .where(
            (asset) =>
                asset.startsWith('assets/inputmaps/') &&
                asset.endsWith('.json'),
          )
          .toList()
        // Sorted so that "which map wins" is the same on every machine. Two maps
        // claiming one `idmatcher` is a collision either way, but a
        // *reproducible* collision can at least be diagnosed.
        ..sort();
  return assets;
}

Future<Directory?> _userMapDirectory() async {
  try {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/inputmaps');
  } on Object catch (error) {
    debugPrint('input: no user mapping directory — $error');
    return null;
  }
}

String _fileName(String path) => path.split('/').last;
