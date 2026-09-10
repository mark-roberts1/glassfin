/// Jellyfin's data model, scoped to movies and series.
///
/// Hand-rolled rather than generated from the OpenAPI spec: the surface Glassfin
/// needs is small and fixed, and a generated client brings a great deal of code
/// for endpoints this application will never call. If the scope ever widens past
/// movies and shows, revisit that trade.
///
/// Field names keep their Jellyfin spelling in `fromJson` so that the mapping
/// back to the API documentation stays obvious.
library;

import 'package:flutter/foundation.dart';

/// Ticks are 100-nanosecond units throughout the Jellyfin API.
const int ticksPerMs = 10000;

int ticksToMs(int ticks) => ticks ~/ ticksPerMs;
int msToTicks(int ms) => ms * ticksPerMs;

Duration ticksToDuration(int ticks) => Duration(microseconds: ticks ~/ 10);
int durationToTicks(Duration duration) => duration.inMicroseconds * 10;

enum ItemKind { movie, series, season, episode, unknown }

ItemKind _itemKind(String? raw) => switch (raw) {
  'Movie' => ItemKind.movie,
  'Series' => ItemKind.series,
  'Season' => ItemKind.season,
  'Episode' => ItemKind.episode,
  _ => ItemKind.unknown,
};

enum StreamType { video, audio, subtitle, embeddedImage, data, unknown }

StreamType _streamType(String? raw) => switch (raw) {
  'Video' => StreamType.video,
  'Audio' => StreamType.audio,
  'Subtitle' => StreamType.subtitle,
  'EmbeddedImage' => StreamType.embeddedImage,
  'Data' => StreamType.data,
  _ => StreamType.unknown,
};

/// How the server intends to deliver a subtitle track.
///
/// **This is the field subtitle switching is keyed on**, and the three cases
/// behave completely differently — see `CLAUDE.md`.
enum DeliveryMethod {
  /// A separate file mpv can sideload from a URL. Switching is instant.
  external$,

  /// Inside the container mpv already has open. Switching is instant.
  embed,

  /// Burned into the picture by the transcoder. Only the server can change it,
  /// which means a new `PlaybackInfo` and a reload.
  encode,

  hls,
  unknown,
}

DeliveryMethod _deliveryMethod(String? raw) => switch (raw) {
  'External' => DeliveryMethod.external$,
  'Embed' => DeliveryMethod.embed,
  'Encode' => DeliveryMethod.encode,
  'Hls' => DeliveryMethod.hls,
  _ => DeliveryMethod.unknown,
};

@immutable
class MediaStream {
  const MediaStream({
    required this.index,
    required this.type,
    this.codec,
    this.language,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.deliveryMethod = DeliveryMethod.unknown,
    this.deliveryUrl,
    this.width,
    this.height,
    this.videoRangeType,
    this.channels,
    this.channelLayout,
  });

  factory MediaStream.fromJson(Map<String, Object?> json) => MediaStream(
    index: json['Index'] as int? ?? -1,
    type: _streamType(json['Type'] as String?),
    codec: json['Codec'] as String?,
    language: json['Language'] as String?,
    displayTitle: json['DisplayTitle'] as String?,
    isDefault: json['IsDefault'] as bool? ?? false,
    isForced: json['IsForced'] as bool? ?? false,
    deliveryMethod: _deliveryMethod(json['DeliveryMethod'] as String?),
    deliveryUrl: json['DeliveryUrl'] as String?,
    width: json['Width'] as int?,
    height: json['Height'] as int?,
    videoRangeType: json['VideoRangeType'] as String?,
    channels: json['Channels'] as int?,
    channelLayout: json['ChannelLayout'] as String?,
  );

  /// Jellyfin's **absolute** index across all streams in the source. mpv counts
  /// per type instead; see `relativeStreamIndex`.
  final int index;
  final StreamType type;
  final String? codec;
  final String? language;
  final String? displayTitle;
  final bool isDefault;
  final bool isForced;
  final DeliveryMethod deliveryMethod;
  final String? deliveryUrl;

  final int? width;
  final int? height;
  final String? videoRangeType;

  final int? channels;
  final String? channelLayout;
}

@immutable
class MediaSource {
  const MediaSource({
    required this.id,
    this.name,
    this.container,
    this.protocol,
    this.supportsDirectPlay = false,
    this.supportsDirectStream = false,
    this.supportsTranscoding = false,
    this.transcodingUrl,
    this.runTimeTicks,
    this.mediaStreams = const [],
  });

  factory MediaSource.fromJson(Map<String, Object?> json) => MediaSource(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String?,
    container: json['Container'] as String?,
    protocol: json['Protocol'] as String?,
    supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
    supportsDirectStream: json['SupportsDirectStream'] as bool? ?? false,
    supportsTranscoding: json['SupportsTranscoding'] as bool? ?? false,
    transcodingUrl: json['TranscodingUrl'] as String?,
    runTimeTicks: json['RunTimeTicks'] as int?,
    mediaStreams: [
      for (final stream in json['MediaStreams'] as List? ?? const [])
        MediaStream.fromJson(stream as Map<String, Object?>),
    ],
  );

  final String id;
  final String? name;
  final String? container;
  final String? protocol;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final bool supportsTranscoding;

  /// Present exactly when the server decided to transcode.
  ///
  /// **This is the field audio switching is keyed on.** A transcode carries one
  /// audio track, so changing audio means asking the server again rather than
  /// switching a track inside mpv.
  final String? transcodingUrl;

  final int? runTimeTicks;
  final List<MediaStream> mediaStreams;

  bool get isTranscoding => transcodingUrl != null;

  Iterable<MediaStream> streamsOfType(StreamType type) =>
      mediaStreams.where((stream) => stream.type == type);
}

@immutable
class UserData {
  const UserData({
    this.playbackPositionTicks = 0,
    this.playCount = 0,
    this.played = false,
    this.isFavorite = false,
    this.unplayedItemCount,
    this.playedPercentage,
  });

  factory UserData.fromJson(Map<String, Object?> json) => UserData(
    playbackPositionTicks: json['PlaybackPositionTicks'] as int? ?? 0,
    playCount: json['PlayCount'] as int? ?? 0,
    played: json['Played'] as bool? ?? false,
    isFavorite: json['IsFavorite'] as bool? ?? false,
    unplayedItemCount: json['UnplayedItemCount'] as int?,
    playedPercentage: (json['PlayedPercentage'] as num?)?.toDouble(),
  );

  final int playbackPositionTicks;
  final int playCount;
  final bool played;
  final bool isFavorite;
  final int? unplayedItemCount;
  final double? playedPercentage;

  bool get hasResumePosition => playbackPositionTicks > 0;
}

@immutable
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.type,
    this.role,
    this.primaryImageTag,
  });

  factory Person.fromJson(Map<String, Object?> json) => Person(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
    type: json['Type'] as String? ?? '',
    role: json['Role'] as String?,
    primaryImageTag: json['PrimaryImageTag'] as String?,
  );

  final String id;
  final String name;
  final String type;
  final String? role;

  /// People carry a single tag rather than the `ImageTags` map items use, which
  /// is why they need their own image-URL helper.
  final String? primaryImageTag;
}

@immutable
class Item {
  const Item({
    required this.id,
    required this.name,
    required this.type,
    this.collectionType,
    this.overview,
    this.productionYear,
    this.officialRating,
    this.communityRating,
    this.criticRating,
    this.runTimeTicks,
    this.genres = const [],
    this.taglines = const [],
    this.studios = const [],
    this.people = const [],
    this.premiereDate,
    this.endDate,
    this.status,
    this.imageTags = const {},
    this.backdropImageTags = const [],
    this.userData,
    this.mediaSources = const [],
    this.seriesId,
    this.seriesName,
    this.seriesPrimaryImageTag,
    this.seasonId,
    this.seasonName,
    this.indexNumber,
    this.parentIndexNumber,
  });

  factory Item.fromJson(Map<String, Object?> json) => Item(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
    type: _itemKind(json['Type'] as String?),
    collectionType: json['CollectionType'] as String?,
    overview: json['Overview'] as String?,
    productionYear: json['ProductionYear'] as int?,
    officialRating: json['OfficialRating'] as String?,
    communityRating: (json['CommunityRating'] as num?)?.toDouble(),
    criticRating: (json['CriticRating'] as num?)?.toDouble(),
    runTimeTicks: json['RunTimeTicks'] as int?,
    genres: [for (final g in json['Genres'] as List? ?? const []) g as String],
    taglines: [
      for (final t in json['Taglines'] as List? ?? const []) t as String,
    ],
    studios: [
      for (final s in json['Studios'] as List? ?? const [])
        (s as Map<String, Object?>)['Name'] as String? ?? '',
    ],
    people: [
      for (final p in json['People'] as List? ?? const [])
        Person.fromJson(p as Map<String, Object?>),
    ],
    premiereDate: json['PremiereDate'] as String?,
    endDate: json['EndDate'] as String?,
    status: json['Status'] as String?,
    imageTags: {
      for (final entry
          in (json['ImageTags'] as Map<String, Object?>? ?? const {}).entries)
        entry.key: entry.value as String,
    },
    backdropImageTags: [
      for (final t in json['BackdropImageTags'] as List? ?? const [])
        t as String,
    ],
    userData: json['UserData'] == null
        ? null
        : UserData.fromJson(json['UserData'] as Map<String, Object?>),
    mediaSources: [
      for (final s in json['MediaSources'] as List? ?? const [])
        MediaSource.fromJson(s as Map<String, Object?>),
    ],
    seriesId: json['SeriesId'] as String?,
    seriesName: json['SeriesName'] as String?,
    seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String?,
    seasonId: json['SeasonId'] as String?,
    seasonName: json['SeasonName'] as String?,
    indexNumber: json['IndexNumber'] as int?,
    parentIndexNumber: json['ParentIndexNumber'] as int?,
  );

  final String id;
  final String name;
  final ItemKind type;
  final String? collectionType;
  final String? overview;
  final int? productionYear;
  final String? officialRating;
  final double? communityRating;
  final double? criticRating;
  final int? runTimeTicks;
  final List<String> genres;
  final List<String> taglines;
  final List<String> studios;
  final List<Person> people;
  final String? premiereDate;
  final String? endDate;
  final String? status;
  final Map<String, String> imageTags;
  final List<String> backdropImageTags;
  final UserData? userData;
  final List<MediaSource> mediaSources;

  final String? seriesId;
  final String? seriesName;

  /// An episode's series poster, which is what a card falls back to — episodes
  /// rarely have a poster of their own.
  final String? seriesPrimaryImageTag;

  final String? seasonId;
  final String? seasonName;
  final int? indexNumber;
  final int? parentIndexNumber;

  // Deliberately no ChildCount. The server sets it to whatever the endpoint
  // happens to be counting — seasons from /Items, recently added episodes from
  // /Items/Latest — so any single reading of it is wrong somewhere. Ask
  // /Shows/{id}/Seasons when a real season count is needed.

  /// Episodes play immediately; films and series open their detail screen.
  ///
  /// An episode in Continue Watching or Next Up is unambiguous, whereas a film
  /// has a resume point worth showing first and a series has no single obvious
  /// episode.
  bool get playsImmediately => type == ItemKind.episode;

  Duration? get runtime =>
      runTimeTicks == null ? null : ticksToDuration(runTimeTicks!);
}

@immutable
class ItemsPage {
  const ItemsPage({required this.items, required this.totalRecordCount});

  factory ItemsPage.fromJson(Map<String, Object?> json) => ItemsPage(
    items: [
      for (final item in json['Items'] as List? ?? const [])
        Item.fromJson(item as Map<String, Object?>),
    ],
    totalRecordCount: json['TotalRecordCount'] as int? ?? 0,
  );

  final List<Item> items;
  final int totalRecordCount;
}

@immutable
class PlaybackInfo {
  const PlaybackInfo({required this.mediaSources, required this.playSessionId});

  factory PlaybackInfo.fromJson(Map<String, Object?> json) => PlaybackInfo(
    mediaSources: [
      for (final s in json['MediaSources'] as List? ?? const [])
        MediaSource.fromJson(s as Map<String, Object?>),
    ],
    playSessionId: json['PlaySessionId'] as String? ?? '',
  );

  final List<MediaSource> mediaSources;
  final String playSessionId;
}

enum SegmentKind { intro, outro, recap, preview, commercial, unknown }

SegmentKind _segmentKind(String? raw) => switch (raw) {
  'Intro' => SegmentKind.intro,
  'Outro' => SegmentKind.outro,
  'Recap' => SegmentKind.recap,
  'Preview' => SegmentKind.preview,
  'Commercial' => SegmentKind.commercial,
  _ => SegmentKind.unknown,
};

/// An intro or credits marker.
///
/// Native in Jellyfin 10.10 and later; the Intro Skipper plugin supplies them
/// on earlier versions. A server with neither returns nothing, which is a normal
/// outcome and never an error.
@immutable
class MediaSegment {
  const MediaSegment({
    required this.type,
    required this.startTicks,
    required this.endTicks,
  });

  factory MediaSegment.fromJson(Map<String, Object?> json) => MediaSegment(
    type: _segmentKind(json['Type'] as String?),
    startTicks: json['StartTicks'] as int? ?? 0,
    endTicks: json['EndTicks'] as int? ?? 0,
  );

  final SegmentKind type;
  final int startTicks;
  final int endTicks;

  Duration get start => ticksToDuration(startTicks);
  Duration get end => ticksToDuration(endTicks);
}

@immutable
class Credentials {
  const Credentials({
    required this.address,
    required this.accessToken,
    required this.userId,
    required this.userName,
  });

  factory Credentials.fromJson(Map<String, Object?> json) => Credentials(
    address: json['address'] as String,
    accessToken: json['accessToken'] as String,
    userId: json['userId'] as String,
    userName: json['userName'] as String,
  );

  final String address;
  final String accessToken;
  final String userId;
  final String userName;

  Map<String, Object?> toJson() => {
    'address': address,
    'accessToken': accessToken,
    'userId': userId,
    'userName': userName,
  };
}

@immutable
class QuickConnectState {
  const QuickConnectState({required this.code, required this.secret});

  final String code;
  final String secret;
}
