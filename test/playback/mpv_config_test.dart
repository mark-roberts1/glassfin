import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/playback/mpv_config.dart';
import 'package:glassfin/settings/audio_settings.dart';
import 'package:glassfin/settings/subtitle_appearance.dart';
import 'package:glassfin/settings/video_settings.dart';

void main() {
  group('init properties', () {
    final properties = initProperties();

    test('do not rebase MKV timestamps', () {
      // The single most consequential property here. Jellyfin's MKV transcodes
      // start at a non-zero timestamp; if mpv rebases them, every position
      // reported back is wrong by that offset and resume points land minutes
      // from where the viewer actually stopped.
      expect(properties['demuxer-mkv-probe-start-time'], 'no');
    });

    test('probe lavf info, because HLS needs it', () {
      // mpv's own default of `auto` disables probing for HLS — which is exactly
      // what a Jellyfin transcode delivers.
      expect(properties['demuxer-lavf-probe-info'], 'yes');
    });

    test('survive an audio device that will not open', () {
      expect(properties['audio-fallback-to-null'], 'yes');
    });

    test('leave downmixing to us rather than the decoder', () {
      expect(properties['ad-lavc-downmix'], 'no');
    });
  });

  group('passthrough', () {
    test('is off entirely for a basic device', () {
      // The per-codec toggles describe what the receiver supports; an analogue
      // or USB output cannot carry a bitstream whatever they say.
      const audio = AudioSettings(
        deviceType: AudioDeviceType.basic,
        passthroughAc3: true,
        passthroughDts: true,
        passthroughTrueHd: true,
      );
      expect(passthroughCodecs(audio), isEmpty);
      expect(audioProperties(audio)['audio-spdif'], '');
    });

    test('offers only AC3 and DTS over S/PDIF', () {
      // An optical cable has nowhere near the bandwidth for TrueHD, so enabling
      // it must not put it in the list.
      const audio = AudioSettings(
        deviceType: AudioDeviceType.spdif,
        passthroughAc3: true,
        passthroughDts: true,
        passthroughEac3: true,
        passthroughTrueHd: true,
      );
      expect(passthroughCodecs(audio), ['ac3', 'dts']);
    });

    test('offers everything over HDMI', () {
      const audio = AudioSettings(
        deviceType: AudioDeviceType.hdmi,
        passthroughAc3: true,
        passthroughEac3: true,
        passthroughTrueHd: true,
      );
      expect(passthroughCodecs(audio), ['ac3', 'eac3', 'truehd']);
    });

    test('drops plain DTS whenever DTS-HD is enabled', () {
      // The rule that is impossible to guess: DTS-HD includes DTS, but listing
      // DTS first can make a receiver settle for the lesser one.
      const audio = AudioSettings(
        deviceType: AudioDeviceType.hdmi,
        passthroughDts: true,
        passthroughDtsHd: true,
      );
      expect(passthroughCodecs(audio), ['dts-hd']);
    });

    test('keeps plain DTS when DTS-HD is not enabled', () {
      const audio = AudioSettings(
        deviceType: AudioDeviceType.hdmi,
        passthroughDts: true,
      );
      expect(passthroughCodecs(audio), ['dts']);
    });

    test('joins the list the way mpv expects', () {
      const audio = AudioSettings(
        deviceType: AudioDeviceType.hdmi,
        passthroughAc3: true,
        passthroughDts: true,
      );
      expect(audioProperties(audio)['audio-spdif'], 'ac3,dts');
    });
  });

  group('channel layout', () {
    test('is forced to stereo on S/PDIF, whatever was chosen', () {
      // S/PDIF physically cannot carry multichannel PCM. Honouring a 5.1
      // selection here would produce silence or noise, not surround.
      const audio = AudioSettings(
        deviceType: AudioDeviceType.spdif,
        channels: AudioChannels.surround71,
      );
      expect(audioProperties(audio)['audio-channels'], '2.0');
    });

    test('is honoured over HDMI', () {
      const audio = AudioSettings(
        deviceType: AudioDeviceType.hdmi,
        channels: AudioChannels.surround71,
      );
      expect(audioProperties(audio)['audio-channels'], '7.1');
    });
  });

  group('AC3 re-encoding', () {
    test('is how 5.1 gets through an optical link', () {
      const audio = AudioSettings(
        deviceType: AudioDeviceType.spdif,
        passthroughAc3: true,
      );
      expect(shouldTranscodeToAc3(audio), isTrue);
    });

    test('is pointless over HDMI, which can carry the real thing', () {
      const audio = AudioSettings(
        deviceType: AudioDeviceType.hdmi,
        passthroughAc3: true,
      );
      expect(shouldTranscodeToAc3(audio), isFalse);
    });

    test('needs a receiver that actually decodes AC3', () {
      const audio = AudioSettings(deviceType: AudioDeviceType.spdif);
      expect(shouldTranscodeToAc3(audio), isFalse);
    });

    test('adds and removes the filter by label', () {
      // Labelled @ac3 so it can be removed by name — adding it twice would
      // stack two encoders on top of each other.
      expect(ac3FilterChange(wanted: true, current: false), [
        'af',
        'add',
        '@ac3:lavcac3enc',
      ]);
      expect(ac3FilterChange(wanted: false, current: true), [
        'af',
        'remove',
        '@ac3',
      ]);
    });

    test('does nothing when the filter is already in the right state', () {
      expect(ac3FilterChange(wanted: true, current: true), isNull);
      expect(ac3FilterChange(wanted: false, current: false), isNull);
    });
  });

  group('video', () {
    test('hardware decode defaults to auto-copy, not auto', () {
      // Deliberate: the frame is copied back so it still travels through mpv's
      // shader pipeline, which keeps the scaler and colour management working.
      expect(videoProperties(const VideoSettings())['hwdec'], 'auto-copy');
    });

    test('tells mpv the display rate rather than letting it guess', () {
      // Critical and easy to miss: without this the display-* sync modes
      // misbehave in ways that look like a decoding fault.
      final properties = videoProperties(
        const VideoSettings(),
        displayFps: 59.94,
      );
      expect(properties['display-fps-override'], '59.94');
    });

    test('omits the override when the rate is not known', () {
      expect(
        videoProperties(const VideoSettings()),
        isNot(contains('display-fps-override')),
      );
    });

    test('converts the cache setting to bytes', () {
      final properties = videoProperties(
        const VideoSettings(cacheMegabytes: 75),
      );
      expect(properties['demuxer-max-bytes'], '${75 * 1024 * 1024}');
    });
  });

  group('per-rate audio delay', () {
    double delay(double? fps) => audioDelayFor(
      displayFps: fps,
      normal: 0,
      at24: -40,
      at25: -20,
      at50: -10,
    );

    test('treats 23.976 as 24', () {
      // Cinema content almost never runs at a round number, which is the whole
      // reason for the tolerance.
      expect(delay(23.976), -40);
      expect(delay(24), -40);
    });

    test('matches 25 and 50 within tolerance', () {
      expect(delay(25), -20);
      expect(delay(50), -10);
      expect(delay(49.95), -10);
    });

    test('falls back to the normal delay for anything else', () {
      expect(delay(60), 0);
      expect(delay(59.94), 0);
      expect(delay(null), 0);
    });

    test('the tolerance is exclusive, so a rate exactly between matches neither', () {
      // 24.5 sits half a hertz from both 24 and 25. Picking either would be a
      // coin toss, so it falls through to the general-purpose delay.
      expect(delay(24.5), 0);
      // 24.6 is genuinely nearer 25, and does match it — the window is half a
      // hertz wide in each direction, not a claim that only round rates count.
      expect(delay(24.6), -20);
    });

    test('30Hz has no entry of its own', () {
      // Only 24, 25 and 50 were ever measured; everything else is normal.
      expect(delay(30), 0);
    });
  });

  group('subtitles', () {
    test('convert size into a scale factor around "Normal"', () {
      // 32 is what the settings call Normal, and mpv wants a multiplier.
      expect(
        subtitleProperties(const SubtitleAppearance(size: 32))['sub-scale'],
        '1.0',
      );
      expect(
        subtitleProperties(const SubtitleAppearance(size: 48))['sub-scale'],
        '1.5',
      );
    });

    test('insert the alpha byte after the hash, not at the end', () {
      // #RRGGBBAA is not an error to mpv — it is a completely different colour.
      // The mistake stays invisible until someone looks at a subtitle.
      expect(subtitleBackColor('#112233', 'AA'), '#AA112233');
    });

    test('need both a colour and a transparency to set a background', () {
      expect(subtitleBackColor('#112233', null), isNull);
      expect(subtitleBackColor(null, 'AA'), isNull);
      expect(subtitleBackColor('', 'AA'), isNull);
    });

    test('map placement onto align and position', () {
      final bottom = subtitleProperties(
        const SubtitleAppearance(alignX: SubtitleAlignX.left),
      );
      expect(bottom['sub-align-x'], 'left');
      expect(bottom['sub-pos'], '100');

      final top = subtitleProperties(
        const SubtitleAppearance(alignY: SubtitleAlignY.top),
      );
      // 10 rather than 0, to keep the text off the very edge of the panel.
      expect(top['sub-pos'], '10');
    });

    test("leave mpv's own defaults alone when a setting is unset", () {
      // Writing an empty string here would blank the subtitle colour rather than
      // leaving it at mpv's default.
      final properties = subtitleProperties(const SubtitleAppearance());
      expect(properties, isNot(contains('sub-scale')));
      expect(properties, isNot(contains('sub-color')));
      expect(properties, isNot(contains('sub-font')));
      expect(properties, isNot(contains('sub-back-color')));
    });

    test('always set the ASS border-scaling override', () {
      // Unlike the rest, this one has a real default either way, so it is always
      // written.
      expect(
        subtitleProperties(
          const SubtitleAppearance(),
        )['sub-ass-style-overrides'],
        'ScaledBorderAndShadow=yes',
      );
      expect(
        subtitleProperties(
          const SubtitleAppearance(assScaleBorderAndShadow: false),
        )['sub-ass-style-overrides'],
        'ScaledBorderAndShadow=no',
      );
    });
  });
}
