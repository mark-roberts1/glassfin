import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/jellyfin/media_badges.dart';
import 'package:glassfin/jellyfin/models.dart';

MediaStream _video({int? height, String? codec, String? range}) => MediaStream(
  index: 0,
  type: StreamType.video,
  height: height,
  codec: codec,
  videoRangeType: range,
);

MediaStream _audio({
  int index = 1,
  String? codec,
  int? channels,
  String? layout,
  bool isDefault = false,
}) => MediaStream(
  index: index,
  type: StreamType.audio,
  codec: codec,
  channels: channels,
  channelLayout: layout,
  isDefault: isDefault,
);

MediaStream _subtitle(int index, String? language) =>
    MediaStream(index: index, type: StreamType.subtitle, language: language);

Item _itemWith(List<MediaStream> streams) => Item(
  id: 'id',
  name: 'Item',
  type: ItemKind.movie,
  mediaSources: [MediaSource(id: 'source', mediaStreams: streams)],
);

void main() {
  group('resolutionLabel', () {
    test('bands by height', () {
      expect(resolutionLabel(_video(height: 2160)), '4K');
      expect(resolutionLabel(_video(height: 1440)), '1440p');
      expect(resolutionLabel(_video(height: 1080)), '1080p');
      expect(resolutionLabel(_video(height: 720)), '720p');
      expect(resolutionLabel(_video(height: 480)), 'SD');
    });

    test('a letterboxed 4K scope frame still reads as 4K', () {
      // 2.39:1 at 4K is 3840×1608, which is below the 2000 threshold — the
      // banding is deliberately generous for exactly this case.
      expect(resolutionLabel(_video(height: 2160)), '4K');
      // And a 1080p scope frame must not fall out of the 1080p band.
      expect(resolutionLabel(_video(height: 804)), '720p');
    });

    test('is null when the height is unknown', () {
      expect(resolutionLabel(_video()), isNull);
      expect(resolutionLabel(_video(height: 0)), isNull);
    });
  });

  group('rangeLabel', () {
    test('both Dolby Vision spellings collapse to one label', () {
      expect(rangeLabel(_video(range: 'DOVI')), 'Dolby Vision');
      expect(rangeLabel(_video(range: 'DOVIWithHDR10')), 'Dolby Vision');
    });

    test('SDR has no badge at all', () {
      expect(rangeLabel(_video(range: 'SDR')), isNull);
      expect(rangeLabel(_video()), isNull);
    });
  });

  group('codecLabel', () {
    test('writes codec names as they are written', () {
      expect(codecLabel('hevc'), 'HEVC');
      expect(codecLabel('h265'), 'HEVC');
      expect(codecLabel('h264'), 'H.264');
      expect(codecLabel('eac3'), 'E-AC-3');
      expect(codecLabel('truehd'), 'TrueHD');
    });

    test('an unknown codec is upper-cased rather than dropped', () {
      expect(codecLabel('wmv3'), 'WMV3');
    });

    test('is null when there is no codec', () {
      expect(codecLabel(null), isNull);
      expect(codecLabel(''), isNull);
    });
  });

  group('channelLabel', () {
    test('prefers the layout the file states', () {
      expect(
        channelLabel(_audio(layout: '5.1(side)', channels: 6)),
        '5.1(SIDE)',
      );
    });

    test('falls back to a count', () {
      expect(channelLabel(_audio(channels: 2)), 'Stereo');
      expect(channelLabel(_audio(channels: 6)), '5.1');
      expect(channelLabel(_audio(channels: 8)), '7.1');
      expect(channelLabel(_audio(channels: 3)), '3ch');
      expect(channelLabel(_audio()), isNull);
    });
  });

  group('mediaBadges', () {
    test('describes the default audio track, not the first', () {
      // The default is the one that will actually play, so it is the one worth
      // describing above the fold.
      final badges = mediaBadges(
        _itemWith([
          _video(height: 1080, codec: 'h264'),
          _audio(index: 1, codec: 'aac', channels: 2),
          _audio(index: 2, codec: 'truehd', channels: 8, isDefault: true),
        ]),
      );
      expect(badges.audio, ['TrueHD', '7.1']);
    });

    test('falls back to the first audio track when none is marked default', () {
      final badges = mediaBadges(
        _itemWith([
          _video(height: 1080, codec: 'h264'),
          _audio(index: 1, codec: 'aac', channels: 2),
        ]),
      );
      expect(badges.audio, ['AAC', 'Stereo']);
    });

    test('subtitle languages are distinct and keep stream order', () {
      final badges = mediaBadges(
        _itemWith([
          _video(height: 1080),
          _subtitle(1, 'eng'),
          _subtitle(2, 'fra'),
          _subtitle(3, 'eng'),
          _subtitle(4, null),
        ]),
      );
      expect(badges.subtitleLanguages, ['eng', 'fra']);
    });

    test(
      'an item with no media sources yields nothing rather than throwing',
      () {
        final badges = mediaBadges(
          const Item(id: 'id', name: 'Item', type: ItemKind.movie),
        );
        expect(badges.isEmpty, isTrue);
        expect(badges.subtitleLanguages, isEmpty);
      },
    );

    test('video badges run resolution, range, codec', () {
      final badges = mediaBadges(
        _itemWith([_video(height: 2160, codec: 'hevc', range: 'HDR10')]),
      );
      expect(badges.video, ['4K', 'HDR10', 'HEVC']);
    });
  });
}
