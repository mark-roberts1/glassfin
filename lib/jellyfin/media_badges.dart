/// What Detail shows under a title: resolution, dynamic range, codec and
/// channels.
///
/// **This is not trivia on the target hardware.** HEVC at 4K is exactly the
/// combination that has to come off six CPU cores when hardware decode is not
/// available, so seeing it before pressing Play is genuinely useful — which is
/// why it sits above the fold rather than in a submenu.
///
/// Ported from `glassfin_old/web/src/lib/mediainfo.ts`.
library;

import 'package:flutter/foundation.dart';

import 'models.dart';

@immutable
class MediaBadges {
  const MediaBadges({
    required this.video,
    required this.audio,
    required this.subtitleLanguages,
  });

  /// Solid inverted chips: resolution, range, codec.
  final List<String> video;

  /// Quiet outlined chips: codec and channel layout of the default track.
  final List<String> audio;

  /// Distinct language codes, in the order the streams appear.
  final List<String> subtitleLanguages;

  bool get isEmpty => video.isEmpty && audio.isEmpty;
}

MediaBadges mediaBadges(Item item) {
  final streams = item.mediaSources.isEmpty
      ? const <MediaStream>[]
      : item.mediaSources.first.mediaStreams;

  final video = _firstWhere(streams, (s) => s.type == StreamType.video);
  // The default audio track is the one that will actually play, so it is the
  // one worth describing; falling back to the first covers files that mark none.
  final audio =
      _firstWhere(streams, (s) => s.type == StreamType.audio && s.isDefault) ??
      _firstWhere(streams, (s) => s.type == StreamType.audio);

  final languages = <String>[];
  for (final stream in streams) {
    final language = stream.language;
    if (stream.type != StreamType.subtitle) continue;
    if (language == null || language.isEmpty) continue;
    if (!languages.contains(language)) languages.add(language);
  }

  return MediaBadges(
    video: video == null
        ? const []
        : [
            ?resolutionLabel(video),
            ?rangeLabel(video),
            ?codecLabel(video.codec),
          ],
    audio: audio == null
        ? const []
        : [?codecLabel(audio.codec), ?channelLabel(audio)],
    subtitleLanguages: languages,
  );
}

/// Banded by height rather than width, because anamorphic and letterboxed
/// sources make width a poor proxy for what the decoder has to do.
String? resolutionLabel(MediaStream video) {
  final height = video.height ?? 0;
  if (height >= 2000) return '4K';
  if (height >= 1400) return '1440p';
  if (height >= 1000) return '1080p';
  if (height >= 700) return '720p';
  return height > 0 ? 'SD' : null;
}

String? rangeLabel(MediaStream video) => switch (video.videoRangeType) {
  'DOVI' || 'DOVIWithHDR10' => 'Dolby Vision',
  'HDR10' => 'HDR10',
  'HDR10Plus' => 'HDR10+',
  'HLG' => 'HLG',
  _ => null,
};

/// Codec names as they are written, not as the container spells them.
String? codecLabel(String? codec) {
  if (codec == null || codec.isEmpty) return null;
  return switch (codec.toLowerCase()) {
    'h264' => 'H.264',
    'hevc' || 'h265' => 'HEVC',
    'av1' => 'AV1',
    'vp9' => 'VP9',
    'mpeg2video' => 'MPEG-2',
    'eac3' => 'E-AC-3',
    'ac3' => 'AC-3',
    'truehd' => 'TrueHD',
    'dts' => 'DTS',
    'dtshd' => 'DTS-HD',
    'aac' => 'AAC',
    'flac' => 'FLAC',
    'opus' => 'Opus',
    'mp3' => 'MP3',
    // An unknown codec is still worth showing; upper case at least reads as a
    // deliberate label rather than as a leaked field name.
    _ => codec.toUpperCase(),
  };
}

String? channelLabel(MediaStream audio) {
  final layout = audio.channelLayout;
  if (layout != null && layout.isNotEmpty) return layout.toUpperCase();
  return switch (audio.channels) {
    1 => 'Mono',
    2 => 'Stereo',
    6 => '5.1',
    8 => '7.1',
    final int count => '${count}ch',
    null => null,
  };
}

MediaStream? _firstWhere(
  List<MediaStream> streams,
  bool Function(MediaStream) test,
) {
  for (final stream in streams) {
    if (test(stream)) return stream;
  }
  return null;
}
