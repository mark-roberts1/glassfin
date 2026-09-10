/// The `video` settings section: how video is decoded, and what the server is
/// asked to transcode.
///
/// Keys and defaults are carried over from the Qt build's `glassfin.conf` rather
/// than reinvented — someone moving between the two should not silently get
/// different transcoding behaviour.
library;

import 'package:flutter/foundation.dart';

/// How mpv should decode video.
enum HardwareDecoding {
  off('no'),

  /// `hwdec=auto-copy` — **the default, and deliberately not `auto`.**
  ///
  /// Hardware decode, but with the frame copied back so it still travels through
  /// mpv's own shader pipeline. That keeps the scaler and colour management
  /// working, which `auto` gives up in exchange for bandwidth.
  copy('auto-copy'),

  direct('auto');

  const HardwareDecoding(this.mpvValue);
  final String mpvValue;
}

/// How mpv should keep video and audio in step.
enum VideoSync {
  /// The safe default: resample audio to match the video clock.
  audio('audio'),

  /// Judder-free when the display rate is a multiple of the content rate, which
  /// is what refresh-rate switching exists to arrange.
  displayResample('display-resample'),

  displayAdrop('display-adrop');

  const VideoSync(this.mpvValue);
  final String mpvValue;
}

@immutable
class VideoSettings {
  const VideoSettings({
    this.hardwareDecoding = HardwareDecoding.copy,
    this.videoSync = VideoSync.audio,
    this.deinterlace = false,
    this.cacheMegabytes = 75,
    this.defaultPlaybackSpeed = 1.0,
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

  final HardwareDecoding hardwareDecoding;
  final VideoSync videoSync;
  final bool deinterlace;

  /// Demuxer cache, in mebibytes.
  final int cacheMegabytes;

  final double defaultPlaybackSpeed;

  /// Drops the video direct-play profile entirely, so the server transcodes
  /// everything. A debugging lever, not something to expose casually.
  final bool alwaysForceTranscode;

  /// Offers HEVC as a transcode *target*.
  ///
  /// This exists as a workaround for Dolby Vision content direct-playing when it
  /// should not, rather than as a quality setting.
  final bool allowTranscodeToHevc;

  /// Puts HEVC first in the transcode-target list. Only meaningful alongside
  /// [allowTranscodeToHevc].
  final bool preferTranscodeToH265;

  /// **Defaults to on.** mpv renders Dolby Vision profile 5 with the wrong
  /// colours, so the honest thing is to ask the server to transcode it away.
  /// This is the flag to revisit if real DoVi support ever lands.
  final bool forceTranscodeDovi;

  final bool forceTranscodeHdr;

  /// 10-bit H.264. Some hardware decoders cannot manage it.
  final bool forceTranscodeHi10p;

  final bool forceTranscodeHevc;
  final bool forceTranscodeAv1;

  /// Caps direct play at 1080p.
  final bool forceTranscode4k;

  VideoSettings copyWith({
    HardwareDecoding? hardwareDecoding,
    VideoSync? videoSync,
    bool? deinterlace,
    int? cacheMegabytes,
    double? defaultPlaybackSpeed,
    bool? alwaysForceTranscode,
    bool? allowTranscodeToHevc,
    bool? preferTranscodeToH265,
    bool? forceTranscodeDovi,
    bool? forceTranscodeHdr,
    bool? forceTranscodeHi10p,
    bool? forceTranscodeHevc,
    bool? forceTranscodeAv1,
    bool? forceTranscode4k,
  }) => VideoSettings(
    hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
    videoSync: videoSync ?? this.videoSync,
    deinterlace: deinterlace ?? this.deinterlace,
    cacheMegabytes: cacheMegabytes ?? this.cacheMegabytes,
    defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
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

  /// Enums are stored by **name**, not index: a reordering of
  /// [HardwareDecoding] would otherwise silently change what a stored file
  /// means, and `auto-copy` becoming `auto` is exactly the kind of change that
  /// is invisible until a specific file will not play.
  Map<String, Object?> toJson() => {
    'hardwareDecoding': hardwareDecoding.name,
    'videoSync': videoSync.name,
    'deinterlace': deinterlace,
    'cacheMegabytes': cacheMegabytes,
    'defaultPlaybackSpeed': defaultPlaybackSpeed,
    'alwaysForceTranscode': alwaysForceTranscode,
    'allowTranscodeToHevc': allowTranscodeToHevc,
    'preferTranscodeToH265': preferTranscodeToH265,
    'forceTranscodeDovi': forceTranscodeDovi,
    'forceTranscodeHdr': forceTranscodeHdr,
    'forceTranscodeHi10p': forceTranscodeHi10p,
    'forceTranscodeHevc': forceTranscodeHevc,
    'forceTranscodeAv1': forceTranscodeAv1,
    'forceTranscode4k': forceTranscode4k,
  };

  /// Every field falls back to its default, so a file written by an older build
  /// — or one missing a key entirely — loads rather than throwing.
  factory VideoSettings.fromJson(Map<String, Object?> json) {
    const defaults = VideoSettings();
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key]! as bool : fallback;

    return VideoSettings(
      hardwareDecoding: _byName(
        HardwareDecoding.values,
        json['hardwareDecoding'],
        defaults.hardwareDecoding,
      ),
      videoSync: _byName(
        VideoSync.values,
        json['videoSync'],
        defaults.videoSync,
      ),
      deinterlace: flag('deinterlace', defaults.deinterlace),
      cacheMegabytes: json['cacheMegabytes'] is int
          ? json['cacheMegabytes']! as int
          : defaults.cacheMegabytes,
      defaultPlaybackSpeed: json['defaultPlaybackSpeed'] is num
          ? (json['defaultPlaybackSpeed']! as num).toDouble()
          : defaults.defaultPlaybackSpeed,
      alwaysForceTranscode: flag(
        'alwaysForceTranscode',
        defaults.alwaysForceTranscode,
      ),
      allowTranscodeToHevc: flag(
        'allowTranscodeToHevc',
        defaults.allowTranscodeToHevc,
      ),
      preferTranscodeToH265: flag(
        'preferTranscodeToH265',
        defaults.preferTranscodeToH265,
      ),
      forceTranscodeDovi: flag(
        'forceTranscodeDovi',
        defaults.forceTranscodeDovi,
      ),
      forceTranscodeHdr: flag('forceTranscodeHdr', defaults.forceTranscodeHdr),
      forceTranscodeHi10p: flag(
        'forceTranscodeHi10p',
        defaults.forceTranscodeHi10p,
      ),
      forceTranscodeHevc: flag(
        'forceTranscodeHevc',
        defaults.forceTranscodeHevc,
      ),
      forceTranscodeAv1: flag('forceTranscodeAv1', defaults.forceTranscodeAv1),
      forceTranscode4k: flag('forceTranscode4k', defaults.forceTranscode4k),
    );
  }

  static T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}

/// How the picture is fitted to the panel — the reference client's "Aspect
/// Ratio" menu, expressed as the mpv properties that actually do it.
///
/// mpv has no single "fit mode" switch, so each option is a small set of
/// properties: `keepaspect` decides whether the ratio is honoured at all, and
/// `panscan` decides whether overflow is cropped rather than letterboxed.
enum AspectMode {
  /// The file's own ratio, letterboxed to fit. What you almost always want.
  auto('Auto', {'keepaspect': 'yes', 'panscan': '0.0'}),

  /// Fill the panel by cropping the overflow — removes the black bars on a
  /// scope film at the cost of the edges of the frame.
  cover('Cover', {'keepaspect': 'yes', 'panscan': '1.0'}),

  /// Stretch to the panel, ratio be damned. Present because some broadcast
  /// material is flagged wrong and this is the only way to correct it.
  fill('Fill', {'keepaspect': 'no', 'panscan': '0.0'});

  const AspectMode(this.label, this.properties);

  final String label;
  final Map<String, String> properties;
}
