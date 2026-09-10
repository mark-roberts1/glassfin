/// Choosing which audio and subtitle tracks to play.
///
/// Pure functions over a stream list, kept apart from the API client so they can
/// be tested directly. Ported from `glassfin_old/web/src/lib/jellyfin.ts`.
library;

import 'models.dart';

/// How subtitles should be chosen.
enum SubtitleMode {
  /// Never pick a subtitle track.
  off,

  /// Only pick a track marked forced — the signed dialogue in a film that is
  /// otherwise in your own language.
  forced,

  /// Pick the preferred language when it is there, and otherwise **leave
  /// subtitles off** rather than turning on a language nobody asked for.
  preferred,
}

/// Converts Jellyfin's absolute stream index into the ordinal mpv wants.
///
/// mpv addresses tracks by their position *among tracks of the same type*, not
/// by the absolute `MediaStream` index Jellyfin reports — a file whose second
/// audio track is stream 4 overall is `aid=2` to mpv. One-based, matching mpv's
/// own convention where 1 is the first audio track.
///
/// Returns -1 when the stream is not in the list, which mpv reads as "no track".
int relativeStreamIndex(
  List<MediaStream> streams,
  int absoluteIndex,
  StreamType type,
) {
  var position = 0;
  for (final stream in streams) {
    if (stream.type != type) continue;
    position += 1;
    if (stream.index == absoluteIndex) return position;
  }
  return -1;
}

bool _sameLanguage(MediaStream stream, String code) {
  final language = stream.language;
  return language != null && language.toLowerCase() == code.toLowerCase();
}

/// The preferred language if present, otherwise the server's default, otherwise
/// the first track.
///
/// Audio always resolves to *something* when the file has any audio at all —
/// unlike subtitles, silence is never the right answer.
MediaStream? chooseAudioStream(List<MediaStream> streams, String preferred) {
  final audio = streams.where((s) => s.type == StreamType.audio).toList();
  if (audio.isEmpty) return null;

  if (preferred.isNotEmpty) {
    for (final stream in audio) {
      if (_sameLanguage(stream, preferred)) return stream;
    }
  }
  for (final stream in audio) {
    if (stream.isDefault) return stream;
  }
  return audio.first;
}

/// Follows [mode] rather than guessing.
///
/// The [SubtitleMode.preferred] case deliberately returns null when the
/// preferred language is absent: turning on Hungarian subtitles because that is
/// all the file has would be worse than showing none.
MediaStream? chooseSubtitleStream(
  List<MediaStream> streams,
  SubtitleMode mode,
  String preferred,
) {
  if (mode == SubtitleMode.off) return null;

  final subtitles = streams.where((s) => s.type == StreamType.subtitle).toList();
  if (subtitles.isEmpty) return null;

  final inLanguage = preferred.isEmpty
      ? subtitles
      : subtitles.where((s) => _sameLanguage(s, preferred)).toList();

  MediaStream? firstWhere(bool Function(MediaStream) test) {
    for (final stream in inLanguage) {
      if (test(stream)) return stream;
    }
    return null;
  }

  if (mode == SubtitleMode.forced) {
    return firstWhere((s) => s.isForced);
  }

  // Forced first even in `preferred` mode: a forced track in the right language
  // is the one the film was authored to show.
  return firstWhere((s) => s.isForced) ??
      firstWhere((s) => s.isDefault) ??
      (inLanguage.isEmpty ? null : inLanguage.first);
}
