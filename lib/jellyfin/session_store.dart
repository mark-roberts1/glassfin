/// Persistence for the signed-in session and this installation's device id.
///
/// The Qt build kept these in the web view's `localStorage`, which is what the
/// custom `glassfin://` URL scheme existed to make possible. That whole
/// mechanism is gone; a JSON file under the application's data directory does
/// the same job with none of the ceremony.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../settings/preferences.dart';
import '../settings/subtitle_appearance.dart';
import 'models.dart';

class SessionStore {
  SessionStore({Directory? directory}) : _override = directory;

  final Directory? _override;
  Directory? _resolved;

  /// `~/.local/share/glassfin` on Linux, matching the Qt build's own location.
  ///
  /// Nothing migrates from Jellyfin Desktop or Jellyfin Media Player,
  /// deliberately: their settings describe a different interface.
  Future<Directory> _directory() async {
    if (_override != null) return _override;
    return _resolved ??= await getApplicationSupportDirectory();
  }

  Future<File> _file(String name) async =>
      File('${(await _directory()).path}/$name');

  Future<Credentials?> readCredentials() async {
    final file = await _file('credentials.json');
    if (!file.existsSync()) return null;
    try {
      return Credentials.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } catch (_) {
      // A corrupt or half-written file should send the viewer to the sign-in
      // screen, not wedge the application on every launch.
      await file.delete();
      return null;
    }
  }

  Future<void> writeCredentials(Credentials credentials) async {
    final file = await _file('credentials.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(credentials.toJson()));
  }

  Future<void> clearCredentials() async {
    final file = await _file('credentials.json');
    if (file.existsSync()) await file.delete();
  }

  Future<Preferences> readPreferences() async {
    final file = await _file('preferences.json');
    if (!file.existsSync()) return const Preferences();
    try {
      return Preferences.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } catch (_) {
      // Defaults are always usable, so a damaged preferences file costs the
      // viewer their settings rather than the application.
      return const Preferences();
    }
  }

  Future<void> writePreferences(Preferences preferences) async {
    final file = await _file('preferences.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(preferences.toJson()));
  }

  /// Subtitle appearance is stored beside the preferences rather than inside
  /// them, because it is a different kind of setting: these are mpv's, and the
  /// spec promises they "apply to every video, and survive a restart".
  Future<SubtitleAppearance> readSubtitleAppearance() async {
    final file = await _file('subtitles.json');
    if (!file.existsSync()) return const SubtitleAppearance();
    try {
      return SubtitleAppearance.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } catch (_) {
      return const SubtitleAppearance();
    }
  }

  Future<void> writeSubtitleAppearance(SubtitleAppearance appearance) async {
    final file = await _file('subtitles.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(appearance.toJson()));
  }

  /// A stable identifier for this installation.
  ///
  /// Jellyfin uses it to keep sessions apart in the dashboard, so it must
  /// survive a restart — a fresh id each launch fills the server's session list
  /// with ghosts.
  Future<String> deviceId() async {
    final file = await _file('device-id');
    if (file.existsSync()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return existing;
    }
    final id = _randomId();
    await file.parent.create(recursive: true);
    await file.writeAsString(id);
    return id;
  }

  /// A UUIDv4. Generated once and then read from disk forever after.
  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 1
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
