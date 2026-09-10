/// The `audio` settings section.
///
/// The passthrough rules here are real domain knowledge from the Qt build — the
/// kind that is only learned by shipping to people with receivers. See
/// `docs/native-audit.md` §2 and `lib/playback/mpv_config.dart`, where they are
/// applied.
library;

import 'package:flutter/foundation.dart';

/// What the audio output is physically connected to.
///
/// This is not cosmetic: it decides which codecs may be passed through
/// untouched, and whether multichannel PCM is possible at all.
enum AudioDeviceType {
  /// Analogue, USB, Bluetooth — anything that just takes PCM. **No passthrough
  /// makes sense here.**
  basic,

  /// Optical or coaxial S/PDIF. Carries compressed AC3 and DTS, but **cannot
  /// carry multichannel PCM**, so the channel layout is forced to stereo and
  /// 5.1 has to be re-encoded to AC3 to get through.
  spdif,

  /// HDMI to a receiver. Everything is on the table.
  hdmi,
}

/// The channel layout to ask mpv for, and to advertise to the server.
enum AudioChannels {
  stereo('2.0'),
  surround51('5.1'),
  surround71('7.1');

  const AudioChannels(this.id);
  final String id;

  static AudioChannels fromId(String id) =>
      AudioChannels.values.firstWhere((c) => c.id == id, orElse: () => stereo);
}

@immutable
class AudioSettings {
  const AudioSettings({
    this.deviceType = AudioDeviceType.basic,
    this.channels = AudioChannels.stereo,
    this.device = 'auto',
    this.exclusive = false,
    this.normalize = true,
    this.passthroughAc3 = false,
    this.passthroughDts = false,
    this.passthroughEac3 = false,
    this.passthroughDtsHd = false,
    this.passthroughTrueHd = false,
  });

  final AudioDeviceType deviceType;
  final AudioChannels channels;

  /// mpv's `audio-device`, or `auto`.
  final String device;

  /// Take exclusive control of the device, bypassing the system mixer.
  final bool exclusive;

  /// `audio-normalize-downmix`.
  final bool normalize;

  final bool passthroughAc3;
  final bool passthroughDts;
  final bool passthroughEac3;
  final bool passthroughDtsHd;
  final bool passthroughTrueHd;

  /// Whether a given codec is enabled for passthrough, ignoring whether the
  /// device could carry it — [AudioDeviceType] decides that separately.
  bool passthroughEnabled(String codec) => switch (codec) {
    'ac3' => passthroughAc3,
    'dts' => passthroughDts,
    'eac3' => passthroughEac3,
    'dts-hd' => passthroughDtsHd,
    'truehd' => passthroughTrueHd,
    _ => false,
  };

  AudioSettings copyWith({
    AudioDeviceType? deviceType,
    AudioChannels? channels,
    String? device,
    bool? exclusive,
    bool? normalize,
    bool? passthroughAc3,
    bool? passthroughDts,
    bool? passthroughEac3,
    bool? passthroughDtsHd,
    bool? passthroughTrueHd,
  }) => AudioSettings(
    deviceType: deviceType ?? this.deviceType,
    channels: channels ?? this.channels,
    device: device ?? this.device,
    exclusive: exclusive ?? this.exclusive,
    normalize: normalize ?? this.normalize,
    passthroughAc3: passthroughAc3 ?? this.passthroughAc3,
    passthroughDts: passthroughDts ?? this.passthroughDts,
    passthroughEac3: passthroughEac3 ?? this.passthroughEac3,
    passthroughDtsHd: passthroughDtsHd ?? this.passthroughDtsHd,
    passthroughTrueHd: passthroughTrueHd ?? this.passthroughTrueHd,
  );
}
