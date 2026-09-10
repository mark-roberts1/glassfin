/// Round-tripping [VideoSettings].
///
/// Worth testing rather than eyeballing: every field falls back to its default
/// when a key is missing or the wrong type, which is what lets an older stored
/// file load — and is also exactly how a typo'd key ends up silently swallowing
/// a setting. A toggle that appears not to persist is the symptom.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/settings/video_settings.dart';

void main() {
  group('VideoSettings json', () {
    test('round-trips every field away from its default', () {
      const original = VideoSettings(
        hardwareDecoding: HardwareDecoding.off,
        videoSync: VideoSync.displayResample,
        deinterlace: true,
        cacheMegabytes: 256,
        defaultPlaybackSpeed: 1.25,
        alwaysForceTranscode: true,
        allowTranscodeToHevc: true,
        preferTranscodeToH265: true,
        // The one that defaults to *on*, so flipping it off is the real test.
        forceTranscodeDovi: false,
        forceTranscodeHdr: true,
        forceTranscodeHi10p: true,
        forceTranscodeHevc: true,
        forceTranscodeAv1: true,
        forceTranscode4k: true,
      );

      final back = VideoSettings.fromJson(original.toJson());

      expect(back.hardwareDecoding, HardwareDecoding.off);
      expect(back.videoSync, VideoSync.displayResample);
      expect(back.deinterlace, isTrue);
      expect(back.cacheMegabytes, 256);
      expect(back.defaultPlaybackSpeed, 1.25);
      expect(back.alwaysForceTranscode, isTrue);
      expect(back.allowTranscodeToHevc, isTrue);
      expect(back.preferTranscodeToH265, isTrue);
      expect(back.forceTranscodeDovi, isFalse);
      expect(back.forceTranscodeHdr, isTrue);
      expect(back.forceTranscodeHi10p, isTrue);
      expect(back.forceTranscodeHevc, isTrue);
      expect(back.forceTranscodeAv1, isTrue);
      expect(back.forceTranscode4k, isTrue);
    });

    test('an empty object is the defaults, not an exception', () {
      final back = VideoSettings.fromJson(const {});
      const defaults = VideoSettings();

      expect(back.hardwareDecoding, defaults.hardwareDecoding);
      expect(back.cacheMegabytes, defaults.cacheMegabytes);
      expect(back.alwaysForceTranscode, isFalse);
      // Dolby Vision transcoding defaults **on**: mpv renders profile 5 with the
      // wrong colours, so a missing key must not quietly turn it off.
      expect(back.forceTranscodeDovi, isTrue);
    });

    test('enums are stored by name, so a reordering cannot change meaning', () {
      expect(const VideoSettings().toJson()['hardwareDecoding'], 'copy');
      expect(
        VideoSettings.fromJson(const {'hardwareDecoding': 'copy'})
            .hardwareDecoding,
        HardwareDecoding.copy,
      );
    });

    test('a junk value falls back rather than throwing', () {
      final back = VideoSettings.fromJson(const {
        'hardwareDecoding': 'nonsense',
        'cacheMegabytes': 'lots',
        'deinterlace': 'yes',
        'defaultPlaybackSpeed': null,
      });

      expect(back.hardwareDecoding, HardwareDecoding.copy);
      expect(back.cacheMegabytes, 75);
      expect(back.deinterlace, isFalse);
      expect(back.defaultPlaybackSpeed, 1.0);
    });

    test('an int is accepted for the speed, which JSON may store as one', () {
      // `1.0` encodes as `1.0` here, but a hand-edited file or another writer
      // can easily produce a bare `2`, and a cast to double would throw on it.
      expect(
        VideoSettings.fromJson(const {'defaultPlaybackSpeed': 2})
            .defaultPlaybackSpeed,
        2.0,
      );
    });
  });
}
