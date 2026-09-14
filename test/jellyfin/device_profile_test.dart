import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/jellyfin/device_profile.dart';
import 'package:glassfin/settings/audio_settings.dart';
import 'package:glassfin/settings/video_settings.dart';

List<Map<String, Object?>> _list(Map<String, Object?> profile, String key) =>
    (profile[key] as List).cast<Map<String, Object?>>();

/// Every condition in a codec profile, flattened, for asserting on shapes.
List<Map<String, Object?>> _conditions(Map<String, Object?> codecProfile) =>
    (codecProfile['Conditions'] as List).cast<Map<String, Object?>>();

void main() {
  const defaults = VideoSettings();

  /// The profile for a given pair of settings sections, each defaulting.
  Map<String, Object?> profileFor({
    VideoSettings? video,
    AudioSettings? audio,
  }) => buildDeviceProfile(
    video: video ?? const VideoSettings(),
    audio: audio ?? const AudioSettings(),
  );

  group('direct play', () {
    test('is unconstrained, because mpv plays everything', () {
      // No Container and no Codec fields: in Jellyfin's profile semantics that
      // means "anything". If a codec list ever appears here, someone has
      // misunderstood what this profile is for.
      final video = _list(
        profileFor(),
        'DirectPlayProfiles',
      ).firstWhere((p) => p['Type'] == 'Video');

      expect(video.keys, ['Type']);
    });

    test('is never bitrate-limited, in either of the two bitrate fields', () {
      // MaxStreamingBitrate is the one the server's direct-play decision reads.
      // Omitted, Jellyfin assumes 8 Mbps and transcodes any 1080p file above
      // it with `ContainerBitrateExceedsLimit`, which is what this guards.
      final profile = profileFor();

      expect(profile['MaxStaticBitrate'], 1000000000);
      expect(profile['MaxStreamingBitrate'], 1000000000);
    });

    test('drops video entirely when everything is forced to transcode', () {
      final profile = profileFor(
        video: defaults.copyWith(alwaysForceTranscode: true),
      );
      final types = _list(
        profile,
        'DirectPlayProfiles',
      ).map((p) => p['Type']).toList();

      expect(types, isNot(contains('Video')));
      // Audio and photo are untouched: the setting is about video.
      expect(types, containsAll(<String>['Audio', 'Photo']));
    });
  });

  group('transcode targets', () {
    test('offer only H.264 by default', () {
      expect(transcodeVideoCodecs(defaults), 'h264,mpeg4,mpeg2video');
    });

    test('add HEVC after H.264 when it is merely allowed', () {
      expect(
        transcodeVideoCodecs(defaults.copyWith(allowTranscodeToHevc: true)),
        'h264,h265,hevc,mpeg4,mpeg2video',
      );
    });

    test('put HEVC first when it is preferred', () {
      // The ordering *is* the preference signal: the server takes the first
      // codec it can produce, so this is the difference between permitting HEVC
      // and asking for it.
      expect(
        transcodeVideoCodecs(
          defaults.copyWith(
            allowTranscodeToHevc: true,
            preferTranscodeToH265: true,
          ),
        ),
        'h265,hevc,h264,mpeg4,mpeg2video',
      );
    });

    test('preferring H.265 does nothing unless it is also allowed', () {
      expect(
        transcodeVideoCodecs(defaults.copyWith(preferTranscodeToH265: true)),
        'h264,mpeg4,mpeg2video',
      );
    });

    test('cap audio channels at the configured layout', () {
      final stereo = _list(
        profileFor(),
        'TranscodingProfiles',
      ).firstWhere((p) => p['Type'] == 'Video');
      expect(stereo['MaxAudioChannels'], '2');

      final surround = _list(
        profileFor(
          audio: const AudioSettings(channels: AudioChannels.surround51),
        ),
        'TranscodingProfiles',
      ).firstWhere((p) => p['Type'] == 'Video');
      expect(surround['MaxAudioChannels'], '6');
    });
  });

  group('force-transcode toggles', () {
    test('Dolby Vision is forced to transcode by default', () {
      // mpv renders DoVi profile 5 with the wrong colours, so this default is
      // deliberate. If it ever flips, it should be because DoVi actually works.
      final codecProfiles = _list(profileFor(), 'CodecProfiles');

      expect(codecProfiles, hasLength(1));
      expect(_conditions(codecProfiles.single).single, {
        'Condition': 'NotEquals',
        'Property': 'VideoRangeType',
        'Value': 'DOVI',
      });
    });

    test('nothing else is forced by default', () {
      final profile = profileFor(
        video: defaults.copyWith(forceTranscodeDovi: false),
      );
      expect(_list(profile, 'CodecProfiles'), isEmpty);
    });

    test('HEVC uses the "Equals Width 0" never-direct-play idiom', () {
      // No stream has width 0, so the condition never holds and the codec can
      // never direct-play. It reads like a mistake and is not one.
      final codecProfiles = _list(
        profileFor(
          video: defaults.copyWith(
            forceTranscodeDovi: false,
            forceTranscodeHevc: true,
          ),
        ),
        'CodecProfiles',
      );

      // Both spellings, because servers report either.
      expect(codecProfiles.map((p) => p['Codec']), ['hevc', 'h265']);
      for (final profile in codecProfiles) {
        expect(_conditions(profile).single, {
          'Condition': 'Equals',
          'Property': 'Width',
          'Value': '0',
        });
      }
    });

    test('AV1 uses the same idiom', () {
      final codecProfiles = _list(
        profileFor(
          video: defaults.copyWith(
            forceTranscodeDovi: false,
            forceTranscodeAv1: true,
          ),
        ),
        'CodecProfiles',
      );
      expect(codecProfiles.single['Codec'], 'av1');
      expect(_conditions(codecProfiles.single).single['Value'], '0');
    });

    test('4K caps direct play at 1080p with both dimensions', () {
      // Width alone would let a 3840x1080 ultrawide through.
      final codecProfiles = _list(
        profileFor(
          video: defaults.copyWith(
            forceTranscodeDovi: false,
            forceTranscode4k: true,
          ),
        ),
        'CodecProfiles',
      );
      expect(_conditions(codecProfiles.single), [
        {'Condition': 'LessThanEqual', 'Property': 'Width', 'Value': '1920'},
        {'Condition': 'LessThanEqual', 'Property': 'Height', 'Value': '1080'},
      ]);
    });

    test('HDR and Hi10p invert their own conditions', () {
      final hdr = _list(
        profileFor(
          video: defaults.copyWith(
            forceTranscodeDovi: false,
            forceTranscodeHdr: true,
          ),
        ),
        'CodecProfiles',
      );
      expect(_conditions(hdr.single).single['Value'], 'SDR');

      final hi10p = _list(
        profileFor(
          video: defaults.copyWith(
            forceTranscodeDovi: false,
            forceTranscodeHi10p: true,
          ),
        ),
        'CodecProfiles',
      );
      expect(_conditions(hi10p.single).single, {
        'Condition': 'LessThanEqual',
        'Property': 'VideoBitDepth',
        'Value': '8',
      });
    });

    test('toggles accumulate rather than replacing one another', () {
      final codecProfiles = _list(
        profileFor(
          video: defaults.copyWith(
            forceTranscodeHevc: true,
            forceTranscode4k: true,
          ),
        ),
        'CodecProfiles',
      );
      // DoVi + hevc + h265 + 4k
      expect(codecProfiles, hasLength(4));
    });
  });

  group('subtitles', () {
    final subtitles = _list(profileFor(), 'SubtitleProfiles');

    Set<Object?> methodsFor(String format) => subtitles
        .where((p) => p['Format'] == format)
        .map((p) => p['Method'])
        .toSet();

    test('text formats can be sideloaded or switched in place', () {
      for (final format in ['srt', 'ass', 'sub', 'ssa', 'smi']) {
        expect(methodsFor(format), {
          'External',
          'Embed',
        }, reason: '$format should support both delivery methods');
      }
    });

    test('bitmap formats are embed-only', () {
      // There is no file mpv could fetch a picture-based subtitle from, so
      // offering External here would make the server hand over a URL that
      // cannot be rendered.
      for (final format in ['pgssub', 'dvdsub', 'dvbsub', 'pgs']) {
        expect(methodsFor(format), {
          'Embed',
        }, reason: '$format is a bitmap format');
      }
    });
  });

  test('identifies itself as Glassfin, not as Jellyfin Desktop', () {
    // The upstream profile this was ported from called itself Jellyfin Desktop;
    // that string reaches the server's dashboard, so it is corrected here.
    expect(profileFor()['Name'], 'Glassfin');
  });

  test('never bitrate-limits direct play', () {
    // A cap here makes the server transcode a file that would have played
    // untouched over a LAN.
    expect(profileFor()['MaxStaticBitrate'], greaterThanOrEqualTo(1000000000));
  });
}
