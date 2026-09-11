/// What a track is called in the menus.
///
/// The server's `DisplayTitle` is the label, with one correction: Jellyfin
/// appends the format to a subtitle's title, so tracks arrive as "English - ASS".
/// That is a text container's name, it is the same for nearly every track on
/// offer, and it is not what anyone reading a television from three metres needs
/// to know. For audio the codec stays, because AAC against TrueHD is a real
/// choice about what the amplifier does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/components/playback_menu.dart';
import 'package:glassfin/jellyfin/models.dart';

MediaStream _stream({
  required StreamType type,
  String? displayTitle,
  String? codec,
  String? language,
}) => MediaStream(
  index: 1,
  type: type,
  displayTitle: displayTitle,
  codec: codec,
  language: language,
);

void main() {
  group('subtitles drop the format', () {
    test('the one that prompted this', () {
      expect(
        trackLabel(
          _stream(
            type: StreamType.subtitle,
            displayTitle: 'English - ASS',
            codec: 'ass',
          ),
        ),
        'English',
      );
    });

    test('every format Jellyfin is likely to append', () {
      for (final format in ['SRT', 'SUBRIP', 'PGS', 'PGSSUB', 'VTT', 'SSA']) {
        expect(
          trackLabel(
            _stream(
              type: StreamType.subtitle,
              displayTitle: 'English - $format',
            ),
          ),
          'English',
          reason: format,
        );
      }
    });

    test('a codec the list has never heard of still goes', () {
      // Matched against the stream's own codec as well as the known list, since
      // the two disagree often enough to matter.
      expect(
        trackLabel(
          _stream(
            type: StreamType.subtitle,
            displayTitle: 'English - SOMETHINGNEW',
            codec: 'somethingnew',
          ),
        ),
        'English',
      );
    });

    test('only the last segment, so the rest of the title survives', () {
      expect(
        trackLabel(
          _stream(
            type: StreamType.subtitle,
            displayTitle: 'English (SDH) - Forced - SRT',
          ),
        ),
        'English (SDH) - Forced',
      );
    });

    test('a title that is not a format is left alone', () {
      expect(
        trackLabel(
          _stream(
            type: StreamType.subtitle,
            displayTitle: 'English - Director commentary',
            codec: 'ass',
          ),
        ),
        'English - Director commentary',
      );
    });

    test('a title that is only the format is kept', () {
      // A poor label, but a blank one is worse.
      expect(
        trackLabel(
          _stream(type: StreamType.subtitle, displayTitle: 'PGS', codec: 'pgs'),
        ),
        'PGS',
      );
    });
  });

  group('audio keeps its codec', () {
    test('because it says what the amplifier will be asked to do', () {
      expect(
        trackLabel(
          _stream(
            type: StreamType.audio,
            displayTitle: 'English - TrueHD - 5.1',
            codec: 'truehd',
          ),
        ),
        'English - TrueHD - 5.1',
      );
    });

    test('even when the title ends in something the subtitle list knows', () {
      expect(
        trackLabel(
          _stream(type: StreamType.audio, displayTitle: 'Commentary - TEXT'),
        ),
        'Commentary - TEXT',
      );
    });
  });

  group('no DisplayTitle at all', () {
    test('a subtitle falls back to the language alone', () {
      expect(
        trackLabel(
          _stream(type: StreamType.subtitle, language: 'eng', codec: 'ass'),
        ),
        'English',
      );
    });

    test('audio falls back to language and codec', () {
      expect(
        trackLabel(
          _stream(type: StreamType.audio, language: 'eng', codec: 'aac'),
        ),
        'English · AAC',
      );
    });

    test('an unknown language does not produce a blank row', () {
      expect(trackLabel(_stream(type: StreamType.subtitle)), 'Unknown');
    });
  });
}
