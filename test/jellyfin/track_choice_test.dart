import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/jellyfin/models.dart';
import 'package:glassfin/jellyfin/track_choice.dart';

MediaStream stream(
  int index,
  StreamType type, {
  String? language,
  bool isDefault = false,
  bool isForced = false,
}) => MediaStream(
  index: index,
  type: type,
  language: language,
  isDefault: isDefault,
  isForced: isForced,
);

void main() {
  group('relativeStreamIndex', () {
    // A realistic file: video is stream 0, then audio, then subtitles, with
    // Jellyfin numbering them all in one sequence.
    final streams = [
      stream(0, StreamType.video),
      stream(1, StreamType.audio, language: 'eng'),
      stream(2, StreamType.audio, language: 'jpn'),
      stream(3, StreamType.subtitle, language: 'eng'),
      stream(4, StreamType.subtitle, language: 'jpn'),
    ];

    test('converts an absolute index to a one-based ordinal for its type', () {
      // mpv counts per type: Jellyfin's stream 2 is mpv's second audio track.
      expect(relativeStreamIndex(streams, 1, StreamType.audio), 1);
      expect(relativeStreamIndex(streams, 2, StreamType.audio), 2);
      expect(relativeStreamIndex(streams, 3, StreamType.subtitle), 1);
      expect(relativeStreamIndex(streams, 4, StreamType.subtitle), 2);
    });

    test('is one-based, matching mpv rather than the array', () {
      expect(relativeStreamIndex(streams, 1, StreamType.audio), isNot(0));
    });

    test('returns -1 when the stream is not of that type', () {
      // Asking for the subtitle ordinal of an audio stream is a caller bug, and
      // -1 is what mpv reads as "no track" rather than silently picking one.
      expect(relativeStreamIndex(streams, 1, StreamType.subtitle), -1);
    });

    test('returns -1 for an index that is not there at all', () {
      expect(relativeStreamIndex(streams, 99, StreamType.audio), -1);
    });

    test('counts from an empty list without throwing', () {
      expect(relativeStreamIndex(const [], 1, StreamType.audio), -1);
    });
  });

  group('chooseAudioStream', () {
    test('prefers the requested language', () {
      final streams = [
        stream(1, StreamType.audio, language: 'eng', isDefault: true),
        stream(2, StreamType.audio, language: 'jpn'),
      ];
      expect(chooseAudioStream(streams, 'jpn')?.index, 2);
    });

    test('falls back to the server default when the language is missing', () {
      final streams = [
        stream(1, StreamType.audio, language: 'eng'),
        stream(2, StreamType.audio, language: 'fre', isDefault: true),
      ];
      expect(chooseAudioStream(streams, 'jpn')?.index, 2);
    });

    test('falls back to the first track when nothing is marked default', () {
      final streams = [
        stream(1, StreamType.audio, language: 'eng'),
        stream(2, StreamType.audio, language: 'fre'),
      ];
      expect(chooseAudioStream(streams, 'jpn')?.index, 1);
    });

    test('always resolves to something when there is any audio at all', () {
      // Unlike subtitles, silence is never the right answer.
      final streams = [stream(1, StreamType.audio)];
      expect(chooseAudioStream(streams, ''), isNotNull);
      expect(chooseAudioStream(streams, 'eng'), isNotNull);
    });

    test('returns null only when the file has no audio', () {
      expect(chooseAudioStream([stream(0, StreamType.video)], 'eng'), isNull);
    });

    test('matches language case-insensitively', () {
      final streams = [
        stream(1, StreamType.audio, language: 'ENG'),
        stream(2, StreamType.audio, language: 'jpn', isDefault: true),
      ];
      expect(chooseAudioStream(streams, 'eng')?.index, 1);
    });
  });

  group('chooseSubtitleStream', () {
    final streams = [
      stream(3, StreamType.subtitle, language: 'eng'),
      stream(4, StreamType.subtitle, language: 'eng', isForced: true),
      stream(5, StreamType.subtitle, language: 'jpn', isDefault: true),
    ];

    test('off picks nothing, whatever is available', () {
      expect(chooseSubtitleStream(streams, SubtitleMode.off, 'eng'), isNull);
    });

    test('forced picks only a forced track in the right language', () {
      expect(
        chooseSubtitleStream(streams, SubtitleMode.forced, 'eng')?.index,
        4,
      );
    });

    test('forced picks nothing when there is no forced track', () {
      // Turning on full subtitles because no forced track exists would be a
      // different setting from the one the viewer chose.
      expect(chooseSubtitleStream(streams, SubtitleMode.forced, 'jpn'), isNull);
    });

    test('preferred takes a forced track ahead of a plain one', () {
      // A forced track in the right language is what the film was authored to
      // show — the signed dialogue, not a full transcript.
      expect(
        chooseSubtitleStream(streams, SubtitleMode.preferred, 'eng')?.index,
        4,
      );
    });

    test('preferred falls back to the default, then the first', () {
      final plain = [
        stream(3, StreamType.subtitle, language: 'eng'),
        stream(4, StreamType.subtitle, language: 'eng', isDefault: true),
      ];
      expect(
        chooseSubtitleStream(plain, SubtitleMode.preferred, 'eng')?.index,
        4,
      );

      final neither = [
        stream(3, StreamType.subtitle, language: 'eng'),
        stream(4, StreamType.subtitle, language: 'eng'),
      ];
      expect(
        chooseSubtitleStream(neither, SubtitleMode.preferred, 'eng')?.index,
        3,
      );
    });

    test('preferred leaves subtitles off when the language is absent', () {
      // The important negative case: turning on Hungarian subtitles because
      // that is all the file has would be worse than showing none.
      expect(
        chooseSubtitleStream(streams, SubtitleMode.preferred, 'hun'),
        isNull,
      );
    });

    test('preferred with no language set considers every track', () {
      expect(
        chooseSubtitleStream(streams, SubtitleMode.preferred, '')?.index,
        4, // the forced one, still first among all of them
      );
    });

    test('returns null when the file has no subtitles', () {
      final none = [stream(1, StreamType.audio, language: 'eng')];
      expect(chooseSubtitleStream(none, SubtitleMode.preferred, 'eng'), isNull);
      expect(chooseSubtitleStream(none, SubtitleMode.forced, 'eng'), isNull);
    });
  });

  group('ticks', () {
    test('convert to and from milliseconds', () {
      // 100-nanosecond units: one second is ten million of them.
      expect(ticksToMs(10000000), 1000);
      expect(msToTicks(1000), 10000000);
    });

    test('convert to a Duration without losing sub-millisecond precision', () {
      expect(ticksToDuration(10000000), const Duration(seconds: 1));
      expect(durationToTicks(const Duration(seconds: 1)), 10000000);
    });

    test('round-trip a realistic resume point', () {
      const position = Duration(minutes: 37, seconds: 12, milliseconds: 340);
      expect(ticksToDuration(durationToTicks(position)), position);
    });
  });
}
