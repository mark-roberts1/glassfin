/// The playback settings that shape the device profile and mpv's configuration.
///
/// Keys and defaults are carried over from the Qt build's `glassfin.conf`
/// (`video` and `audio` sections) rather than reinvented — a user upgrading
/// should not silently get different transcoding behaviour.
library;

import 'package:flutter/foundation.dart';

/// How many channels to ask the server for, and what to tell mpv.
enum AudioChannels {
  stereo('2.0'),
  surround51('5.1'),
  surround71('7.1');

  const AudioChannels(this.id);
  final String id;

  static AudioChannels fromId(String id) =>
      AudioChannels.values.firstWhere((c) => c.id == id, orElse: () => stereo);
}

/// How mpv should decode video.
enum HardwareDecoding {
  /// `hwdec=no`.
  off('no'),

  /// `hwdec=auto-copy` — **the default, and not the same as `auto`.**
  ///
  /// `auto` hands mpv's own output a hardware surface, which does not survive
  /// being handed to a texture. `auto-copy` decodes on the GPU and copies the
  /// frame back, which costs bandwidth and works everywhere.
  copy('auto-copy'),

  /// `hwdec=auto`.
  direct('auto');

  const HardwareDecoding(this.mpvValue);
  final String mpvValue;
}

@immutable
class PlaybackSettings {
  const PlaybackSettings({
    this.channels = AudioChannels.stereo,
    this.hardwareDecoding = HardwareDecoding.copy,
    this.alwaysForceTranscode = false,
    this.allowTranscodeToHevc = false,
    this.preferTranscodeToH265 = false,
    this.forceTranscodeDovi = true,
    this.forceTranscodeHdr = false,
    this.forceTranscodeHi10p = false,
    this.forceTranscodeHevc = false,
    this.forceTranscodeAv1 = false,
    this.forceTranscode4k = false,
  });

  final AudioChannels channels;
  final HardwareDecoding hardwareDecoding;

  /// Drops the video direct-play profile entirely, so the server transcodes
  /// everything. A debugging lever, not something to expose casually.
  final bool alwaysForceTranscode;

  /// Offers HEVC as a transcode *target*.
  ///
  /// This exists as a workaround for Dolby Vision content direct-playing when
  /// it should not, rather than as a quality setting.
  final bool allowTranscodeToHevc;

  /// Puts HEVC first in the transcode-target list. Only meaningful with
  /// [allowTranscodeToHevc].
  final bool preferTranscodeToH265;

  /// **Defaults to on.** mpv renders Dolby Vision profile 5 with the wrong
  /// colours — everything comes out washed out and green-tinted — so the honest
  /// thing is to ask the server to transcode it away. This is the flag to
  /// revisit if real DoVi support ever lands.
  final bool forceTranscodeDovi;

  final bool forceTranscodeHdr;

  /// 10-bit H.264. Some hardware decoders cannot manage it.
  final bool forceTranscodeHi10p;

  final bool forceTranscodeHevc;
  final bool forceTranscodeAv1;

  /// Caps direct play at 1080p.
  final bool forceTranscode4k;

  PlaybackSettings copyWith({
    AudioChannels? channels,
    HardwareDecoding? hardwareDecoding,
    bool? alwaysForceTranscode,
    bool? allowTranscodeToHevc,
    bool? preferTranscodeToH265,
    bool? forceTranscodeDovi,
    bool? forceTranscodeHdr,
    bool? forceTranscodeHi10p,
    bool? forceTranscodeHevc,
    bool? forceTranscodeAv1,
    bool? forceTranscode4k,
  }) => PlaybackSettings(
    channels: channels ?? this.channels,
    hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
    alwaysForceTranscode: alwaysForceTranscode ?? this.alwaysForceTranscode,
    allowTranscodeToHevc: allowTranscodeToHevc ?? this.allowTranscodeToHevc,
    preferTranscodeToH265: preferTranscodeToH265 ?? this.preferTranscodeToH265,
    forceTranscodeDovi: forceTranscodeDovi ?? this.forceTranscodeDovi,
    forceTranscodeHdr: forceTranscodeHdr ?? this.forceTranscodeHdr,
    forceTranscodeHi10p: forceTranscodeHi10p ?? this.forceTranscodeHi10p,
    forceTranscodeHevc: forceTranscodeHevc ?? this.forceTranscodeHevc,
    forceTranscodeAv1: forceTranscodeAv1 ?? this.forceTranscodeAv1,
    forceTranscode4k: forceTranscode4k ?? this.forceTranscode4k,
  );
}
