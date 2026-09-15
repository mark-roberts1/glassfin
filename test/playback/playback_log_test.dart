import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/jellyfin/models.dart';
import 'package:glassfin/playback/playback_log.dart';

void main() {
  const film = Item(id: 'film1', name: 'Your Name.', type: ItemKind.movie);
  const episode = Item(
    id: 'ep1',
    name: 'Sex and the City',
    type: ItemKind.episode,
    seriesName: 'Sex and the City',
    parentIndexNumber: 1,
    indexNumber: 1,
  );

  group('the title', () {
    test('is the name for a film', () {
      expect(playbackLogTitle(film), 'Your Name.');
    });

    test('names the series, the episode code and the episode', () {
      // A journal full of lines that all say "Sex and the City" is exactly the
      // ambiguity this line exists to remove, so the episode has to be in it.
      expect(
        playbackLogTitle(episode),
        'Sex and the City · S1:E1 · Sex and the City',
      );
    });

    test('drops the code, not the separator, when indices are missing', () {
      const pilot = Item(
        id: 'ep0',
        name: 'Pilot',
        type: ItemKind.episode,
        seriesName: 'Arrested Development',
      );
      expect(playbackLogTitle(pilot), 'Arrested Development · Pilot');
    });

    test('cannot end the quoted title early', () {
      const quoted = Item(
        id: 'q',
        name: 'The "Best" Film',
        type: ItemKind.movie,
      );
      expect(playbackLogTitle(quoted), "The 'Best' Film");
    });
  });

  group('the line', () {
    test(
      'carries the point, delivery, title, id and position before the values',
      () {
        final line = playbackLogLine(
          point: PlaybackLogPoint.stopped,
          item: film,
          transcoding: false,
          position: const Duration(hours: 1, minutes: 46, seconds: 31),
          values: const [('hwdec-current', 'no'), ('frame-drop-count', '1')],
        );

        expect(
          line,
          'glassfin: playback stop [direct] "Your Name." id=film1 at=1:46:31 '
          'hwdec-current=no frame-drop-count=1',
        );
      },
    );

    test('says transcode when the server is transcoding', () {
      final line = playbackLogLine(
        point: PlaybackLogPoint.started,
        item: episode,
        transcoding: true,
        position: const Duration(seconds: 10),
        values: const [],
      );

      expect(line, startsWith('glassfin: playback start [transcode] '));
      expect(line, contains('at=0:10'));
    });

    test('prints a value mpv could not supply as a question mark', () {
      final line = playbackLogLine(
        point: PlaybackLogPoint.playing,
        item: film,
        transcoding: false,
        position: Duration.zero,
        values: const [('display-fps', null)],
      );

      expect(line, endsWith('display-fps=?'));
    });

    test('keeps the prefix that existing log searches look for', () {
      // Handoff notes and release notes grep for "glassfin: playback".
      for (final point in PlaybackLogPoint.values) {
        final line = playbackLogLine(
          point: point,
          item: film,
          transcoding: false,
          position: Duration.zero,
          values: const [],
        );
        expect(line, startsWith('glassfin: playback '));
      }
    });
  });

  test('reports the drop counters the stutter diagnosis depends on', () {
    expect(
      playbackLogProperties,
      containsAll([
        'hwdec-current',
        'frame-drop-count',
        'decoder-frame-drop-count',
      ]),
    );
  });
}
