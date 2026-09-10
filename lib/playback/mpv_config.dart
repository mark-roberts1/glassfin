/// Settings → mpv properties.
///
/// media_kit *is* libmpv, and `NativePlayer.setProperty()` reaches the same
/// property interface the Qt build used, so this is a direct port of
/// `glassfin_old/src/player/PlayerComponent.cpp` — the *set of properties and
/// the reasoning*, not the code.
///
/// Deliberately pure: these functions take settings and return a property map,
/// so every rule below can be tested without a player, a file, or a sound card.
/// Several of them were learned by shipping to people with receivers, and they
/// look arbitrary until they are written down.
///
/// See `docs/native-audit.md` §2.
library;

import '../settings/audio_settings.dart';
import '../settings/subtitle_appearance.dart';
import '../settings/video_settings.dart';

/// Properties set once, when the player is created.
///
/// Most of mpv's defaults are right; these are the ones that are not, and each
/// was arrived at the hard way.
Map<String, String> initProperties() => {
  // **Load-bearing for Jellyfin.** MKV transcodes start at a non-zero
  // timestamp; left to itself mpv rebases them to zero, and every position
  // Glassfin reports back to the server is then wrong by the offset — resume
  // points land minutes from where the viewer stopped.
  'demuxer-mkv-probe-start-time': 'no',

  // mpv's own default is `auto`, which disables probing for HLS — and HLS is
  // exactly what a Jellyfin transcode delivers.
  'demuxer-lavf-probe-info': 'yes',

  // Don't abort playback because a sound card would not open. Losing audio is
  // bad; losing the film as well is worse, and the application can say so.
  'audio-fallback-to-null': 'yes',

  // Don't let the decoder downmix behind our back — the passthrough and channel
  // layout logic below has to be the only thing deciding that.
  'ad-lavc-downmix': 'no',

  // plex-media-player issue #736.
  'cache-seek-min': '5000',

  // Makes downmix behave the way Plex Home Theater did, which is the sound
  // people who have used one of these boxes for a decade expect.
  'audio-swresample-o': 'surround_mix_level=1',

  // Keeps the video output alive while idle. See the render-context note in
  // docs/native-audit.md §2 — in the Qt build, initialising before the render
  // context existed made this fail with "No render context set", and mpv then
  // silently never retried for the rest of the session.
  'force-window': 'yes',
};

/// The codecs each kind of connection can carry untouched.
///
/// Passthrough over a `basic` device — analogue, USB, Bluetooth — is not a thing
/// at all, which is why it has no entry.
const Map<AudioDeviceType, List<String>> passthroughCandidates = {
  AudioDeviceType.spdif: ['ac3', 'dts'],
  AudioDeviceType.hdmi: ['ac3', 'dts', 'eac3', 'dts-hd', 'truehd'],
};

/// The value for mpv's `audio-spdif`.
///
/// Two rules that are not guessable:
///
///  1. **`dts-hd` includes `dts`, but listing `dts` first can disable
///     `dts-hd`.** So `dts` is dropped whenever `dts-hd` is present, rather than
///     both being sent and the receiver quietly falling back to the lesser one.
///  2. A `basic` device passes nothing through, whatever the individual toggles
///     say — the toggles describe what the *receiver* supports, not what the
///     cable can carry.
List<String> passthroughCodecs(AudioSettings audio) {
  final candidates = passthroughCandidates[audio.deviceType];
  if (candidates == null) return const [];

  final enabled = candidates.where(audio.passthroughEnabled).toList();
  if (enabled.contains('dts-hd')) enabled.remove('dts');
  return enabled;
}

/// Audio properties.
///
/// The AC3 re-encoding filter is **not** here: it is added and removed by
/// command rather than set as a property, so it needs to know its own previous
/// state. See [shouldTranscodeToAc3] and [ac3FilterChange].
Map<String, String> audioProperties(AudioSettings audio) {
  // S/PDIF cannot carry multichannel PCM at all, so whatever the viewer picked,
  // stereo is the only honest answer. Anything more has to be passed through
  // compressed, or re-encoded — see [ac3FilterChange].
  final channels = audio.deviceType == AudioDeviceType.spdif
      ? AudioChannels.stereo
      : audio.channels;

  return {
    'audio-exclusive': audio.exclusive ? 'yes' : 'no',
    'audio-normalize-downmix': audio.normalize ? 'yes' : 'no',
    'audio-device': audio.device,
    'audio-spdif': passthroughCodecs(audio).join(','),
    'audio-channels': channels.id,
  };
}

/// Whether 5.1 should be re-encoded to AC3 on the way out.
///
/// This is how surround gets through an optical link at all: S/PDIF cannot carry
/// 5.1 PCM, but it can carry an AC3 bitstream, so with a receiver that decodes
/// AC3 the answer is to encode one on the fly. Only AC3 is implemented — DTS
/// encoding was never asked for often enough to justify it.
bool shouldTranscodeToAc3(AudioSettings audio) =>
    audio.deviceType == AudioDeviceType.spdif && audio.passthroughAc3;

/// The mpv command to reconcile the AC3 filter with [shouldTranscodeToAc3], or
/// null when it is already in the right state.
///
/// The filter is labelled `@ac3` so it can be removed by name; adding it twice
/// would stack two encoders.
List<String>? ac3FilterChange({required bool wanted, required bool current}) {
  if (wanted == current) return null;
  return wanted
      ? const ['af', 'add', '@ac3:lavcac3enc']
      : const ['af', 'remove', '@ac3'];
}

/// Video properties.
///
/// [displayFps] is **critical and easy to miss**: mpv is *told* the display's
/// refresh rate rather than left to guess, and it must be re-set on every
/// refresh-rate change and every load. Without it the `display-*` sync modes
/// misbehave in ways that look like a decoding problem.
Map<String, String> videoProperties(VideoSettings video, {double? displayFps}) {
  return {
    // `auto-copy` rather than `auto` by default — see [HardwareDecoding.copy].
    'hwdec': video.hardwareDecoding.mpvValue,
    'video-sync': video.videoSync.mpvValue,
    'deinterlace': video.deinterlace ? 'yes' : 'no',
    'demuxer-max-bytes': '${video.cacheMegabytes * 1024 * 1024}',
    'speed': '${video.defaultPlaybackSpeed}',
    if (displayFps != null) 'display-fps-override': '$displayFps',
  };
}

/// Which of the per-rate audio delays applies at [displayFps].
///
/// Some HDMI audio paths have a latency that depends on the refresh rate, so the
/// delay is picked from the *current* display rate. The half-hertz tolerance is
/// what makes 23.976 count as 24 — cinema content almost never runs at a round
/// number.
const double refreshRateTolerance = 0.5;

double audioDelayFor({
  required double? displayFps,
  required double normal,
  required double at24,
  required double at25,
  required double at50,
}) {
  if (displayFps == null) return normal;
  bool near(double rate) => (displayFps - rate).abs() < refreshRateTolerance;
  if (near(24)) return at24;
  if (near(25)) return at25;
  if (near(50)) return at50;
  return normal;
}

/// Subtitle appearance → mpv properties.
///
/// Every entry is omitted when its setting is unset, so mpv's own defaults
/// survive rather than being overwritten with something empty.
Map<String, String> subtitleProperties(SubtitleAppearance subtitles) {
  final properties = <String, String>{
    'sub-ass-style-overrides': subtitles.assScaleBorderAndShadow
        ? 'ScaledBorderAndShadow=yes'
        : 'ScaledBorderAndShadow=no',
  };

  final override = subtitles.assStyleOverride;
  if (override != null && override.isNotEmpty) {
    properties['sub-ass-override'] = override;
  }

  // mpv wants a scale factor, and 32 is what the settings call "Normal".
  final size = subtitles.size;
  if (size != null) properties['sub-scale'] = '${size / 32.0}';

  final font = subtitles.font;
  if (font != null && font.isNotEmpty) properties['sub-font'] = font;

  final color = subtitles.color;
  if (color != null && color.isNotEmpty) properties['sub-color'] = color;

  final borderColor = subtitles.borderColor;
  if (borderColor != null && borderColor.isNotEmpty) {
    properties['sub-border-color'] = borderColor;
  }

  final borderSize = subtitles.borderSize;
  if (borderSize != null) properties['sub-border-size'] = '$borderSize';

  final background = subtitleBackColor(
    subtitles.backgroundColor,
    subtitles.backgroundTransparency,
  );
  if (background != null) properties['sub-back-color'] = background;

  properties['sub-align-x'] = subtitles.alignX.name;
  // mpv's sub-pos is a percentage down the frame, so the bottom is 100. 10
  // rather than 0 for the top keeps the text off the very edge of the panel.
  properties['sub-pos'] = subtitles.alignY == SubtitleAlignY.bottom
      ? '100'
      : '10';

  return properties;
}

/// Combines `#RRGGBB` and a two-digit alpha byte into mpv's `#AARRGGBB`.
///
/// **The alpha is inserted at index 1**, immediately after the `#`. Appending it
/// instead produces `#RRGGBBAA`, which mpv reads as a completely different
/// colour rather than as an error, so the mistake is invisible until someone
/// looks at a subtitle.
String? subtitleBackColor(String? color, String? transparency) {
  if (color == null || color.isEmpty) return null;
  if (transparency == null || transparency.isEmpty) return null;
  if (!color.startsWith('#')) return null;
  return '#$transparency${color.substring(1)}';
}
