/// The Jellyfin `DeviceProfile`.
///
/// Ported from `glassfin_old/native/nativeshell.js:64-213`. This is the single
/// highest-value artifact in the whole port: it is what the client posts to
/// `/Items/{id}/PlaybackInfo`, and the *server* uses it to decide direct play
/// versus transcode. Getting it wrong produces silent transcodes of files that
/// would have played untouched, or direct plays of files that cannot be
/// rendered — and the reasoning behind each toggle is documented nowhere
/// upstream.
///
/// See `docs/native-audit.md` §1.
library;

import '../settings/playback_settings.dart';

/// Never bitrate-limit direct play. The client is on a LAN with a wire or a
/// good access point; a cap here would make the server transcode a file that
/// would have played perfectly.
const int _maxStaticBitrate = 1000000000;

const int _musicStreamingTranscodingBitrate = 1280000;

/// How far ahead of the reported position the server should assume the client
/// is. Jellyfin's own default for desktop clients.
const int _timelineOffsetSeconds = 5;

/// Builds the profile Jellyfin negotiates against.
Map<String, Object?> buildDeviceProfile(PlaybackSettings settings) => {
  'Name': 'Glassfin',
  'MaxStaticBitrate': _maxStaticBitrate,
  'MusicStreamingTranscodingBitrate': _musicStreamingTranscodingBitrate,
  'TimelineOffsetSeconds': _timelineOffsetSeconds,
  'TranscodingProfiles': _transcodingProfiles(settings),
  'DirectPlayProfiles': _directPlayProfiles(settings),
  'ResponseProfiles': const <Object?>[],
  'ContainerProfiles': const <Object?>[],
  'CodecProfiles': _codecProfiles(settings),
  'SubtitleProfiles': _subtitleProfiles,
};

/// Note the shape: **no `Container` and no `Codec` fields.**
///
/// In Jellyfin's profile semantics an unconstrained direct-play profile means
/// "anything". That is deliberate, and it is why there is no codec enumeration
/// anywhere in this file: the player is mpv, and **mpv's answer is all of it.**
/// media_kit is also libmpv, so the assumption carries over unchanged.
List<Map<String, Object?>> _directPlayProfiles(PlaybackSettings settings) => [
  {'Type': 'Audio'},
  {'Type': 'Photo'},
  if (!settings.alwaysForceTranscode) {'Type': 'Video'},
];

List<Map<String, Object?>> _transcodingProfiles(PlaybackSettings settings) => [
  {'Type': 'Audio'},
  {
    'Container': 'ts',
    'Type': 'Video',
    'Protocol': 'hls',
    'AudioCodec': 'aac,mp3,ac3,opus,vorbis',
    'VideoCodec': transcodeVideoCodecs(settings),
    'MaxAudioChannels': settings.channels == AudioChannels.stereo ? '2' : '6',
  },
  {'Container': 'jpeg', 'Type': 'Photo'},
];

/// The transcode target list. **The ordering is the preference signal to the
/// server** — it picks the first codec it can produce, so putting HEVC first is
/// how you ask for HEVC rather than merely permitting it.
String transcodeVideoCodecs(PlaybackSettings settings) {
  if (!settings.allowTranscodeToHevc) return 'h264,mpeg4,mpeg2video';
  return settings.preferTranscodeToH265
      ? 'h265,hevc,h264,mpeg4,mpeg2video'
      : 'h264,h265,hevc,mpeg4,mpeg2video';
}

/// Each entry here is a **deliberately unsatisfiable condition**. That is how
/// you force the server to transcode: you declare a requirement the stream
/// cannot meet, so direct play is ruled out and transcoding is the only path
/// left. They are not descriptions of what the client supports.
List<Map<String, Object?>> _codecProfiles(PlaybackSettings settings) => [
  // "Direct play only what is *not* Dolby Vision" — i.e. transcode all DoVi.
  if (settings.forceTranscodeDovi)
    _videoCondition(condition: 'NotEquals', property: 'VideoRangeType', value: 'DOVI'),

  // The mirror image: "direct play only SDR", so every HDR stream transcodes.
  if (settings.forceTranscodeHdr)
    _videoCondition(condition: 'Equals', property: 'VideoRangeType', value: 'SDR'),

  // 10-bit and deeper transcode; 8-bit direct plays.
  if (settings.forceTranscodeHi10p)
    _videoCondition(condition: 'LessThanEqual', property: 'VideoBitDepth', value: '8'),

  // `Equals Width 0` is the idiom for "this codec can never be direct-played":
  // no stream has width 0, so the condition never holds and the codec is always
  // transcoded. Both spellings of HEVC are listed because servers use either.
  if (settings.forceTranscodeHevc) ...[
    _videoCondition(codec: 'hevc', condition: 'Equals', property: 'Width', value: '0'),
    _videoCondition(codec: 'h265', condition: 'Equals', property: 'Width', value: '0'),
  ],
  if (settings.forceTranscodeAv1)
    _videoCondition(codec: 'av1', condition: 'Equals', property: 'Width', value: '0'),

  // Cap direct play at 1080p: anything larger fails both conditions and
  // transcodes down.
  if (settings.forceTranscode4k)
    {
      'Type': 'Video',
      'Conditions': [
        {'Condition': 'LessThanEqual', 'Property': 'Width', 'Value': '1920'},
        {'Condition': 'LessThanEqual', 'Property': 'Height', 'Value': '1080'},
      ],
    },
];

Map<String, Object?> _videoCondition({
  String? codec,
  required String condition,
  required String property,
  required String value,
}) => {
  'Type': 'Video',
  'Codec': ?codec,
  'Conditions': [
    {'Condition': condition, 'Property': property, 'Value': value},
  ],
};

/// Text formats can be sideloaded (`External`) or switched in place (`Embed`);
/// bitmap formats can only be `Embed`, because there is no URL mpv could fetch
/// a picture-based subtitle track from as a separate file.
const List<Map<String, String>> _subtitleProfiles = [
  {'Format': 'srt', 'Method': 'External'},
  {'Format': 'srt', 'Method': 'Embed'},
  {'Format': 'ass', 'Method': 'External'},
  {'Format': 'ass', 'Method': 'Embed'},
  {'Format': 'sub', 'Method': 'Embed'},
  {'Format': 'sub', 'Method': 'External'},
  {'Format': 'ssa', 'Method': 'Embed'},
  {'Format': 'ssa', 'Method': 'External'},
  {'Format': 'smi', 'Method': 'Embed'},
  {'Format': 'smi', 'Method': 'External'},
  {'Format': 'pgssub', 'Method': 'Embed'},
  {'Format': 'dvdsub', 'Method': 'Embed'},
  {'Format': 'dvbsub', 'Method': 'Embed'},
  {'Format': 'pgs', 'Method': 'Embed'},
];
