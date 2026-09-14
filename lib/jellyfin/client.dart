/// The Jellyfin server API, scoped to movies and series.
///
/// Ported from `glassfin_old/web/src/lib/jellyfin.ts`. **Playback decisions are
/// not made here.** The device profile goes to `/Items/{id}/PlaybackInfo` and
/// the server decides direct play, direct stream, or transcode; this class only
/// carries the answer back.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/audio_settings.dart';
import '../settings/video_settings.dart';
import 'device_profile.dart';
import 'models.dart';

const String clientName = 'Glassfin';
const String clientVersion = '0.2.0';

/// Thrown for anything the viewer might need told about.
class JellyfinException implements Exception {
  const JellyfinException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Accepts `nas:8096` as readily as a full URL; trailing slashes are noise.
///
/// Typing a server address on a D-pad is the single most tedious moment in the
/// application, so it forgives as much as it can.
String normaliseAddress(String address) {
  final trimmed = address.trim().replaceAll(RegExp(r'/+$'), '');
  final hasScheme = RegExp(
    r'^https?://',
    caseSensitive: false,
  ).hasMatch(trimmed);
  return hasScheme ? trimmed : 'http://$trimmed';
}

class Jellyfin {
  Jellyfin({
    required this.credentials,
    required this.deviceId,
    required this.video,
    required this.audio,
    this.deviceName = clientName,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Credentials credentials;
  final String deviceId;

  /// What the server shows in its dashboard's session list.
  final String deviceName;

  final http.Client _http;

  /// Mutable, and read on every `playbackInfo` call rather than cached into a
  /// profile at construction — so changing a transcoding setting takes effect on
  /// the next thing played instead of after a restart.
  VideoSettings video;
  AudioSettings audio;

  void close() => _http.close();

  /// Jellyfin's own authorisation scheme. The header is required even on calls
  /// made before there is a token — that is how the server identifies the client
  /// during sign-in.
  static String authHeader({
    required String deviceId,
    required String deviceName,
    String? token,
  }) {
    final parts = [
      'Client="$clientName"',
      'Device="$deviceName"',
      'DeviceId="$deviceId"',
      'Version="$clientVersion"',
      if (token != null) 'Token="$token"',
    ];
    return 'MediaBrowser ${parts.join(', ')}';
  }

  String get _auth => authHeader(
    deviceId: deviceId,
    deviceName: deviceName,
    token: credentials.accessToken,
  );

  Uri _uri(String path, [Map<String, Object?> params = const {}]) {
    final base = Uri.parse(credentials.address + path);
    return base.replace(
      queryParameters: {
        for (final entry in params.entries)
          if (entry.value != null) entry.key: '${entry.value}',
      },
    );
  }

  Future<T> _request<T>(
    String path, {
    String method = 'GET',
    Map<String, Object?> params = const {},
    Object? body,
    required T Function(Object? json) parse,
  }) async {
    final uri = _uri(path, params);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': _auth,
    };

    final response = switch (method) {
      'POST' => await _http.post(uri, headers: headers, body: jsonEncode(body)),
      _ => await _http.get(uri, headers: headers),
    };

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException(
        '$method $path failed (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
      return parse(null);
    }
    return parse(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  // ---------------------------------------------------------------------------
  // Sign-in
  // ---------------------------------------------------------------------------

  static Future<Credentials> authenticate({
    required String address,
    required String username,
    required String password,
    required String deviceId,
    String deviceName = clientName,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final base = normaliseAddress(address);
    try {
      final response = await client.post(
        Uri.parse('$base/Users/AuthenticateByName'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authHeader(
            deviceId: deviceId,
            deviceName: deviceName,
          ),
        },
        body: jsonEncode({'Username': username, 'Pw': password}),
      );

      if (response.statusCode != 200) {
        throw JellyfinException(
          response.statusCode == 401
              ? 'That username or password was not accepted.'
              : 'The server refused the sign-in (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      return _credentialsFrom(base, response.bodyBytes);
    } finally {
      if (httpClient == null) client.close();
    }
  }

  // ---- Quick Connect --------------------------------------------------------
  //
  // The television answer to signing in: the server shows a code, someone
  // approves it from a phone or the web dashboard, and no password is ever typed
  // on a D-pad. The server address still has to be entered once, which is what
  // the on-screen keyboard is for.

  static Future<bool> quickConnectEnabled(
    String address, {
    required String deviceId,
    String deviceName = clientName,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('${normaliseAddress(address)}/QuickConnect/Enabled'),
        headers: {
          'Authorization': authHeader(
            deviceId: deviceId,
            deviceName: deviceName,
          ),
        },
      );
      if (response.statusCode != 200) return false;
      return jsonDecode(utf8.decode(response.bodyBytes)) == true;
    } catch (_) {
      // An unreachable or ancient server simply has no Quick Connect; that is
      // not worth an error, it just means offering the password form instead.
      return false;
    } finally {
      if (httpClient == null) client.close();
    }
  }

  /// Starts a Quick Connect request and returns the code to display.
  ///
  /// Initiate moved from GET to POST across Jellyfin releases, so this tries the
  /// current shape and falls back rather than pinning users to one server
  /// version.
  static Future<QuickConnectState> quickConnectInitiate(
    String address, {
    required String deviceId,
    String deviceName = clientName,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final base = normaliseAddress(address);
    final headers = {
      'Authorization': authHeader(deviceId: deviceId, deviceName: deviceName),
    };
    try {
      final uri = Uri.parse('$base/QuickConnect/Initiate');
      var response = await client.post(uri, headers: headers);
      if (response.statusCode == 404 || response.statusCode == 405) {
        response = await client.get(uri, headers: headers);
      }
      if (response.statusCode != 200) {
        throw const JellyfinException(
          'This server would not start a Quick Connect request.',
        );
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      return QuickConnectState(
        code: body['Code'] as String? ?? '',
        secret: body['Secret'] as String? ?? '',
      );
    } finally {
      if (httpClient == null) client.close();
    }
  }

  /// True once someone has approved the code.
  static Future<bool> quickConnectApproved(
    String address,
    String secret, {
    required String deviceId,
    String deviceName = clientName,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('${normaliseAddress(address)}/QuickConnect/Connect')
            .replace(queryParameters: {'secret': secret}),
        headers: {
          'Authorization': authHeader(
            deviceId: deviceId,
            deviceName: deviceName,
          ),
        },
      );
      if (response.statusCode != 200) {
        throw const JellyfinException(
          'The Quick Connect request expired. Start a new one.',
        );
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      return body['Authenticated'] == true;
    } finally {
      if (httpClient == null) client.close();
    }
  }

  static Future<Credentials> authenticateWithQuickConnect(
    String address,
    String secret, {
    required String deviceId,
    String deviceName = clientName,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final base = normaliseAddress(address);
    try {
      final response = await client.post(
        Uri.parse('$base/Users/AuthenticateWithQuickConnect'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authHeader(
            deviceId: deviceId,
            deviceName: deviceName,
          ),
        },
        body: jsonEncode({'Secret': secret}),
      );
      if (response.statusCode != 200) {
        throw JellyfinException(
          'The server refused the sign-in (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      return _credentialsFrom(base, response.bodyBytes);
    } finally {
      if (httpClient == null) client.close();
    }
  }

  static Credentials _credentialsFrom(String address, List<int> bodyBytes) {
    final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, Object?>;
    final user = body['User'] as Map<String, Object?>? ?? const {};
    return Credentials(
      address: address,
      accessToken: body['AccessToken'] as String? ?? '',
      userId: user['Id'] as String? ?? '',
      userName: user['Name'] as String? ?? '',
    );
  }

  // ---------------------------------------------------------------------------
  // Library
  // ---------------------------------------------------------------------------

  /// Only the libraries Glassfin understands. Music and live TV are out of
  /// scope, and showing a library that cannot be opened is worse than hiding it.
  Future<List<Item>> libraries() async {
    final page = await _request(
      '/UserViews',
      params: {'userId': credentials.userId},
      parse: (json) => ItemsPage.fromJson(json as Map<String, Object?>),
    );
    return page.items
        .where(
          (view) =>
              const {'movies', 'tvshows'}.contains(view.collectionType ?? ''),
        )
        .toList();
  }

  Future<List<Item>> resume({int limit = 12}) async {
    final page = await _request(
      '/UserItems/Resume',
      params: {
        'userId': credentials.userId,
        'limit': limit,
        'mediaTypes': 'Video',
        'includeItemTypes': 'Movie,Episode',
        'fields': 'PrimaryImageAspectRatio,Overview',
        'enableImageTypes': 'Primary,Backdrop,Thumb',
      },
      parse: (json) => ItemsPage.fromJson(json as Map<String, Object?>),
    );
    return page.items;
  }

  Future<List<Item>> nextUp({int limit = 16}) async {
    final page = await _request(
      '/Shows/NextUp',
      params: {
        'userId': credentials.userId,
        'limit': limit,
        'fields': 'PrimaryImageAspectRatio,Overview',
        'enableImageTypes': 'Primary,Backdrop,Thumb',
      },
      parse: (json) => ItemsPage.fromJson(json as Map<String, Object?>),
    );
    return page.items;
  }

  /// Note: `/Items/Latest` returns a bare array, not the usual paged shape.
  Future<List<Item>> latest(String parentId, {int limit = 20}) => _request(
    '/Items/Latest',
    params: {
      'userId': credentials.userId,
      'parentId': parentId,
      'limit': limit,
      'fields': 'PrimaryImageAspectRatio',
      'enableImageTypes': 'Primary,Backdrop,Thumb',
    },
    parse: (json) => [
      for (final item in json as List? ?? const [])
        Item.fromJson(item as Map<String, Object?>),
    ],
  );

  Future<ItemsPage> items(Map<String, Object?> query) => _request(
    '/Items',
    params: {
      'userId': credentials.userId,
      'recursive': true,
      'fields': 'PrimaryImageAspectRatio,Overview,Genres',
      'enableImageTypes': 'Primary,Backdrop,Thumb',
      ...query,
    },
    parse: (json) => ItemsPage.fromJson(json as Map<String, Object?>),
  );

  Future<Item> item(String id) => _request(
    '/Items/$id',
    params: {
      'userId': credentials.userId,
      'fields':
          'People,Studios,Taglines,Overview,Genres,MediaSources,MediaStreams',
    },
    parse: (json) => Item.fromJson(json as Map<String, Object?>),
  );

  Future<List<Item>> seasons(String seriesId) async {
    final page = await _request(
      '/Shows/$seriesId/Seasons',
      params: {
        'userId': credentials.userId,
        'fields': 'PrimaryImageAspectRatio',
      },
      parse: (json) => ItemsPage.fromJson(json as Map<String, Object?>),
    );
    return page.items;
  }

  Future<List<Item>> episodes(String seriesId, {String? seasonId}) async {
    final page = await _request(
      '/Shows/$seriesId/Episodes',
      params: {
        'userId': credentials.userId,
        'seasonId': seasonId,
        'fields': 'Overview,PrimaryImageAspectRatio',
      },
      parse: (json) => ItemsPage.fromJson(json as Map<String, Object?>),
    );
    return page.items;
  }

  Future<List<Item>> search(String term, {int limit = 40}) async {
    final page = await items({
      'searchTerm': term,
      'includeItemTypes': 'Movie,Series',
      'limit': limit,
    });
    return page.items;
  }

  /// Intro and credits markers.
  ///
  /// Absent on servers older than 10.10 without the Intro Skipper plugin, which
  /// is **not an error** — it just means nothing gets skipped. Swallowing the
  /// failure here keeps that out of every caller.
  Future<List<MediaSegment>> mediaSegments(String itemId) async {
    try {
      return await _request(
        '/MediaSegments/$itemId',
        params: {'includeSegmentTypes': 'Intro,Outro'},
        parse: (json) => [
          for (final segment
              in (json as Map<String, Object?>?)?['Items'] as List? ?? const [])
            MediaSegment.fromJson(segment as Map<String, Object?>),
        ],
      );
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Images
  // ---------------------------------------------------------------------------

  /// The URL for one of an item's images, or **null when there is no image**.
  ///
  /// That null is load-bearing: it is what drives every placeholder in the
  /// interface. Returning a URL that 404s instead would give every artless item
  /// a broken-image box.
  String? imageUrl(
    Item item, {
    String type = 'Primary',
    int? maxWidth,
    int? maxHeight,
  }) {
    var id = item.id;
    String? tag = item.imageTags[type];

    // Episodes usually have no poster of their own; borrow the series'.
    if (type == 'Primary' &&
        tag == null &&
        item.seriesPrimaryImageTag != null &&
        item.seriesId != null) {
      id = item.seriesId!;
      tag = item.seriesPrimaryImageTag;
    }
    if (type == 'Backdrop') {
      tag = item.backdropImageTags.isEmpty
          ? null
          : item.backdropImageTags.first;
    }
    if (tag == null) return null;

    return _uri('/Items/$id/Images/$type', {
      'tag': tag,
      'quality': 90,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
    }).toString();
  }

  /// People carry `PrimaryImageTag` rather than the `ImageTags` map, so they
  /// need their own helper.
  String? personImageUrl(Person person, {int maxWidth = 300}) {
    final tag = person.primaryImageTag;
    if (tag == null) return null;
    return _uri('/Items/${person.id}/Images/Primary', {
      'tag': tag,
      'quality': 90,
      'maxWidth': maxWidth,
    }).toString();
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  /// Asks the server how to play something, and with which tracks.
  ///
  /// Track indices matter *here*, not only at load time. When the server decides
  /// to transcode it transcodes **one** audio track, so changing audio means
  /// asking again with a different `AudioStreamIndex` rather than switching a
  /// track inside mpv. The same is true of a subtitle it has burned in.
  Future<PlaybackInfo> playbackInfo(
    String itemId, {
    int startTicks = 0,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) => _request(
    '/Items/$itemId/PlaybackInfo',
    method: 'POST',
    params: {'userId': credentials.userId},
    body: {
      'UserId': credentials.userId,
      'StartTimeTicks': startTicks,
      'AutoOpenLiveStream': true,
      'DeviceProfile': buildDeviceProfile(video: video, audio: audio),
      'AudioStreamIndex': ?audioStreamIndex,
      'SubtitleStreamIndex': ?subtitleStreamIndex,
    },
    parse: (json) => PlaybackInfo.fromJson(json as Map<String, Object?>),
  );

  /// Subtitle delivery URLs come back server-relative, and **mpv is not a
  /// browser** — it has no page to resolve them against.
  String absoluteUrl(String path) =>
      RegExp(r'^https?://', caseSensitive: false).hasMatch(path)
      ? path
      : credentials.address + path;

  /// The absolute URL mpv should open, honouring whatever the server decided.
  String streamUrl(MediaSource source, String playSessionId) {
    final transcodingUrl = source.transcodingUrl;
    if (transcodingUrl != null) return credentials.address + transcodingUrl;

    return _uri('/Videos/${source.id}/stream', {
      'static': true,
      'mediaSourceId': source.id,
      'playSessionId': playSessionId,
      // Direct play hands the URL to mpv, which does not send our auth header,
      // so the token has to travel in the query string.
      'api_key': credentials.accessToken,
    }).toString();
  }

  // ---- Progress -------------------------------------------------------------
  //
  // Getting this wrong is how resume points and watched state rot, so it stays
  // explicit rather than clever.

  Future<void> reportStart(
    String itemId,
    String playSessionId,
    int positionTicks,
  ) => _request(
    '/Sessions/Playing',
    method: 'POST',
    body: {
      'ItemId': itemId,
      'PlaySessionId': playSessionId,
      'PositionTicks': positionTicks,
    },
    parse: (_) {},
  );

  Future<void> reportProgress(
    String itemId,
    String playSessionId,
    int positionTicks, {
    required bool isPaused,
  }) => _request(
    '/Sessions/Playing/Progress',
    method: 'POST',
    body: {
      'ItemId': itemId,
      'PlaySessionId': playSessionId,
      'PositionTicks': positionTicks,
      'IsPaused': isPaused,
    },
    parse: (_) {},
  );

  Future<void> reportStopped(
    String itemId,
    String playSessionId,
    int positionTicks,
  ) => _request(
    '/Sessions/Playing/Stopped',
    method: 'POST',
    body: {
      'ItemId': itemId,
      'PlaySessionId': playSessionId,
      'PositionTicks': positionTicks,
    },
    parse: (_) {},
  );
}
