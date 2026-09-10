import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/jellyfin/labels.dart';
import 'package:glassfin/jellyfin/models.dart';

Item _item({
  String name = 'Item',
  ItemKind type = ItemKind.movie,
  String? seriesName,
  int? indexNumber,
  int? parentIndexNumber,
  int? productionYear,
  String? status,
  String? endDate,
}) => Item(
  id: 'id',
  name: name,
  type: type,
  seriesName: seriesName,
  indexNumber: indexNumber,
  parentIndexNumber: parentIndexNumber,
  productionYear: productionYear,
  status: status,
  endDate: endDate,
);

void main() {
  group('itemTitle', () {
    test('uses the series name for an episode', () {
      // Scanned at a distance on a shelf of Continue Watching, "The Expanse" is
      // what the viewer is looking for; the episode name is not.
      expect(
        itemTitle(
          _item(
            name: 'Leviathan Wakes',
            type: ItemKind.episode,
            seriesName: 'The Expanse',
          ),
        ),
        'The Expanse',
      );
    });

    test('falls back to the episode name when the series is unknown', () {
      expect(
        itemTitle(_item(name: 'Leviathan Wakes', type: ItemKind.episode)),
        'Leviathan Wakes',
      );
    });

    test('uses the item name for anything else', () {
      expect(itemTitle(_item(name: 'Arrival')), 'Arrival');
    });
  });

  group('episodeCode', () {
    test('needs both indices', () {
      expect(
        episodeCode(
          _item(type: ItemKind.episode, parentIndexNumber: 2, indexNumber: 4),
        ),
        'S2:E4',
      );
      expect(
        episodeCode(_item(type: ItemKind.episode, indexNumber: 4)),
        isEmpty,
      );
      expect(
        episodeCode(_item(type: ItemKind.episode, parentIndexNumber: 2)),
        isEmpty,
      );
    });
  });

  group('itemCaption', () {
    test('an episode is captioned by its code and its own name', () {
      expect(
        itemCaption(
          _item(
            name: 'Leviathan Wakes',
            type: ItemKind.episode,
            seriesName: 'The Expanse',
            parentIndexNumber: 1,
            indexNumber: 1,
          ),
        ),
        'S1:E1 · Leviathan Wakes',
      );
    });

    test('an episode without a code is captioned by its name alone', () {
      expect(
        itemCaption(_item(name: 'Pilot', type: ItemKind.episode)),
        'Pilot',
      );
    });

    test('a continuing series reads as open-ended', () {
      expect(
        itemCaption(
          _item(
            type: ItemKind.series,
            productionYear: 2015,
            status: 'Continuing',
          ),
        ),
        '2015–present',
      );
    });

    test('an ended series shows both years', () {
      expect(
        itemCaption(
          _item(
            type: ItemKind.series,
            productionYear: 2015,
            status: 'Ended',
            endDate: '2022-01-14T00:00:00.0000000Z',
          ),
        ),
        '2015–2022',
      );
    });

    test('a series that began and ended in one year shows it once', () {
      expect(
        itemCaption(
          _item(
            type: ItemKind.series,
            productionYear: 2019,
            status: 'Ended',
            endDate: '2019-06-01T00:00:00.0000000Z',
          ),
        ),
        '2019',
      );
    });

    test('an unparseable end date degrades to the start year', () {
      expect(
        itemCaption(
          _item(
            type: ItemKind.series,
            productionYear: 2015,
            status: 'Ended',
            endDate: 'not a date',
          ),
        ),
        '2015',
      );
    });

    test('a film is captioned by its year', () {
      expect(itemCaption(_item(productionYear: 2016)), '2016');
    });

    test('nothing is captioned when there is no year', () {
      expect(itemCaption(_item()), isEmpty);
    });
  });

  group('episodeSubtitle', () {
    test('is empty for anything that is not an episode', () {
      expect(episodeSubtitle(_item(name: 'Arrival')), isEmpty);
    });

    test('carries the code and the episode name', () {
      expect(
        episodeSubtitle(
          _item(
            name: 'Leviathan Wakes',
            type: ItemKind.episode,
            parentIndexNumber: 1,
            indexNumber: 1,
          ),
        ),
        'S1:E1 · Leviathan Wakes',
      );
    });
  });
}
